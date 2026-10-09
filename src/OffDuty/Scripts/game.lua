-- Unreal helpers shared by Off Duty's modules. Construct on the game thread only.
-- Rules learned in the probe (docs/phase0-findings.md):
-- - a Lua reference doesn't keep a UObject alive: never cache one in Lua (class default objects of
--   native classes are permanent, so those are the exception);
-- - never write a soft-object property (crashes UE4SS 3.0.1);
-- - load classes through the engine (Kismet soft class path), never UE4SS LoadAsset.
local M = {}

M.EFFECTS_DIR = "/Game/OffDuty/Effects/"
M.FATIGUE = "GE_OffDuty_Fatigue"
M.DEPLOYED = "GE_OffDuty_Deployed"
M.LOSE_AP = "GE_OffDuty_LoseAP"
M.ACCURACY = "/Game/Game/GameData/Progression/NextMissionGameplayEffects/"
    .. "GE_Lose_NextMission_RangedAccuracy.GE_Lose_NextMission_RangedAccuracy_C"
M.PLAYER_TEAM = "/Game/Game/GameData/Teams/PlayerTeam.PlayerTeam_C"
M.MAX_SAFE_INJURIES = 2 -- a third injury kills; Off Duty never adds injuries

function M.new(log)
    local g = {}

    function g.unwrap(value)
        if value == nil then return nil end
        local ok, inner = pcall(function() return value:get() end)
        if ok and inner ~= nil then return inner end
        return value
    end

    function g.valid(object)
        object = g.unwrap(object)
        if object == nil then return false end
        local ok, result = pcall(function() return object:IsValid() end)
        return ok and result == true
    end

    -- Excludes class default objects and archetypes.
    function g.live(object)
        if not g.valid(object) then return false end
        local ok, flagged = pcall(function() return object:HasAnyFlags(0x30) end)
        return ok and flagged == false
    end

    function g.full_name(object)
        local ok, value = pcall(function() return g.unwrap(object):GetFullName() end)
        return ok and tostring(value) or "<unnamed>"
    end

    function g.address(object)
        local ok, value = pcall(function() return g.unwrap(object):GetAddress() end)
        return ok and value or nil
    end

    function g.text(value)
        value = g.unwrap(value)
        if value == nil then return nil end
        local t = type(value)
        if t == "string" or t == "number" or t == "boolean" then return tostring(value) end
        local ok, s = pcall(function() return value:ToString() end)
        return ok and s ~= nil and tostring(s) or nil
    end

    -- Rich text to plain ("Tesh <Bold_Color>Hawks</>" -> "Tesh Hawks").
    function g.plain(rich)
        return ((rich or ""):gsub("<[^>]*>", ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    function g.guid_string(guid)
        guid = g.unwrap(guid)
        if guid == nil then return nil end
        local ok, a, b, c, d = pcall(function() return guid.A, guid.B, guid.C, guid.D end)
        if not ok or type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" or type(d) ~= "number" then
            return nil
        end
        local function u32(n) if n < 0 then return n + 4294967296 end return n end
        return string.format("%08X-%08X-%08X-%08X", u32(a), u32(b), u32(c), u32(d))
    end

    -- A standalone copy of an FGuid (never hold array/iterator-backed wrappers).
    function g.guid_copy(guid)
        guid = g.unwrap(guid)
        if guid == nil then return nil end
        local ok, a, b, c, d = pcall(function() return guid.A, guid.B, guid.C, guid.D end)
        if not ok or type(a) ~= "number" then return nil end
        return { A = a, B = b, C = c, D = d }
    end

    function g.array_each(array, callback)
        array = g.unwrap(array)
        if array == nil then return end
        local ok, count = pcall(function() return array:GetArrayNum() end)
        -- UE4SS 3.0.1 can hang in TArray:ForEach on an empty array.
        if not ok or type(count) ~= "number" or count <= 0 then return end
        pcall(function() array:ForEach(function(index, element) callback(index, g.unwrap(element)) end) end)
    end

    -- UFunction returns may arrive as a TArray wrapper or a plain Lua table.
    function g.to_list(value)
        value = g.unwrap(value)
        local items = {}
        if type(value) == "table" then
            for _, element in ipairs(value) do items[#items + 1] = g.unwrap(element) end
        else
            g.array_each(value, function(_, element) items[#items + 1] = element end)
        end
        return items
    end

    function g.tag_names(container)
        local names = {}
        pcall(function()
            g.array_each(g.unwrap(container).GameplayTags, function(_, tag) names[#names + 1] = g.text(tag.TagName) or "?" end)
        end)
        return names
    end

    -- Calls a reflected function; returns (result, nil) or (nil, error). Always one result: wrap the
    -- call in parentheses where it's passed on, e.g. tonumber((g.call(...))).
    function g.call(object, method, ...)
        if object == nil then return nil, "no object" end
        local args = { ... }
        local ok, result = pcall(function() return object[method](object, table.unpack(args)) end)
        if ok then return g.unwrap(result), nil end
        return nil, tostring(result)
    end

    local cdos = {}
    function g.cdo(path)
        if not g.valid(cdos[path]) then
            local ok, object = pcall(StaticFindObject, path)
            cdos[path] = ok and g.valid(object) and object or nil
        end
        return cdos[path]
    end
    function g.roster_statics() return g.cdo("/Script/Bruno.Default__BrunoRosterStatics") end
    function g.game_statics() return g.cdo("/Script/BitReactorGame.Default__BitReactorGameStatics") end
    function g.unit_statics() return g.cdo("/Script/BitReactorGame.Default__BitReactorGameStatics_Unit") end
    function g.ability_library() return g.cdo("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary") end
    function g.scripting() return g.cdo("/Script/BitReactorGame.Default__BitReactorAbilityScriptingFunctions") end
    function g.kismet() return g.cdo("/Script/Engine.Default__KismetSystemLibrary") end

    function g.find_live(class_name)
        local ok, objects = pcall(FindAllOf, class_name)
        if not ok or objects == nil then return nil end
        for _, object in pairs(objects) do
            if g.live(object) then return object end
        end
        return nil
    end

    function g.world_context()
        return g.find_live("BrunoMissionCentral") or g.find_live("BrunoStrategyTurnManager")
            or g.find_live("BrunoRosterManager")
    end

    function g.is_actor(object)
        local ok, result = pcall(function() return g.unwrap(object):IsA("/Script/Engine.Actor") end)
        return ok and result == true
    end

    function g.character_name(actor)
        if not g.is_actor(actor) then return nil end -- the native getter takes an AActor*
        local name = g.text((g.call(g.game_statics(), "GetActorCharacterFullName", actor)))
        return name ~= "" and name or nil
    end

    function g.character_id(actor)
        if not g.is_actor(actor) then return nil end
        return g.guid_string((g.call(g.game_statics(), "GetActorCharacterID", actor)))
    end

    function g.asc(actor)
        local asc = (g.call(g.ability_library(), "GetAbilitySystemComponent", actor))
        return g.valid(asc) and asc or nil
    end

    -- A class by path, through the engine (already in memory, else a blocking soft-class load).
    function g.load_class(path)
        local ok, found = pcall(StaticFindObject, path)
        if ok and g.valid(found) then return found end
        local kismet = g.kismet()
        if not kismet then return nil end
        local soft_path = (g.call(kismet, "MakeSoftClassPath", path))
        local soft_ref = soft_path ~= nil and (g.call(kismet, "Conv_SoftClassPathToSoftClassRef", soft_path)) or nil
        local class = soft_ref ~= nil and (g.call(kismet, "LoadClassAsset_Blocking", soft_ref)) or nil
        return g.valid(class) and class or nil
    end

    function g.effect_class(name)
        return g.load_class(M.EFFECTS_DIR .. name .. "." .. name .. "_C")
    end

    function g.effect_count(asc, class)
        if not asc or not class then return 0 end
        return tonumber((g.call(asc, "GetGameplayEffectCount", class, nil, true))) or 0
    end

    function g.apply_effect(asc, class, times)
        local err
        for _ = 1, times or 1 do
            _, err = g.call(asc, "BP_ApplyGameplayEffectToSelf", class, 1.0, (g.call(asc, "MakeEffectContext")))
            if err then return err end
        end
        return nil
    end

    function g.remove_effect(asc, class, stacks)
        local _, err = g.call(g.scripting(), "RemoveEffectByClass", asc, class, stacks)
        return err
    end

    -- Sets a stackable effect to exactly `target` stacks; returns the new count.
    function g.set_effect_count(asc, class, target)
        local current = g.effect_count(asc, class)
        local err
        if current < target then err = g.apply_effect(asc, class, target - current)
        elseif current > target then err = g.remove_effect(asc, class, current - target) end
        if err then log("WARNING: could not set %s to %d stacks | %s", g.full_name(class), target, err) end
        return g.effect_count(asc, class)
    end

    -- Roster members: { guid, id, away, actor (may be nil) }.
    function g.roster(wco)
        local members = {}
        local guids = {}
        for _, guid in ipairs(g.to_list((g.call(g.roster_statics(), "GetRoster", wco)))) do
            guids[#guids + 1] = g.guid_copy(guid)
        end
        if #guids == 0 then
            local manager = g.find_live("BrunoRosterManager")
            local ok, roster = pcall(function() return manager.Roster end)
            for _, guid in ipairs(g.to_list(ok and roster or nil)) do guids[#guids + 1] = g.guid_copy(guid) end
        end
        for _, guid in ipairs(guids) do
            local actor = (g.call(g.roster_statics(), "GetRosterCharacterByCharacterID", wco, guid))
            members[#members + 1] = {
                guid = guid,
                id = g.guid_string(guid),
                away = (g.call(g.roster_statics(), "IsCharacterAwayByCharacterID", wco, guid)) == true,
                actor = g.valid(actor) and actor or nil,
            }
        end
        return members
    end

    function g.roster_ids(wco)
        local ids = {}
        for _, member in ipairs(g.roster(wco)) do if member.id then ids[member.id] = true end end
        return ids
    end

    return g
end

return M
