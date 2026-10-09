-- Off Duty Probe: diagnostics for the Phase 0 open questions.
-- Read-only apart from Ctrl+Shift+T, which adds one native next-mission effect.
-- Never iterates reflected TMaps (known access-violation risk in this build).
local M = {}

local RESULT_EFFECTS = "/Game/Game/GameData/Abilities/ResultEffects/"
-- A third injury kills the operator. Never apply GE_Injured past this.
local MAX_SAFE_INJURIES = 2
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

    -- Ctrl+Shift+B (squad select): fatigue banner prototype. Adds a second WBP_InjuryWarningEntry
    -- under each slot's injury banner, driven from Lua (no view model), labelled with the slot
    -- operator's fatigue tier. Press again to rebuild; UI only, nothing is saved.
    local fatigue_banners = {}
    -- Tier colours are a test: tints multiply the banner's red art, so results may differ.
    -- Tier colours come from the game's own palette (UBitReactorColorBank, tags in BitReactorUITags.ini).
    -- AccentYellow renders orange in game, so it is Exhausted; Spent uses the injury red. The palette
    -- has no true yellow, so Tired's is mixed in the same family. Penalties follow docs/design.md.
    local FATIGUE_CAP = 7
    local TIER_LABELS = {
        { 5, "SPENT", "ColorBank.UI.AccentRed1", {
            "<Bold>-15%</> Chance-To-Hit", "<Bold>-10%</> Max Health", "<Bold>-5%</> Movement",
            "<Bold>10%</> chance each turn to lose <Bold>1 AP</>" } },
        { 3, "EXHAUSTED", "ColorBank.UI.AccentYellow", {
            "<Bold>-10%</> Chance-To-Hit", "<Bold>-5%</> Max Health",
            "<Bold>5%</> chance each turn to lose <Bold>1 AP</>" } },
        { 1, "TIRED", { R = 0.98, G = 0.75, B = 0.07, A = 1.0 }, {
            "<Bold>-5%</> Chance-To-Hit" } },
    }

    local function tier_body(tier, count)
        local lines = { string.format("Fatigue <Bold>%d</> of %d. Each mission adds 2; each turn off duty removes 1.",
                                      count, FATIGUE_CAP), "", "Next mission:" }
        for _, penalty in ipairs(tier[4]) do lines[#lines + 1] = "  " .. penalty end
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("Fully rested after <Bold>%d</> turn%s off duty.", count, count == 1 and "" or "s")
        return table.concat(lines, "\n")
    end
    local bank_colour
    local function tier_for(count)
        for _, tier in ipairs(TIER_LABELS) do
            if count and count >= tier[1] then
                return tier, type(tier[3]) == "table" and tier[3] or bank_colour(tier[3])
                    or { R = 0.98, G = 0.45, B = 0.07, A = 1.0 }
            end
        end
        return nil
    end

    local function colour_table(value)
        local ok, c = pcall(function() return { R = value.R, G = value.G, B = value.B, A = value.A } end)
        return ok and type(c.R) == "number" and c or nil
    end

    local palette_logged = false
    function bank_colour(tag)
        local bank = cdo("/Script/BitReactorGame.Default__BitReactorColorBank")
        if not bank then return nil end
        if not palette_logged then
            palette_logged = true
            local entries = {}
            pcall(function()
                array_each(bank.ColorEntries, function(_, entry)
                    local c = colour_table(entry.Color)
                    entries[#entries + 1] = string.format("%s=%s", (text(entry.Key.TagName) or "?"):gsub("^ColorBank%.UI%.", ""),
                        c and string.format("%.2f,%.2f,%.2f", c.R, c.G, c.B) or "?")
                end)
            end)
            log("BANNER ART | palette: %s", #entries > 0 and table.concat(entries, " ") or "unreadable")
        end
        return colour_table(select(1, call(bank, "GetColor", { TagName = FName(tag) })))
    end

    local function reddish(c) return c and c.R > 0.4 and c.G < 0.35 and c.B < 0.35 end

    local function material_vectors(material)
        local params = {}
        pcall(function()
            array_each(material.VectorParameterValues, function(_, p)
                params[#params + 1] = { name = text(p.ParameterInfo.Name) or "?", value = colour_table(p.ParameterValue) }
            end)
        end)
        return params
    end
    local BANNER_IMAGES = { "Back", "PillBack", "PillBack_Highlight", "GlowBack", "EndCapBG", "Icon" }
    -- Brightness of each banner part relative to the tier colour, as the game's red version has it
    -- (AccentRed1 for the body, ~0.64x for the glow, a lighter highlight).
    local BANNER_ROLES = { Back = 1.0, PillBack = 1.0, EndCapBG = 1.0, GlowBack = 0.64, PillBack_Highlight = 1.6 }

    local function recolour_banner(parts, colour)
        -- The caller stops the state animation first: stopping restores the pre-animation (design)
        -- colours on a later frame, which overwrote a recolour made in the same call.
        local stop_err = nil
        local done = 0
        for part, scale in pairs(BANNER_ROLES) do
            local c = { R = math.min(1, colour.R * scale), G = math.min(1, colour.G * scale),
                        B = math.min(1, colour.B * scale), A = colour.A }
            if valid(parts[part]) and select(2, call(parts[part], "SetColorAndOpacity", c)) == nil then done = done + 1 end
        end
        return done, stop_err
    end
    -- The game sizes the banner's "Sizer" box at runtime (250x34 with "1 INJURY", whose text is 76 wide);
    -- a created copy keeps the design default of 380x36. Widen by however much longer our label is.
    local BANNER_SIZE, BANNER_TEXT_WIDTH = { 250, 34 }, 76

    local function plain(rich)
        -- Slot names are rich text ("Tesh <Bold_Color>Hawks</>").
        return (rich:gsub("<[^>]*>", ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function widget_name(widget)
        local ok, name = pcall(function() return widget:GetFName():ToString() end)
        return ok and tostring(name) or "?"
    end

    local function widget_tree(user_widget)
        -- Designer widgets that aren't "Is Variable" have no property; walk the tree instead.
        local nodes = {}
        local root = select(2, pcall(function() return user_widget.WidgetTree.RootWidget end))
        local function walk(widget, depth)
            if not valid(widget) or depth > 12 then return end
            nodes[#nodes + 1] = { widget = widget, depth = depth, name = widget_name(widget) }
            local count = tonumber((call(widget, "GetChildrenCount"))) or 0
            for i = 0, count - 1 do walk(select(1, call(widget, "GetChildAt", i)), depth + 1) end
        end
        walk(unwrap(root), 0)
        return nodes
    end

    local function colour_string(value)
        -- FLinearColor directly, or an FSlateColor wrapping one; a missing field throws, so try both.
        for _, get in ipairs({ function() return value end, function() return value.SpecifiedColor end }) do
            local ok, s = pcall(function()
                local c = get()
                return string.format("%.2f,%.2f,%.2f,%.2f", c.R, c.G, c.B, c.A)
            end)
            if ok then return s end
        end
        return "?"
    end

    local function fatigue_by_name()
        -- Returns fatigue stacks by operator name and by character ID string.
        local stacks, by_id = {}, {}
        local wco = world_context()
        local class = load_class(FATIGUE_EFFECT)
        if not wco or not class then return stacks, by_id end
        for _, member in ipairs(roster_members(wco)) do
            local name = member.actor and character_name(member.actor)
            local asc = name and select(1, call(ability_library(), "GetAbilitySystemComponent", member.actor))
            if valid(asc) then
                stacks[name] = tonumber((call(asc, "GetGameplayEffectCount", class, nil, true))) or 0
                if member.id then by_id[member.id] = stacks[name] end
            end
        end
        return stacks, by_id
    end

    local function copy_slot_layout(from, to)
        for _, pair in ipairs({ { "Padding", "SetPadding" }, { "HorizontalAlignment", "SetHorizontalAlignment" },
                                { "VerticalAlignment", "SetVerticalAlignment" }, { "Size", "SetSize" } }) do
            pcall(function() to[pair[2]](to, from[pair[1]]) end)
        end
    end

    local function describe_widget(node)
        local w = node.widget
        local function get(f) local ok, v = pcall(f); return ok and v or nil end
        local parts = {
            "vis " .. tostring(select(1, call(w, "GetVisibility"))),
            "op " .. tostring(get(function() return string.format("%.2f", w.RenderOpacity) end)),
            "scale " .. tostring(get(function() return string.format("%.2f,%.2f", w.RenderTransform.Scale.X, w.RenderTransform.Scale.Y) end)),
            "move " .. tostring(get(function() return string.format("%.0f,%.0f", w.RenderTransform.Translation.X, w.RenderTransform.Translation.Y) end)),
            "size " .. tostring(get(function() local d = w:GetDesiredSize(); return string.format("%.0fx%.0f", d.X, d.Y) end)),
        }
        local colour = get(function() return w.ColorAndOpacity end)
        if colour ~= nil then parts[#parts + 1] = "colour " .. colour_string(colour) end
        local brush = get(function() return string.format("%.0fx%.0f", w.Brush.ImageSize.X, w.Brush.ImageSize.Y) end)
        if brush then parts[#parts + 1] = "brush " .. brush end
        local override = get(function() return string.format("%.0fx%.0f", w.WidthOverride, w.HeightOverride) end)
        if override then parts[#parts + 1] = "sizebox " .. override end
        return table.concat(parts, " ")
    end

    local function log_tree_diff(name, original, copy, original_slot, copy_slot)
        local function slot_text(s)
            local ok, v = pcall(function()
                local p = s.Padding
                return string.format("pad %.0f,%.0f,%.0f,%.0f h %s v %s", p.Left, p.Top, p.Right, p.Bottom,
                    tostring(s.HorizontalAlignment), tostring(s.VerticalAlignment))
            end)
            return ok and v or "?"
        end
        log("BANNER TREE | %s | slot original: %s | copy: %s", name, slot_text(original_slot), slot_text(copy_slot))
        local copy_nodes = {}
        for _, node in ipairs(widget_tree(copy)) do copy_nodes[node.name] = node end
        for _, node in ipairs(widget_tree(original)) do
            local a = describe_widget(node)
            local other = copy_nodes[node.name]
            local b = other and describe_widget(other) or "missing"
            log("BANNER TREE | %s%s | %s%s", string.rep(" ", node.depth), node.name, a,
                a == b and "" or (" || COPY " .. b))
        end
    end

    -- Portrait strip (and roster screens): WBP_RosterTile shows injuries with WBP_HeroInjuries.
    -- Log-only: how a tile maps to its operator, and the injury marker's widget tree.
    local function dump_roster_tiles()
        local list_lib = cdo("/Script/UMG.Default__UserObjectListEntryLibrary")
        local ok, tiles = pcall(FindAllOf, "WBP_RosterTile_C")
        local count, shown_tree = 0, false
        for _, tile in pairs(ok and tiles or {}) do
            if live(tile) then
                count = count + 1
                local item, item_err = call(list_lib, "GetListItemObject", tile)
                local who = item and plain(text((call(item, "GetFullName"))) or "?") or "?"
                local id = item and guid_string((call(item, "GetCharacterID"))) or "?"
                local injuries = select(2, pcall(function() return tile.WBP_HeroInjuries end))
                local vis = valid(injuries) and tostring((call(injuries, "GetVisibility"))) or "none"
                log("TILE | %d | %s | id %s | item %s%s | HeroInjuries vis %s | parent %s", count, who, tostring(id),
                    item and (full_name(item):match("^(%S+)") or "?") or "none", item_err and (" err " .. item_err) or "",
                    vis, valid(injuries) and (full_name((call(injuries, "GetParent"))):match("^(%S+)") or "?") or "?")
                if not shown_tree and valid(injuries) and vis ~= "1" and vis ~= "2" then
                    shown_tree = true
                    for _, node in ipairs(widget_tree(injuries)) do
                        log("TILE TREE | %s%s | %s", string.rep(" ", node.depth), node.name, describe_widget(node))
                    end
                    local row = select(2, pcall(function() return tile.NotificationsHorizontalBox end))
                    local n = valid(row) and tonumber((call(row, "GetChildrenCount"))) or 0
                    local names = {}
                    for i = 0, n - 1 do
                        local child = (call(row, "GetChildAt", i))
                        names[#names + 1] = widget_name(child) .. "(" .. tostring((call(child, "GetVisibility"))) .. ")"
                    end
                    log("TILE TREE | NotificationsHorizontalBox children: %s", table.concat(names, " "))
                end
            end
        end
        log("TILE | %d live roster tile(s)%s", count, count == 0 and " (open the portrait strip first)" or "")
    end

    -- Portrait tiles: a copy of the tile's WBP_HeroInjuries marker at the portrait's bottom right,
    -- one image showing the game's Lethargy status icon in the tier colour, with our tooltip.
    local LETHARGY_ICON = "/Game/Game/UI/Icons/StatusEffects/T_UI_StatusEffect_Lethargy.T_UI_StatusEffect_Lethargy"
    local tile_markers = {}

    local function build_tile_markers(by_id, library)
        for _, marker in ipairs(tile_markers) do
            pcall(function() if valid(marker) then marker:RemoveFromParent() end end)
        end
        tile_markers = {}
        local list_lib = cdo("/Script/UMG.Default__UserObjectListEntryLibrary")
        local icon = select(2, pcall(StaticFindObject, LETHARGY_ICON))
        if not valid(icon) then log("TILE MARK | Lethargy icon not loaded; keeping the heartbeat icon") icon = nil end
        local ok, tiles = pcall(FindAllOf, "WBP_RosterTile_C")
        local built = 0
        for _, tile in pairs(ok and tiles or {}) do
            local item = live(tile) and (call(list_lib, "GetListItemObject", tile)) or nil
            local id = item and guid_string((call(item, "GetCharacterID"))) or nil
            local count = id and by_id[id] or nil
            local tier, colour = tier_for(count)
            local injuries = select(2, pcall(function() return tile.WBP_HeroInjuries end))
            local parent = valid(injuries) and (call(injuries, "GetParent")) or nil
            if tier and valid(parent) then
                local marker, err = call(library, "Create", tile, injuries:GetClass(), (call(injuries, "GetOwningPlayer")))
                if valid(marker) then
                    local new_slot = (call(parent, "AddChild", marker))
                    local old_slot = select(2, pcall(function() return injuries.Slot end))
                    if valid(new_slot) and valid(old_slot) then copy_slot_layout(old_slot, new_slot) end
                    call(new_slot, "SetHorizontalAlignment", 3) -- Right
                    local parts = {}
                    for _, node in ipairs(widget_tree(marker)) do parts[node.name] = node.widget end
                    call(parts.Injury_2, "SetVisibility", 1) -- Collapsed: one icon
                    call(parts.Injury_1, "SetVisibility", 4)
                    if icon then call(parts.Injury_1, "SetBrushFromTexture", icon, false) end
                    for part_name, widget in pairs(parts) do
                        if part_name:find("^BitReactorTooltipBox") then
                            call(widget, "SetTooltipPayloadTags", {})
                            call(widget, "SetTooltipPayloadEntries", {
                                { HeaderText = FText(tier[2]), BodyText = FText(tier_body(tier, count)) } })
                        end
                    end
                    call(marker, "SetVisibility", 4)
                    tile_markers[#tile_markers + 1] = marker
                    built = built + 1
                    actions:schedule_after("tile_mark", 100, function()
                        call(marker, "StopAllAnimations")
                        actions:schedule_after("tile_mark_colour", 150, function()
                            call(parts.Injury_1, "SetColorAndOpacity", colour)
                        end, marker)
                    end, marker)
                    log("TILE MARK | %s | %s (%d) | slot h %s v %s", plain(text((call(item, "GetFullName"))) or "?"),
                        tier[2], count,
                        tostring(select(2, pcall(function() return old_slot.HorizontalAlignment end))),
                        tostring(select(2, pcall(function() return old_slot.VerticalAlignment end))))
                else
                    log("TILE MARK | Create failed: %s", tostring(err))
                end
            end
        end
        log("TILE MARK | %d marker(s) added", built)
    end

    local function build_fatigue_banners()
        for _, banner in ipairs(fatigue_banners) do
            pcall(function() if valid(banner) then banner:RemoveFromParent() end end)
        end
        fatigue_banners = {}
        local library = cdo("/Script/UMG.Default__WidgetBlueprintLibrary")
        local compared = false
        local logged_art = {}
        local stacks, stacks_by_id = fatigue_by_name()
        local ok, slots = pcall(FindAllOf, "WBP_CharacterSlot_C")
        local built = 0
        for _, slot in pairs(ok and slots or {}) do
            if live(slot) then
                local name = plain(select(2, pcall(function() return text(slot.FullName:GetText()) end)) or "?")
                local entry = select(2, pcall(function() return slot.WBP_InjuryWarningEntry end))
                local parent = valid(entry) and select(1, call(entry, "GetParent")) or nil
                if not valid(parent) then
                    log("BANNER | slot %s | no injury entry parent", name)
                else
                    local index = select(1, call(parent, "GetChildIndex", entry))
                    log("BANNER | slot %s | entry visibility %s | header '%s' | parent %s (%s children, entry at %s)",
                        name, tostring(select(1, call(entry, "GetVisibility"))),
                        select(2, pcall(function() return text(entry.HeaderText:GetText()) end)) or "?",
                        full_name(parent):match("^(%S+)") or "?",
                        tostring(select(1, call(parent, "GetChildrenCount"))), tostring(index))
                    local transform = select(2, pcall(function() return entry.RenderTransform end))
                    log("BANNER | slot %s | entry render scale %s | pivot %s | back colour %s | desired size %s",
                        name,
                        select(2, pcall(function() return string.format("%.2f,%.2f", transform.Scale.X, transform.Scale.Y) end)) or "?",
                        select(2, pcall(function() return string.format("%.2f,%.2f", entry.RenderTransformPivot.X, entry.RenderTransformPivot.Y) end)) or "?",
                        colour_string(select(2, pcall(function() return entry.Back.ColorAndOpacity end))),
                        select(2, pcall(function() local d = entry:GetDesiredSize(); return string.format("%.0fx%.0f", d.X, d.Y) end)) or "?")
                    local count = stacks[name]
                    local label, colour, tier_info = nil, nil, nil
                    if count == nil then
                        label = "NO FATIGUE DATA"
                    else
                        for _, tier in ipairs(TIER_LABELS) do
                            if count >= tier[1] then
                                label, tier_info = tier[2], tier
                                colour = type(tier[3]) == "table" and tier[3] or bank_colour(tier[3])
                                    or { R = 0.98, G = 0.45, B = 0.07, A = 1.0 }
                                break
                            end
                        end
                    end
                    if label == nil then
                        log("BANNER | slot %s | rested (%d), no banner", name, count)
                    else
                        local banner, err = call(library, "Create", slot, entry:GetClass(), select(1, call(entry, "GetOwningPlayer")))
                        if not valid(banner) then
                            log("BANNER | slot %s | Create failed: %s", name, tostring(err))
                        else
                            local new_slot, add_err = call(parent, "AddChild", banner)
                            local entry_slot = select(2, pcall(function() return entry.Slot end))
                            if valid(new_slot) and valid(entry_slot) then copy_slot_layout(entry_slot, new_slot) end
                            local _, text_err = call(banner.HeaderText, "SetText", FText(label))
                            pcall(function()
                                banner:SetRenderTransform(transform)
                                banner:SetRenderTransformPivot(entry.RenderTransformPivot)
                            end)
                            local tinted = 0
                            local wanted = {}
                            for _, image in ipairs(colour and BANNER_IMAGES or {}) do wanted[image] = true end
                            local parts = { __banner = banner }
                            for _, node in ipairs(widget_tree(banner)) do
                                parts[node.name] = node.widget
                                if wanted[node.name] then
                                    -- A multiply tint over red art only darkened it. UBitReactorImage colours come
                                    -- from a palette tag (ColorAndOpacityColorTag) or material parameters, so
                                    -- recolour red material vectors, else replace the widget tint.
                                    local w = node.widget
                                    local material = select(2, pcall(function() return w.Brush.ResourceObject end))
                                    local vectors = valid(material) and material_vectors(material) or {}
                                    if not logged_art[node.name] then
                                        logged_art[node.name] = true
                                        local listed = {}
                                        for _, v in ipairs(vectors) do
                                            listed[#listed + 1] = v.name .. "=" .. colour_string(v.value)
                                        end
                                        log("BANNER ART | %s | colour tag %s | brush type %s | has material %s | widget tint %s | brush tint %s | draws %s | vectors [%s]",
                                            node.name,
                                            select(2, pcall(function() return text(w.ColorAndOpacityColorTag.TagName) end)) or "?",
                                            tostring(select(2, pcall(function() return w.BrushType end))),
                                            tostring((call(w, "GetHasMaterial"))),
                                            colour_string(select(2, pcall(function() return w.ColorAndOpacity end))),
                                            colour_string(select(2, pcall(function() return w.Brush.TintColor end))),
                                            full_name(material), table.concat(listed, " "))
                                    end
                                    local changed, errors = 0, {}
                                    local red_vectors = {}
                                    for _, v in ipairs(vectors) do
                                        if reddish(v.value) then red_vectors[#red_vectors + 1] = v.name end
                                    end
                                    if #red_vectors > 0 then
                                        local mid, mid_err = call(w, "GetDynamicMaterial")
                                        for _, param in ipairs(red_vectors) do
                                            local _, e = call(mid, "SetVectorParameterValue", FName(param), colour)
                                            if e == nil and valid(mid) then changed = changed + 1 else errors[#errors + 1] = tostring(e or mid_err) end
                                        end
                                    else
                                        local _, e = call(w, "SetColorAndOpacity", colour)
                                        if e == nil then changed = changed + 1 else errors[#errors + 1] = tostring(e) end
                                    end
                                    if changed > 0 then tinted = tinted + 1 end
                                    if #errors > 0 and not logged_art[node.name .. "!"] then
                                        logged_art[node.name .. "!"] = true
                                        log("BANNER ART | %s | recolour errors: %s", node.name, table.concat(errors, " | "))
                                    end
                                end
                            end
                            -- Pips: the game shows Injury_1 for one injury and adds Injury_2 for two.
                            -- Here: one pip for Tired, two for Exhausted and Spent.
                            call(parts.Injury_1, "SetVisibility", 4)
                            call(parts.Injury_2, "SetVisibility", count >= 3 and 4 or 2)
                            call(parts.Sizer, "SetWidthOverride", BANNER_SIZE[1])
                            call(parts.Sizer, "SetHeightOverride", BANNER_SIZE[2])
                            -- Tooltip: the injury one comes from its payload (tags/objects); ours is a plain
                            -- header + body entry. Log the original's setup once to see what it renders from.
                            if not logged_art.tooltip then
                                logged_art.tooltip = true
                                local original_tip
                                for _, node in ipairs(widget_tree(entry)) do
                                    if node.name == "WarningTooltip" then original_tip = node.widget end
                                end
                                local ok, info = pcall(function()
                                    local p = original_tip.TooltipWidgetParameters
                                    local tags = {}
                                    array_each(p.TooltipPayloadTags, function(_, t) tags[#tags + 1] = text(t.TagName) or "?" end)
                                    local objects, entries = 0, 0
                                    array_each(p.TooltipPayloadObjects, function() objects = objects + 1 end)
                                    array_each(p.TooltipPayloadEntries, function() entries = entries + 1 end)
                                    return string.format("class %s | tags [%s] | objects %d | entries %d | display %s",
                                        full_name(p.TooltipWidgetClass), table.concat(tags, ", "), objects, entries,
                                        tostring(p.bDisplayTooltip))
                                end)
                                log("BANNER TIP | original (%s) | %s", name, ok and info or ("unreadable: " .. tostring(info)))
                            end
                            if tier_info and valid(parts.WarningTooltip) then
                                local tip = parts.WarningTooltip
                                call(tip, "SetTooltipPayloadTags", {})
                                call(tip, "SetTooltipPayloadObjects", {})
                                local _, tip_err = call(tip, "SetTooltipPayloadEntries", {
                                    { HeaderText = FText(tier_info[2]), BodyText = FText(tier_body(tier_info, count)) } })
                                call(tip, "SetDisplayTooltop", true)
                                if tip_err then log("BANNER TIP | %s | entries error %s", name, tip_err) end
                            end
                            actions:schedule_after("banner_size", 100, function()
                                if colour then
                                    local _, stop_err = call(banner, "StopAllAnimations")
                                    actions:schedule_after("banner_recolour", 150, function()
                                        local done = recolour_banner(parts, colour)
                                        log("BANNER | %s | stopped animations%s, recoloured %d part(s)", name,
                                            stop_err and (" (error " .. stop_err .. ")") or "", done)
                                    end, banner)
                                    actions:schedule_after("banner_check", 700, function()
                                        log("BANNER | %s | Back colour after 0.5 s: %s (wanted %s)", name,
                                            colour_string(select(2, pcall(function() return parts.Back.ColorAndOpacity end))),
                                            colour_string(colour))
                                    end, banner)
                                end
                                local ok, width = pcall(function() return parts.HeaderText:GetDesiredSize().X end)
                                if ok and type(width) == "number" then
                                    call(parts.Sizer, "SetWidthOverride", BANNER_SIZE[1] + math.max(0, width - BANNER_TEXT_WIDTH))
                                    log("BANNER | %s | label %.0f wide, banner %.0f", name, width,
                                        BANNER_SIZE[1] + math.max(0, width - BANNER_TEXT_WIDTH))
                                end
                            end, banner)
                            call(banner, "SetVisibility", 4) -- SelfHitTestInvisible
                            if not compared and select(1, call(entry, "GetVisibility")) ~= 1 then
                                compared = true
                                -- After a layout pass, so desired sizes are real.
                                actions:schedule_after("banner_tree", 300, function()
                                    log_tree_diff(name, entry, banner, entry_slot, new_slot)
                                end, entry, banner)
                            end
                            fatigue_banners[#fatigue_banners + 1] = banner
                            built = built + 1
                            log("BANNER | slot %s | added '%s' | tinted %d image(s) | slot %s%s%s", name, label, tinted,
                                valid(new_slot) and (full_name(new_slot):match("^(%S+)") or "?") or "none",
                                add_err and (" | add error " .. add_err) or "", text_err and (" | text error " .. text_err) or "")
                        end
                    end
                end
            end
        end
        dump_roster_tiles()
        build_tile_markers(stacks_by_id, library)
        log("BANNER | %d banner(s) added (fatigue known for %d operator(s))", built,
            (function() local n = 0; for _ in pairs(stacks) do n = n + 1 end; return n end)())
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
                    local before = tonumber((call(asc, "GetGameplayEffectCount", class, nil, true)))
                    if before == nil or before >= MAX_SAFE_INJURIES then
                        log("CONTROL | %s | has %s injuries; not adding (3 injuries kills)", name, tostring(before))
                        return
                    end
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

    -- Ctrl+Shift+F: set the config.test_squad fatigue and injury counts exactly (repeatable).
    local function set_effect_count(asc, class, target)
        local current = tonumber((call(asc, "GetGameplayEffectCount", class, nil, true))) or 0
        local err
        if current < target then
            for _ = current + 1, target do
                local context = select(1, call(asc, "MakeEffectContext"))
                _, err = call(asc, "BP_ApplyGameplayEffectToSelf", class, 1.0, context)
            end
        elseif current > target then
            local remover = cdo("/Script/BitReactorGame.Default__BitReactorAbilityScriptingFunctions")
            _, err = call(remover, "RemoveEffectByClass", asc, class, current - target)
        end
        return tonumber((call(asc, "GetGameplayEffectCount", class, nil, true))) or 0, err
    end

    local function apply_test_squad()
        local wco = world_context()
        if not wco or not roster_statics() then log("SQUAD | no world context (load a campaign first)"); return end
        local fatigue = load_class(FATIGUE_EFFECT)
        local injured = load_class(class_path(RESULT_EFFECTS, "GE_Injured"))
        if not fatigue or not injured then log("SQUAD | effect classes not loadable"); return end
        local done = {}
        for _, member in ipairs((roster_members(wco))) do
            local name = member.actor and character_name(member.actor)
            for _, entry in ipairs(config.test_squad or {}) do
                if name and not done[entry.name] and name:lower():find(entry.name:lower(), 1, true) then
                    local asc = select(1, call(ability_library(), "GetAbilitySystemComponent", member.actor))
                    if valid(asc) then
                        done[entry.name] = true
                        local f, f_err = set_effect_count(asc, fatigue, entry.fatigue or 0)
                        local wanted_injuries = math.min(entry.injuries or 0, MAX_SAFE_INJURIES)
                        if (entry.injuries or 0) > MAX_SAFE_INJURIES then
                            log("SQUAD | %s | injuries capped at %d (3 injuries kills)", name, MAX_SAFE_INJURIES)
                        end
                        local i, i_err = set_effect_count(asc, injured, wanted_injuries)
                        log("SQUAD | %s | fatigue %d (wanted %d) | injuries %d (wanted %d)%s%s", name,
                            f, entry.fatigue or 0, i, entry.injuries or 0,
                            f_err and (" | fatigue error " .. f_err) or "", i_err and (" | injury error " .. i_err) or "")
                    end
                end
            end
        end
        for _, entry in ipairs(config.test_squad or {}) do
            if not done[entry.name] then log("SQUAD | %s | not found among roster operators with a live actor", entry.name) end
        end
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
        actions:schedule_after("fatigue", 0, apply_test_squad)
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
    runtime:register_keybind(Key.B, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("banner", 0, build_fatigue_banners)
    end)
    runtime:register_keybind(Key.G, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        actions:schedule_after("fatigue", 0, function() change_fatigue(false) end)
    end)
    log("Ready | Ctrl+Shift+D = dump | Ctrl+Shift+T = test next-mission effect | Ctrl+Shift+F = set test squad fatigue/injuries (config.test_squad) | Ctrl+Shift+G = -1 fatigue stack on every operator | Ctrl+Shift+I = control injury on one operator | Ctrl+Shift+K = keep fatigue class loaded | Ctrl+Shift+1/2/3 = queue Tired/Exhausted/Spent penalty | Ctrl+Shift+U = injury banner dump | Ctrl+Shift+B = fatigue banner prototype (squad select)")
end

return M
