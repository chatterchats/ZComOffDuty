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
    { label = "OD_Fatigue", path = "/Game/OffDuty/Effects/GE_OffDuty_Fatigue.GE_OffDuty_Fatigue_C" },
    { label = "OD_Exhausted", path = "/Game/OffDuty/Effects/GE_OffDuty_Exhausted.GE_OffDuty_Exhausted_C" },
    { label = "OD_Spent", path = "/Game/OffDuty/Effects/GE_OffDuty_Spent.GE_OffDuty_Spent_C" },
}
-- Ctrl+Shift+1/2/3: queue a tier's next-mission penalty (accuracy = stacks of the game's -5% effect).
local TIERS = {
    { name = "Tired", accuracy_stacks = 1 },
    { name = "Exhausted", accuracy_stacks = 2, effect = "GE_OffDuty_Exhausted" },
    { name = "Spent", accuracy_stacks = 3, effect = "GE_OffDuty_Spent" },
}
-- Off Duty's own effect: Content/Paks/~mods/OffDuty_P.* (a Linux cook, remapped onto /Game).
local FATIGUE_EFFECT = "/Game/OffDuty/Effects/GE_OffDuty_Fatigue.GE_OffDuty_Fatigue_C"
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
    -- Save/load flow (delegate-bound UFUNCTIONs run through ProcessEvent).
    "/Script/Bruno.BrunoSaveGameSubsystem:OnPreLoadMap",
    "/Script/Bruno.BrunoSaveGameSubsystem:OnPostLoadMap",
    "/Script/Bruno.BrunoSaveGameSubsystem:OnWorldMatchStarting",
    "/Script/Bruno.BrunoSaveGameSubsystem:SaveGame",
    "/Script/Bruno.BrunoStrategySaveGame:GatherSaveInfo",
    "/Script/Bruno.BrunoStrategySaveGame:ApplySaveInfo",
}
-- Pre-hooks that make sure GE_OffDuty_Fatigue is loaded before a save is applied: a map change's
-- garbage collection unloads it (nothing in the game references it), and the hub save then drops it.
local PRELOAD_BEFORE = {
    ["/Script/Bruno.BrunoSaveGameSubsystem:OnPostLoadMap"] = true,
    ["/Script/Bruno.BrunoSaveGameSubsystem:OnWorldMatchStarting"] = true,
    ["/Script/Bruno.BrunoStrategySaveGame:ApplySaveInfo"] = true,
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

    -- Classes load through the engine (a soft class path), never UE4SS's LoadAsset: for a ~mods
    -- pak whose registry the game never merged, LoadAsset returned a pointer that crashed on use.
    local kismet_system = nil
    local function engine_load_class(path)
        if not valid(kismet_system) then
            local ok, object = pcall(StaticFindObject, "/Script/Engine.Default__KismetSystemLibrary")
            kismet_system = ok and valid(object) and object or nil
        end
        if not kismet_system then return nil, "KismetSystemLibrary unavailable" end
        local soft_path, err = call(kismet_system, "MakeSoftClassPath", path)
        if err then return nil, "MakeSoftClassPath: " .. err end
        local soft_ref
        soft_ref, err = call(kismet_system, "Conv_SoftClassPathToSoftClassRef", soft_path)
        if err then return nil, "Conv_SoftClassPathToSoftClassRef: " .. err end
        local class
        class, err = call(kismet_system, "LoadClassAsset_Blocking", soft_ref)
        if err then return nil, "LoadClassAsset_Blocking: " .. err end
        return class, nil
    end

    local function load_class(path)
        local ok, class = pcall(StaticFindObject, path)
        if ok and valid(class) then return class, "already in memory" end
        local loaded, err = engine_load_class(path)
        if err then log("load_class(%s) | %s", path, err) end
        -- Re-find by path rather than trusting the returned wrapper.
        ok, class = pcall(StaticFindObject, path)
        if ok and valid(class) then return class, "loaded now" end
        return nil
    end

    -- Run 4: where the remapped fatigue class lives. Lookups only; nothing touches unverified objects.
    local function diagnose_fatigue_load()
        for _, path in ipairs({
            "/Game/OffDuty/Effects/GE_OffDuty_Fatigue.GE_OffDuty_Fatigue_C",
            "/Game/OffDuty/Effects/GE_OffDuty_Fatigue.Default__GE_OffDuty_Fatigue_C",
            "/Game/OffDuty/Effects/GE_OffDuty_Fatigue",
            "/OffDuty/OffDuty/Effects/GE_OffDuty_Fatigue.GE_OffDuty_Fatigue_C",
            "/OffDuty/OffDuty/Effects/GE_OffDuty_Fatigue",
        }) do
            local ok, result = pcall(StaticFindObject, path)
            local found = ok and valid(result)
            log("  StaticFindObject(%s) -> %s", path, found and ("FOUND " .. full_name(result)) or (ok and "nil" or ("error " .. tostring(result))))
        end
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
        local preload = phase == "pre" and PRELOAD_BEFORE[path]
        return function(context, ...)
            if preload then
                local class, residency = load_class(FATIGUE_EFFECT)
                log("PRELOAD | %s | fatigue class %s", path:match(":(.+)$"), class and residency or "NOT FOUND")
            end
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

    local function effect_defaults(class_path_value)
        local cdo_path = class_path_value:gsub("%.([^.]+)$", ".Default__%1")
        local ok, defaults = pcall(StaticFindObject, cdo_path)
        if not ok or not valid(defaults) then return cdo_path .. " | not in memory" end
        local parts = { (cdo_path:match("Default__([^.]+)$")) }
        for _, name in ipairs({ "bIncludeInSaveData", "bTerminateWithCombat", "DurationPolicy", "StackingType", "StackLimitCount" }) do
            local read_ok, value = pcall(function() return defaults[name] end)
            parts[#parts + 1] = name .. "=" .. (read_ok and tostring(value) or "unreadable")
        end
        return table.concat(parts, " ")
    end

    -- The game's own "keep these loaded" list: UBrunoSaveGameSubsystem.TrackedPreloadObjects.CachedObjects
    -- (a transient TArray<UObject*> on a game-instance subsystem, so it survives map-change GC).
    local function preload_list()
        local subsystem = find_live("BrunoSaveGameSubsystem")
        if not subsystem then return nil, "BrunoSaveGameSubsystem not found" end
        local ok, tracked = pcall(function() return unwrap(subsystem.TrackedPreloadObjects) end)
        if not ok or not valid(tracked) then return nil, "TrackedPreloadObjects unavailable" end
        local cached_ok, cached = pcall(function() return tracked.CachedObjects end)
        if not cached_ok or cached == nil then return nil, "CachedObjects unreadable" end
        return tracked, cached
    end

    local function preload_summary(class)
        local tracked, cached = preload_list()
        if not tracked then return cached end
        local count = select(2, pcall(function() return cached:GetArrayNum() end))
        local present = false
        if class then
            local target = select(2, pcall(function() return class:GetAddress() end))
            array_each(cached, function(_, object)
                local address = select(2, pcall(function() return object:GetAddress() end))
                if address == target then present = true end
            end)
        end
        local strategy = select(2, pcall(function() return #tracked.StrategyDerivatives end))
        local tactical = select(2, pcall(function() return #tracked.TacticalDerivatives end))
        return string.format("CachedObjects=%s (fatigue class %s) | StrategyDerivatives=%s | TacticalDerivatives=%s",
            tostring(count), present and "PRESENT" or "absent", tostring(strategy), tostring(tactical))
    end

    -- Ctrl+Shift+K: append GE_OffDuty_Fatigue to CachedObjects so map-change GC can't unload it.
    local function keep_fatigue_loaded()
        local class = load_class(FATIGUE_EFFECT)
        if not class then log("KEEP | fatigue class not loadable"); return end
        local tracked, cached = preload_list()
        if not tracked then log("KEEP | %s", tostring(cached)); return end
        local before = select(2, pcall(function() return cached:GetArrayNum() end))
        local ok, err = pcall(function() cached[before + 1] = class end)
        log("KEEP | append ok=%s%s | %s", tostring(ok), ok and "" or (" error " .. tostring(err)), preload_summary(class))
    end

    local function dump(reason)
        log("==== DUMP (%s) ====", reason)
        local wco = world_context()
        log("World context | %s", wco and full_name(wco) or "none")
        local fatigue_class, residency = load_class(FATIGUE_EFFECT)
        if fatigue_class then
            log("Off Duty fatigue class | loaded: %s | %s", full_name(fatigue_class), residency)
            for _, path in ipairs({ FATIGUE_EFFECT, class_path(RESULT_EFFECTS, "GE_Injured") }) do
                log("    defaults %s", effect_defaults(path))
            end
            log("    preload list | %s", preload_summary(fatigue_class))
        else
            log("Off Duty fatigue class | NOT FOUND at %s", FATIGUE_EFFECT)
            diagnose_fatigue_load()
        end
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

    -- Ctrl+Shift+F / Ctrl+Shift+G: one fatigue stack on/off every roster operator with a live actor.
    local function change_fatigue(add)
        local wco = world_context()
        if not wco or not roster_statics() then log("FATIGUE | no world context (load a campaign first)"); return end
        local class = load_class(FATIGUE_EFFECT)
        if not class then log("FATIGUE | GE_OffDuty_Fatigue not loadable; is SWZeroCompany/Mods/OffDuty installed?"); return end
        local remover = cdo("/Script/BitReactorGame.Default__BitReactorAbilityScriptingFunctions")
        local members = roster_members(wco)
        local changed = 0
        for _, member in ipairs(members) do
            if member.actor then
                local name = character_name(member.actor) or full_name(member.actor)
                local asc = select(1, call(ability_library(), "GetAbilitySystemComponent", member.actor))
                if valid(asc) then
                    local err
                    if add then
                        local context = select(1, call(asc, "MakeEffectContext"))
                        _, err = call(asc, "BP_ApplyGameplayEffectToSelf", class, 1.0, context)
                    else
                        _, err = call(remover, "RemoveEffectByClass", asc, class, 1)
                    end
                    local stacks = select(1, call(asc, "GetGameplayEffectCount", class, nil, true))
                    log("FATIGUE | %s | %s | stacks now %s%s", add and "+1" or "-1", name, tostring(stacks), err and (" | error " .. err) or "")
                    changed = changed + 1
                else
                    log("FATIGUE | %s | no ability system component", name)
                end
            end
        end
        log("FATIGUE | %s on %d operator(s) with a live actor (roster %d)", add and "added" or "removed", changed, #members)
    end

    -- Ctrl+Shift+U (squad select): what the injury banner lists. Each WBP_InjuryWarningEntry binds a
    -- BrunoGameplayEffectListViewModel and shows its effects' stack count; its EffectQuery decides
    -- which effects count. Also prints GE_Injured's and our fatigue effect's tags for comparison.
    local function tag_names(container)
        local names = {}
        pcall(function()
            array_each(unwrap(container).GameplayTags, function(_, tag)
                names[#names + 1] = text(tag.TagName) or "?"
            end)
        end)
        return #names > 0 and table.concat(names, ", ") or "-"
    end

    local function tag_query(query)
        local tags, tokens = {}, {}
        pcall(function()
            array_each(query.TagDictionary, function(_, tag) tags[#tags + 1] = text(tag.TagName) or "?" end)
        end)
        pcall(function()
            array_each(query.QueryTokenStream, function(_, byte) tokens[#tokens + 1] = tostring(byte) end)
        end)
        if #tags == 0 and #tokens == 0 then return "empty" end
        return string.format("tags [%s] tokens [%s]", table.concat(tags, ", "), table.concat(tokens, " "))
    end

    local function effect_tags(label, default_object_path)
        local defaults = cdo(default_object_path)
        if not defaults then log("UI | %s | not loaded (%s)", label, default_object_path); return end
        local parts = {}
        pcall(function()
            array_each(defaults.GEComponents, function(_, component)
                local name = full_name(component):match("^(%S+)") or "?"
                local detail = ""
                for _, field in ipairs({ "InheritableAssetTags", "InheritableGrantedTagsContainer",
                                         "InheritableBlockedAbilityTagsContainer" }) do
                    local ok, value = pcall(function() return component[field] end)
                    if ok and value ~= nil then
                        local tags = tag_names(value.CombinedTags)
                        if tags ~= "-" then detail = detail .. string.format(" %s=[%s]", field, tags) end
                    end
                end
                parts[#parts + 1] = name .. detail
            end)
        end)
        log("UI | %s | components: %s", label, #parts > 0 and table.concat(parts, " | ") or "none")
    end

    local function dump_injury_ui()
        log("UI | ---- injury banner dump ----")
        local ok, lists = pcall(FindAllOf, "BrunoGameplayEffectListViewModel")
        local count = 0
        for _, list in pairs(ok and lists or {}) do
            if live(list) then
                count = count + 1
                local q_ok, query = pcall(function() return list.EffectQuery end)
                if q_ok and query ~= nil then
                    local fields = {}
                    for _, field in ipairs({ "OwningTagQuery", "EffectTagQuery", "SourceAggregateTagQuery",
                                             "SourceTagQuery" }) do
                        local f_ok, value = pcall(function() return query[field] end)
                        if f_ok and value ~= nil then fields[#fields + 1] = field .. "=" .. tag_query(value) end
                    end
                    local def_ok, definition = pcall(function() return query.EffectDefinition end)
                    fields[#fields + 1] = "EffectDefinition=" .. (def_ok and valid(definition) and full_name(definition) or "none")
                    local attr_ok, attribute = pcall(function() return text(query.ModifyingAttribute.AttributeName) end)
                    fields[#fields + 1] = "ModifyingAttribute=" .. (attr_ok and attribute or "?")
                    log("UI | list %d %s | query: %s", count, full_name(list), table.concat(fields, " | "))
                else
                    log("UI | list %d %s | EffectQuery unreadable: %s", count, full_name(list), tostring(query))
                end
                local effects = to_list(select(1, call(list, "GetEffectViewModels")))
                log("UI | list %d | %d effect view model(s)", count, #effects)
                for _, vm in ipairs(effects) do
                    local function field(name)
                        local f_ok, value = pcall(function() return vm[name] end)
                        return f_ok and text(value) or "?"
                    end
                    log("UI |   effect %s | stacks %s/%s | notification %s | asset tags [%s] | granted [%s]",
                        field("DisplayableEffectName"), field("CurrentStackCount"), field("StackLimit"),
                        select(2, pcall(function() return text(vm.NotificationTag.TagName) end)) or "?",
                        tag_names(select(2, pcall(function() return vm.AssetTags end))),
                        tag_names(select(2, pcall(function() return vm.GrantedTags end))))
                end
            end
        end
        log("UI | %d live effect list view model(s)%s", count,
            count == 0 and " (open squad select with an injured operator first)" or "")
        effect_tags("GE_Injured", "/Game/Game/GameData/Abilities/ResultEffects/GE_Injured.Default__GE_Injured_C")
        effect_tags("GE_OffDuty_Fatigue", "/Game/OffDuty/Effects/GE_OffDuty_Fatigue.Default__GE_OffDuty_Fatigue_C")
    end

    -- Ctrl+Shift+I: control for the save test; one GE_Injured stack on the first operator with an actor.
    local function apply_control_injury()
        local wco = world_context()
        if not wco or not roster_statics() then log("CONTROL | no world context (load a campaign first)"); return end
        local class = load_class(class_path(RESULT_EFFECTS, "GE_Injured"))
        if not class then log("CONTROL | GE_Injured not loadable"); return end
        for _, member in ipairs((roster_members(wco))) do
            if member.actor then
                local name = character_name(member.actor) or full_name(member.actor)
                local asc = select(1, call(ability_library(), "GetAbilitySystemComponent", member.actor))
                if valid(asc) then
                    local context = select(1, call(asc, "MakeEffectContext"))
                    local _, err = call(asc, "BP_ApplyGameplayEffectToSelf", class, 1.0, context)
                    local stacks = select(1, call(asc, "GetGameplayEffectCount", class, nil, true))
                    log("CONTROL | +1 GE_Injured | %s | stacks now %s%s", name, tostring(stacks), err and (" | error " .. err) or "")
                    return
                end
            end
        end
        log("CONTROL | no operator with an ability system component")
    end

    local function queue_tier(level)
        local tier = TIERS[level]
        local wco = world_context()
        if not wco or not roster_statics() then log("TIER | no world context (load a campaign first)"); return end
        local accuracy = load_class(class_path(NEXT_MISSION_EFFECTS, "GE_Lose_NextMission_RangedAccuracy"))
        local extra = tier.effect and load_class("/Game/OffDuty/Effects/" .. tier.effect .. "." .. tier.effect .. "_C") or nil
        if not accuracy or (tier.effect and not extra) then log("TIER | effect classes not loadable"); return end
        local queued = 0
        for _, member in ipairs((roster_members(wco))) do
            if not member.away then
                local name = member.actor and (character_name(member.actor) or full_name(member.actor)) or ("id " .. tostring(member.id))
                local err
                for _ = 1, tier.accuracy_stacks do
                    _, err = call(bruno_statics(), "AddNextMissionCharacterEffect", wco, member.guid, accuracy, 1)
                end
                if extra and not err then
                    _, err = call(bruno_statics(), "AddNextMissionCharacterEffect", wco, member.guid, extra, 1)
                end
                log("TIER | %s queued for %s%s", tier.name, name, err and (" | error " .. err) or "")
                queued = queued + 1
            end
        end
        log("TIER | %s queued on %d operator(s) for their next mission | next-mission entries %s | press once: reload the save to undo",
            tier.name, queued, next_mission_map_count())
    end

    -- AP-loss experiment: roll at each player operator's team turn start (Exhausted/Spent only).
    local TURN_HOOK = "/Script/BitReactorGame.BitReactorAbilitySystemComponent:OnTeamTurnStarted"
    local LOSE_AP = "/Game/OffDuty/Effects/GE_OffDuty_LoseAP.GE_OffDuty_LoseAP_C"
    local PLAYER_TEAM = "/Game/Game/GameData/Teams/PlayerTeam.PlayerTeam_C"
    local seen_teams = {}
    pcall(function() math.randomseed(os.time()) end)

    local function action_points(actor)
        local entry = attribute_sets("BitReactorCombatSet")[select(2, pcall(function() return actor:GetAddress() end))]
        if not entry then return "?" end
        local ok, value = pcall(function() return entry.set.ActionPoints.CurrentValue end)
        return ok and tostring(value) or "?"
    end

    local function fatigue_tier(asc)
        for _, tier in ipairs({ "Spent", "Exhausted" }) do
            local class = load_class("/Game/OffDuty/Effects/GE_OffDuty_" .. tier .. ".GE_OffDuty_" .. tier .. "_C")
            local count = class and select(1, call(asc, "GetGameplayEffectCount", class, nil, true)) or 0
            if (tonumber(count) or 0) > 0 then return tier end
        end
        return nil
    end

    local function on_team_turn_started(context, team)
        local asc = unwrap(context)
        local team_class = unwrap(team)
        local team_name = team_class and full_name(team_class) or "?"
        if not seen_teams[team_name] then
            seen_teams[team_name] = true
            log("TURN | team turn started: %s", team_name)
        end
        -- Exact class: WorldTeam_PrePlayer also starts a turn each round (before AP refill), and a
        -- substring match on "player" rolled twice per round.
        if not team_name:find(PLAYER_TEAM, 1, true) then return end
        if not valid(asc) then return end
        local owner = select(1, call(asc, "GetOwner"))
        if not valid(owner) or select(1, call(unit_statics(), "IsPlayerTeamMember", owner)) ~= true then return end
        local tier = fatigue_tier(asc)
        if not tier then return end
        local chance = config.test_ap_loss_chance or config.ap_loss_chance[tier] or 0
        local name = character_name(owner) or full_name(owner)
        local ap_at_hook = action_points(owner)
        if math.random() >= chance then
            log("AP ROLL | %s | %s | %.0f%% | safe | AP %s", name, tier, chance * 100, ap_at_hook)
            return
        end
        actions:schedule_after("ap_loss", config.ap_loss_delay_ms, function()
            if not valid(asc) or not valid(owner) then return end
            local class = load_class(LOSE_AP)
            if not class then log("AP LOSS | GE_OffDuty_LoseAP not loadable"); return end
            local before = action_points(owner)
            local context_handle = select(1, call(asc, "MakeEffectContext"))
            local _, err = call(asc, "BP_ApplyGameplayEffectToSelf", class, 1.0, context_handle)
            log("AP LOSS | %s | %s | %.0f%% | AP at hook %s, before %s, after %s%s",
                name, tier, chance * 100, ap_at_hook, before, action_points(owner), err and (" | error " .. err) or "")
        end, asc, owner)
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
    do
        local ok, err = pcall(function() runtime:register_hook(TURN_HOOK, function() end, on_team_turn_started) end)
        log("AP-loss hook %s | %s%s", ok and "installed" or "FAILED", TURN_HOOK, ok and "" or (" | " .. tostring(err)))
    end

    runtime:register_keybind(Key.D, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("dump", 0, function() dump("Ctrl+Shift+D") end)
    end)
    runtime:register_keybind(Key.T, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("test", 0, apply_test)
    end)
    runtime:register_keybind(Key.F, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("fatigue", 0, function() change_fatigue(true) end)
    end)
    for level, key in ipairs({ Key.ONE, Key.TWO, Key.THREE }) do
        runtime:register_keybind(key, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
            actions:schedule_after("tier", 0, function() queue_tier(level) end)
        end)
    end
    runtime:register_keybind(Key.K, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("keep", 0, keep_fatigue_loaded)
    end)
    runtime:register_keybind(Key.I, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("control", 0, apply_control_injury)
    end)
    runtime:register_keybind(Key.U, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("ui", 0, dump_injury_ui)
    end)
    runtime:register_keybind(Key.G, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("fatigue", 0, function() change_fatigue(false) end)
    end)
    log("Ready | Ctrl+Shift+D = dump | Ctrl+Shift+T = test next-mission effect | Ctrl+Shift+F/G = +1/-1 fatigue stack on every operator | Ctrl+Shift+I = control injury on one operator | Ctrl+Shift+K = keep fatigue class loaded | Ctrl+Shift+1/2/3 = queue Tired/Exhausted/Spent penalty | Ctrl+Shift+U = injury banner dump (squad select)")
end

return M
