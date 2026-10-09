-- QuickWin (dev tool, never shipped): Ctrl+Shift+W wins the current tactical mission through the
-- game's own cheat, BRGameMissionActor::CompleteMissionCheat, so the normal success flow runs
-- (rewards, injuries, turn end). For testing Off Duty without playing missions out.
-- Wait for the first player turn first: Off Duty processes the squad a few seconds into the mission.
local TAG = "[QuickWin]"
local MISSION_ACTOR = "BRGameMissionActor"

local function log(fmt, ...)
    print(string.format("%s %s\n", TAG, string.format(fmt, ...)))
end

local function valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function live_mission()
    local ok, actors = pcall(FindAllOf, MISSION_ACTOR)
    if not ok or actors == nil then return nil end
    for _, actor in pairs(actors) do
        local live = valid(actor) and select(2, pcall(function() return not actor:HasAnyFlags(0x30) end))
        if live == true then return actor end
    end
    return nil
end

local function win()
    local mission = live_mission()
    if not mission then
        log("no mission in progress (open this in a tactical mission)")
        return
    end
    local ok, in_progress = pcall(function() return mission:IsInProgress() end)
    if ok and in_progress ~= true then
        log("mission isn't in progress (already ending?); nothing done")
        return
    end
    local called, err = pcall(function() mission:CompleteMissionCheat() end)
    log("CompleteMissionCheat %s%s", called and "called" or "FAILED", called and "" or (" | " .. tostring(err)))
end

-- Keybind callbacks don't run on the game thread; UObject work does.
RegisterKeyBind(Key.W, { ModifierKey.CONTROL, ModifierKey.SHIFT }, function()
    ExecuteInGameThread(function()
        local ok, err = pcall(win)
        if not ok then log("ERROR: %s", tostring(err)) end
    end)
end)
log("ready | Ctrl+Shift+W = win the current mission")
