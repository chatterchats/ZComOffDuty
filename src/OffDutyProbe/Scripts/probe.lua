-- Off Duty Probe: diagnostics for the Phase 0 open questions.
-- Read-only apart from Ctrl+Shift+T, which adds one native next-mission effect.
-- Never iterates reflected TMaps (known access-violation risk in this build).
local M = {}

local RESULT_EFFECTS = "/Game/Game/GameData/Abilities/ResultEffects/"
local NEXT_MISSION_EFFECTS = "/Game/Game/GameData/Progression/NextMissionGameplayEffects/"
local function class_path(directory, name) return directory .. name .. "." .. name .. "_C" end

local TRACKED_EFFECTS = {
    { label = "Injured", path = class_path(RESULT_EFFECTS, "GE_Injured") },
    { label = "NM_LoseAccuracy", path = class_path(NEXT_MISSION_EFFECTS, "GE_Lose_NextMission_RangedAccuracy") },
    { label = "NM_LoseMaxHealth", path = class_path(NEXT_MISSION_EFFECTS, "GE_Lose_NextMission_LoseMaxHealth") },
}
local COMBAT_ATTRIBUTES = {
    "ActionPoints", "RefreshActionPoints", "MovementActionPoints", "RefreshMovementActionPoints",
    "MovementPerAP", "SpecialActionPoints", "ClassTacticPoints",
    "Aim", "Accuracy", "MaxAccuracy", "AccuracyReduction",
}
local HEALTH_ATTRIBUTES = { "Health", "MaxHealth" }

local ROSTER_TILE = "/Game/Game/UI/Strategy/_Common/Widgets/WBP_RosterTile.WBP_RosterTile_C"
local SQUAD_SELECT = "/Game/Game/UI/Strategy/SquadSelect/BPs/VM_SquadSelect.VM_SquadSelect_C"

-- Answers: when next-mission effects are added/applied/cleared (Q4), whether
-- squad assignment reaches CanAssignToMissionSquad through ProcessEvent (Q3),
-- and the turn/mission boundaries fatigue will key off.
local NATIVE_HOOKS = {
    "/Script/Bruno.BrunoStrategyTurnManager:BeginStrategyTurn",
    "/Script/Bruno.BrunoStrategyTurnManager:EndStrategyTurn",
    "/Script/Bruno.BrunoMissionCentral:CompleteMission",
    "/Script/Bruno.BrunoMissionCentral:FailMission",
    "/Script/Bruno.BrunoMissionCentral:CanAssignToMissionSquad",
    "/Script/Bruno.BrunoGameStatics:AddNextMissionCharacterEffect",
    "/Script/Bruno.BrunoGameStatics:AddNextMissionEffect",
    "/Script/Bruno.BrunoGameStatics:ApplyNextMissionEffectsToCharacter",
    "/Script/Bruno.BrunoGameStatics:ClearNextMissionEffects",
}
-- Blueprint classes load with their screens, so these install lazily.
local BLUEPRINT_HOOKS = {
    ROSTER_TILE .. ":IsRosterTileSelectable",
    SQUAD_SELECT .. ":OnAddButtonClicked",
    SQUAD_SELECT .. ":OnCharacterSlotClicked",
    SQUAD_SELECT .. ":OnRemoveButtonClicked",
}

function M.start(runtime, actions, logger, config)
    local log = function(...) logger:log(...) end
    local installed, call_counts = {}, {}

    local function unwrap(value)
        if value == nil then return nil end
        local ok, inner = pcall(function() return value:get() end)
        if ok and inner ~= nil then return inner end
        return value
    end

    local function valid(object)
        object = unwrap(object)
        if object == nil then return false end
        local ok, result = pcall(function() return object:IsValid() end)
        return ok and result == true
    end

    local function live(object)
        -- Excludes class default objects and archetypes.
        if not valid(object) then return false end
        local ok, flagged = pcall(function() return object:HasAnyFlags(0x30) end)
        return ok and flagged == false
    end

    local function full_name(object)
        local ok, value = pcall(function() return unwrap(object):GetFullName() end)
        return ok and tostring(value) or "<unnamed>"
    end

    local function text(value)
        value = unwrap(value)
        if value == nil then return nil end
        local t = type(value)
        if t == "string" or t == "number" or t == "boolean" then return tostring(value) end
        local ok, s = pcall(function() return value:ToString() end)
        return ok and s ~= nil and tostring(s) or nil
    end

    local function guid_copy(guid)
        guid = unwrap(guid)
        if guid == nil then return nil end
        local ok, a, b, c, d = pcall(function() return guid.A, guid.B, guid.C, guid.D end)
        if not ok or type(a) ~= "number" or type(b) ~= "number"
            or type(c) ~= "number" or type(d) ~= "number" then
            return nil
        end
        -- A standalone value: never hold array/iterator-backed wrappers.
        return { A = a, B = b, C = c, D = d }
    end

    local function guid_string(guid)
        local g = guid_copy(guid)
        if g == nil then return nil end
        local function u32(n) if n < 0 then return n + 4294967296 end return n end
        return string.format("%08X-%08X-%08X-%08X", u32(g.A), u32(g.B), u32(g.C), u32(g.D))
    end

    local function array_each(array, callback)
        array = unwrap(array)
        if array == nil then return end
        local ok, count = pcall(function() return array:GetArrayNum() end)
        -- UE4SS 3.0.1 can hang in TArray:ForEach on an empty array.
        if not ok or type(count) ~= "number" or count <= 0 then return end
        pcall(function()
            array:ForEach(function(index, element) callback(index, unwrap(element)) end)
        end)
    end

    local cdos = {}
    local function cdo(path)
        if not valid(cdos[path]) then
            local ok, object = pcall(StaticFindObject, path)
            cdos[path] = ok and valid(object) and object or nil
        end
        return cdos[path]
    end
    local function roster_statics() return cdo("/Script/Bruno.Default__BrunoRosterStatics") end
    local function game_statics() return cdo("/Script/BitReactorGame.Default__BitReactorGameStatics") end
    local function unit_statics() return cdo("/Script/BitReactorGame.Default__BitReactorGameStatics_Unit") end
    local function bruno_statics() return cdo("/Script/Bruno.Default__BrunoGameStatics") end
    local function ability_library() return cdo("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary") end

    local function call(object, method, ...)
        if object == nil then return nil, "no object" end
        local args = { ... }
        local ok, result = pcall(function() return object[method](object, table.unpack(args)) end)
        if ok then return unwrap(result), nil end
        return nil, tostring(result)
    end

    local function find_live(class_name)
        local ok, objects = pcall(FindAllOf, class_name)
        if not ok or objects == nil then return nil end
        for _, object in pairs(objects) do
            if live(object) then return object end
        end
        return nil
    end

    local function world_context()
        return find_live("BrunoMissionCentral")
            or find_live("BrunoStrategyTurnManager")
            or find_live("BrunoRosterManager")
            or find_live("BRGameMissionActor")
    end

    local function is_actor(object)
        local ok, result = pcall(function() return unwrap(object):IsA("/Script/Engine.Actor") end)
        return ok and result == true
    end

    local function character_name(actor)
        -- The native getter takes an AActor*; never hand it anything else.
        if not is_actor(actor) then return nil end
        local name = text(select(1, call(game_statics(), "GetActorCharacterFullName", actor)))
        if name and name ~= "" then return name end
        return nil
    end

    local function load_class(path)
        local ok, class = pcall(StaticFindObject, path)
        if ok and valid(class) then return class end
        if type(LoadAsset) == "function" then
            pcall(LoadAsset, (path:gsub("%.[^.]+$", "")))
            ok, class = pcall(StaticFindObject, path)
            if ok and valid(class) then return class end
        end
        return nil
    end

    local function describe(value)
        value = unwrap(value)
        local t = type(value)
        if t ~= "userdata" and t ~= "table" then return tostring(value) end
        local guid = guid_string(value)
        if guid then return "guid:" .. guid end
        local ok, name = pcall(function() return value:GetFullName() end)
        if ok and type(name) == "string" then
            local display = character_name(value)
            return display and (name .. " [" .. display .. "]") or name
        end
        return text(value) or tostring(value)
    end

    local function should_log(path)
        local n = (call_counts[path] or 0) + 1
        call_counts[path] = n
        return n <= config.log_first_calls or n % config.log_every_nth_call == 0, n
    end

    local install_blueprint_hooks -- defined below; screens load after startup

    local function hook_logger(path, phase)
        local turn_begin = phase == "post" and path:find(":BeginStrategyTurn$") ~= nil
        return function(context, ...)
            if turn_begin then
                actions:schedule_after("blueprint_hooks", 0, function() install_blueprint_hooks("turn begin") end)
            end
            local ok_log, n = should_log(path .. phase)
            if not ok_log then return end
            local parts = {}
            for index = 1, select("#", ...) do
                parts[#parts + 1] = describe((select(index, ...)))
            end
            log("HOOK %s #%d | %s | self=%s | args=(%s)",
                phase, n, path, describe(context), table.concat(parts, ", "))
        end
    end

    local function install(path)
        if installed[path] then return true end
        local ok, err = pcall(function()
            runtime:register_hook(path, hook_logger(path, "pre"), hook_logger(path, "post"))
        end)
        if ok then
            installed[path] = true
            log("Hook installed | %s", path)
        end
        return ok, err
    end

    function install_blueprint_hooks(reason)
        for _, path in ipairs(BLUEPRINT_HOOKS) do
            if not installed[path] then
                local class_path_only = path:match("^(.-):")
                local ok, class = pcall(StaticFindObject, class_path_only)
                if ok and valid(class) then
                    local done, err = install(path)
                    if not done then log("Blueprint hook failed | %s | %s", path, tostring(err)) end
                end
            end
        end
        local pending = 0
        for _, path in ipairs(BLUEPRINT_HOOKS) do if not installed[path] then pending = pending + 1 end end
        if pending > 0 then log("Blueprint hooks pending (screen not loaded yet) | %d | after %s", pending, reason) end
    end

    local function attribute_summary(set, names)
        local parts = {}
        for _, name in ipairs(names) do
            local ok, base, current = pcall(function()
                local data = set[name]
                return data.BaseValue, data.CurrentValue
            end)
            if ok and type(base) == "number" then
                parts[#parts + 1] = base == current
                    and string.format("%s=%g", name, base)
                    or string.format("%s=%g/%g", name, base, current)
            end
        end
        return table.concat(parts, " ")
    end

    local function owning_actor(set)
        local ok, outer = pcall(function() return unwrap(set:GetOuter()) end)
        if not ok or not valid(outer) then return nil end
        if is_actor(outer) then return outer end
        local owner_ok, owner = pcall(function() return unwrap(outer:GetOwner()) end)
        if owner_ok and valid(owner) then return owner end
        return nil
    end

    local function attribute_sets(class_name)
        local by_actor = {}
        local ok, sets = pcall(FindAllOf, class_name)
        if not ok or sets == nil then return by_actor end
        for _, set in pairs(sets) do
            if live(set) then
                local actor = owning_actor(set)
                if actor then
                    local address = select(2, pcall(function() return actor:GetAddress() end))
                    if address then by_actor[address] = { actor = actor, set = set } end
                end
            end
        end
        return by_actor
    end

    local function effect_summary(actor)
        local asc = select(1, call(ability_library(), "GetAbilitySystemComponent", actor))
        if not valid(asc) then return "asc=unavailable" end
        local parts = {}
        for _, effect in ipairs(TRACKED_EFFECTS) do
            local class = load_class(effect.path)
            if class then
                local count, err = call(asc, "GetGameplayEffectCount", class, nil, true)
                parts[#parts + 1] = string.format("%s=%s", effect.label, err and "err" or tostring(count))
            end
        end
        return table.concat(parts, " ")
    end

    local function next_mission_map_count()
        -- Count only; iterating this TMap is unsafe.
        local instance = find_live("BrunoGameInstance")
        if not instance then return "game instance unavailable" end
        local ok, count = pcall(function() return #instance.StrategyData.NextMissionCharacterEffects end)
        return ok and tostring(count) or ("unreadable: " .. tostring(count))
    end

    local function to_list(value)
        -- UFunction returns may arrive as a TArray wrapper or a plain Lua table.
        value = unwrap(value)
        local items = {}
        if type(value) == "table" then
            for _, element in ipairs(value) do items[#items + 1] = unwrap(element) end
        else
            array_each(value, function(_, element) items[#items + 1] = element end)
        end
        return items
    end

    local function roster_guids(wco)
        local guids, notes = {}, {}
        local result, err = call(roster_statics(), "GetRoster", wco)
        for _, guid in ipairs(to_list(result)) do guids[#guids + 1] = guid_copy(guid) end
        notes[#notes + 1] = string.format("GetRoster type=%s count=%d%s",
            type(result), #guids, err and (" err=" .. err) or "")
        if #guids == 0 then
            local manager = find_live("BrunoRosterManager")
            if manager then
                local ok, roster = pcall(function() return manager.Roster end)
                for _, guid in ipairs(to_list(ok and roster or nil)) do guids[#guids + 1] = guid_copy(guid) end
                notes[#notes + 1] = string.format("RosterManager.Roster ok=%s type=%s count=%d",
                    tostring(ok), type(roster), #guids)
            else
                notes[#notes + 1] = "RosterManager not found"
            end
        end
        return guids, table.concat(notes, " | ")
    end

    -- Every roster operator: {guid, id, actor (or nil), away, source}.
    local function roster_members(wco)
        local guids, notes = roster_guids(wco)
        local by_id = {}
        for _, entry in pairs(attribute_sets("BitReactorCombatSet")) do
            local id = guid_string(select(1, call(game_statics(), "GetActorCharacterID", entry.actor)))
            if id then by_id[id] = entry.actor end
        end
        local members = {}
        for _, guid in ipairs(guids) do
            local id = guid_string(guid)
            local actor = select(1, call(roster_statics(), "GetRosterCharacterByCharacterID", wco, guid))
            local source = "GetRosterCharacterByCharacterID"
            if not valid(actor) then actor, source = by_id[id], "attribute-set scan" end
            local away = select(1, call(roster_statics(), "IsCharacterAwayByCharacterID", wco, guid))
            members[#members + 1] = {
                guid = guid, id = id, away = away == true,
                actor = valid(actor) and actor or nil, source = valid(actor) and source or "none",
            }
        end
        return members, notes
    end

    local function dump(reason)
        log("==== DUMP (%s) ====", reason)
        local wco = world_context()
        log("World context | %s", wco and full_name(wco) or "none")
        local turn_manager = find_live("BrunoStrategyTurnManager")
        if turn_manager then
            log("Strategy turn | %s", tostring(select(1, call(turn_manager, "GetStrategyTurn"))))
        end
        log("GameInstance.StrategyData.NextMissionCharacterEffects entries | %s", next_mission_map_count())

        local combat = attribute_sets("BitReactorCombatSet")
        local health = attribute_sets("BitReactorHealthSet")
        local listed = {}

        local function report(actor, address, header)
            listed[address] = true
            local id = guid_string(select(1, call(game_statics(), "GetActorCharacterID", actor))) or "?"
            local name = character_name(actor) or full_name(actor)
            local injuries = select(1, call(unit_statics(), "GetUnitInjuryCount", actor))
            local available = select(1, call(unit_statics(), "IsUnitAvailable", actor))
            log("%s | %s | id=%s | injuries=%s | available=%s",
                header, name, id, tostring(injuries), tostring(available))
            local c, h = combat[address], health[address]
            log("    combat: %s", c and attribute_summary(c.set, COMBAT_ATTRIBUTES) or "no BitReactorCombatSet")
            log("    health: %s", h and attribute_summary(h.set, HEALTH_ATTRIBUTES) or "no BitReactorHealthSet")
            log("    effects: %s", effect_summary(actor))
        end

        if wco and roster_statics() then
            local members, notes = roster_members(wco)
            log("Roster size | %d | %s", #members, notes)
            for _, member in ipairs(members) do
                local header = "ROSTER" .. (member.away and " (Away)" or "")
                if member.actor then
                    local address = select(2, pcall(function() return member.actor:GetAddress() end))
                    report(member.actor, address, header .. " via " .. member.source)
                else
                    log("%s | id=%s | no live actor", header, tostring(member.id))
                end
            end
        end

        -- Tactical units (and anything with combat attributes not on the roster).
        for address, entry in pairs(combat) do
            if not listed[address] then
                local player = select(1, call(unit_statics(), "IsPlayerTeamMember", entry.actor))
                if player == true then report(entry.actor, address, "PLAYER UNIT") end
            end
        end
        log("==== END DUMP ====")
        install_blueprint_hooks("dump")
    end

    local function apply_test()
        local wco = world_context()
        local statics = roster_statics()
        if not wco or not statics then log("TEST | no world context / roster statics (load a campaign first)"); return end
        local wanted = tostring(config.test_character_name or ""):lower()
        local members, notes = roster_members(wco)
        local target_guid, target_name
        for _, member in ipairs(members) do
            local name = member.actor and (character_name(member.actor) or full_name(member.actor)) or nil
            local match = wanted ~= "" and name ~= nil and name:lower():find(wanted, 1, true) ~= nil
            if match or (wanted == "" and not member.away) then
                target_guid, target_name = member.guid, name or ("id " .. tostring(member.id))
                break
            end
        end
        if not target_guid then
            log("TEST | no roster operator matched '%s' | roster=%d | %s", wanted, #members, notes)
            return
        end
        local effect_path = class_path(NEXT_MISSION_EFFECTS, config.test_effect)
        local class = load_class(effect_path)
        if not class then log("TEST | effect class unavailable | %s", effect_path); return end
        local _, err = call(bruno_statics(), "AddNextMissionCharacterEffect",
            wco, target_guid, class, config.test_magnitude)
        log("TEST | AddNextMissionCharacterEffect | %s | %s | magnitude=%s | %s",
            target_name, config.test_effect, tostring(config.test_magnitude), err or "ok")
        log("TEST | Deploy this operator, then press Ctrl+Shift+D in the mission to read AccuracyReduction/MaxHealth and hit chances.")
        log("TEST | GameInstance next-mission entries now | %s", next_mission_map_count())
    end

    for _, path in ipairs(NATIVE_HOOKS) do
        local ok, err = install(path)
        if not ok then log("Native hook failed | %s | %s", path, tostring(err)) end
    end
    install_blueprint_hooks("startup")

    runtime:register_keybind(Key.D, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("dump", 0, function() dump("Ctrl+Shift+D") end)
    end)
    runtime:register_keybind(Key.T, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("test", 0, apply_test)
    end)
    log("Ready | Ctrl+Shift+D = dump roster/units + install screen hooks | Ctrl+Shift+T = apply test next-mission effect")
end

return M
