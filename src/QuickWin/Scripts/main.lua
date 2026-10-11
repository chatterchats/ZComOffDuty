-- QuickWin (dev tool, never shipped): Ctrl+Shift+W wins the current tactical mission through the
-- game's own cheat, BRGameMissionActor::CompleteMissionCheat, so the normal success flow runs
-- (rewards, injuries, turn end). Ctrl+Shift+L loses it by failing the primary mission objectives
-- (ABRGameObjectiveBase::FailObjective), so the normal failure flow runs. For testing without
-- playing missions out.
-- Wait for the first player turn first: Off Duty processes the squad a few seconds into the mission.
local TAG = "[QuickWin]"
local MISSION_ACTOR = "BRGameMissionActor"
local MISSION_OBJECTIVE = "BRGameMissionObjective"

local function log(fmt, ...)
    print(string.format("%s %s\n", TAG, string.format(fmt, ...)))
end

local function valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

-- Live (non-default, non-archetype) instances of a class.
local function live_all(class)
    local live = {}
    local ok, actors = pcall(FindAllOf, class)
    if not ok or actors == nil then return live end
    for _, actor in pairs(actors) do
        local alive = valid(actor) and select(2, pcall(function() return not actor:HasAnyFlags(0x30) end))
        if alive == true then live[#live + 1] = actor end
    end
    return live
end

-- The current mission, or nil (logged) when there isn't one in progress.
local function mission_in_progress()
    local mission = live_all(MISSION_ACTOR)[1]
    if not mission then
        log("no mission in progress (open this in a tactical mission)")
        return nil
    end
    local ok, in_progress = pcall(function() return mission:IsInProgress() end)
    if ok and in_progress ~= true then
        log("mission isn't in progress (already ending?); nothing done")
        return nil
    end
    return mission
end

local function win()
    local mission = mission_in_progress()
    if not mission then return end
    local called, err = pcall(function() mission:CompleteMissionCheat() end)
    log("CompleteMissionCheat %s%s", called and "called" or "FAILED", called and "" or (" | " .. tostring(err)))
end

local function lose()
    local mission = mission_in_progress()
    if not mission then return end
    local failed = 0
    for _, objective in ipairs(live_all(MISSION_OBJECTIVE)) do
        local ok, eligible = pcall(function()
            return objective.bIsPrimaryMissionObjective == true and objective:IsInProgress() == true
        end)
        if ok and eligible then
            local called, err = pcall(function() objective:FailObjective() end)
            if called then failed = failed + 1 else log("FailObjective FAILED | %s", tostring(err)) end
        end
    end
    log("FailObjective called on %d primary mission objective(s)", failed)
    ExecuteInGameThreadWithDelay(MakeActionHandle(), 1000, function()
        local ok, is_failed = pcall(function() return valid(mission) and mission:IsFailed() end)
        log("mission failed: %s", ok and tostring(is_failed) or "unknown")
    end)
end

-- Keybind callbacks don't run on the game thread; UObject work does.
local function bind(key, action)
    RegisterKeyBind(key, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(action)
            if not ok then log("ERROR: %s", tostring(err)) end
        end)
    end)
end
bind(Key.W, win)
bind(Key.L, lose)
log("ready | Ctrl+Shift+W = win, Ctrl+Shift+L = lose the current mission")
