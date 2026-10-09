-- Production wiring of main.lua under a controllable game-thread scheduler.
-- Run from repository root: tools/run-tests.sh bootstrap
local scripts = assert(arg[1], "pass the mod Scripts directory")
local queue, order, next_id, clears = {}, {}, 0, 0
local writes = {}

local hooks = {}
function RegisterHook(path)
    -- Hooks are game-thread work: never during loader registration.
    assert(game_thread, "hook installed on the loader thread: " .. tostring(path))
    assert(not hooks[path], "duplicate hook " .. tostring(path))
    hooks[path] = true
    next_id = next_id + 2
    return next_id - 1, next_id
end
function UnregisterHook(path) hooks[path] = nil end
game_thread = false
function MakeActionHandle() next_id = next_id + 1; return next_id end
function ExecuteInGameThreadWithDelay(handle, delay, callback)
    assert(type(delay) == "number" and delay >= 0)
    queue[handle] = callback
    order[#order + 1] = handle
end
function CancelDelayedAction(handle)
    local had = queue[handle] ~= nil
    queue[handle] = nil
    return had
end
function IsValidDelayedActionHandle(handle) return queue[handle] ~= nil end
function IsDelayedActionActive(handle) return queue[handle] ~= nil end
function ClearAllDelayedActions() clears = clears + 1 end

local original_open, original_print = io.open, print
io.open = function(path, mode)
    if not path:match("off_duty%.log$") then return nil end -- MXM files: not installed in tests
    assert(mode == "a", tostring(path))
    return {
        setvbuf = function() end,
        write = function(_, value) writes[#writes + 1] = value end,
        flush = function() end,
        close = function() end,
    }
end
print = function() end

local function run_pending()
    game_thread = true
    local pending = order
    order = {}
    for _, handle in ipairs(pending) do
        local callback = queue[handle]
        queue[handle] = nil
        if callback then callback() end
    end
end

local function output() return table.concat(writes) end

-- Loading only composes modules and schedules the game-thread handoff.
local handle = dofile(scripts .. "/main.lua")
assert(type(handle) == "number", "main.lua must return the bootstrap action handle")
assert(not output():find("runtime | loading -> ready", 1, true), "ready before game thread")
assert(output():find("WORKFLOW TRANSITION | runtime | idle -> loading; version=", 1, true))
run_pending()
assert(output():find("runtime | loading -> ready; preset=hard gain=2 rest=1 ap_loss=true", 1, true), output())
for _, path in ipairs({
    "/Script/Bruno.BrunoGameStatics:ApplyNextMissionEffectsToCharacter",
    "/Script/Bruno.BrunoStrategyTurnManager:EndStrategyTurn",
    "/Script/BitReactorGame.BitReactorAbilitySystemComponent:OnTeamTurnStarted",
    "/Script/BitReactorGame.BRG_ActiveStatusEffectsListViewModel:GetStatusEffects",
}) do assert(hooks[path], "missing hook " .. path) end

-- A reload retires the previous instance before the new one starts.
local first = assert(rawget(_G, "OffDutyRuntime"))
game_thread = false
dofile(scripts .. "/main.lua")
local second = assert(rawget(_G, "OffDutyRuntime"))
assert(first ~= second and not first.alive and second.alive)
assert(second.generation == first.generation + 1)
assert(output():find("runtime | ready -> retired; script reload", 1, true))
run_pending()

io.open, print = original_open, original_print
print("Off Duty bootstrap tests passed")
