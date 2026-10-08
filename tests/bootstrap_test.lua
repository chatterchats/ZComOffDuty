-- Production wiring of main.lua under a controllable game-thread scheduler.
-- Run from repository root: tools/run-tests.sh bootstrap
local scripts = assert(arg[1], "pass the mod Scripts directory")
local queue, order, next_id, clears = {}, {}, 0, 0
local writes = {}

function RegisterHook() error("this build must not install hooks") end
function UnregisterHook() end
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
    assert(path:match("off_duty%.log$") and mode == "a", tostring(path))
    return {
        setvbuf = function() end,
        write = function(_, value) writes[#writes + 1] = value end,
        flush = function() end,
        close = function() end,
    }
end
print = function() end

local function run_pending()
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
assert(output():find("runtime | loading -> ready", 1, true))

-- A reload retires the previous instance before the new one starts.
local first = assert(rawget(_G, "OffDutyRuntime"))
dofile(scripts .. "/main.lua")
local second = assert(rawget(_G, "OffDutyRuntime"))
assert(first ~= second and not first.alive and second.alive)
assert(second.generation == first.generation + 1)
assert(output():find("runtime | ready -> retired; script reload", 1, true))
run_pending()

io.open, print = original_open, original_print
print("Off Duty bootstrap tests passed")
