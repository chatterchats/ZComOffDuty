-- Run from repository root: tools/run-tests.sh runtime
local scripts = assert(arg[1], "pass the mod Scripts directory")
local hooks, queue, cancelled = {}, {}, {}
local next_id, clear_count, binding_registrations = 0, 0, 0
local fail_unregister = false

function RegisterHook(path, pre, post)
    assert(hooks[path] == nil, "duplicate hook")
    next_id = next_id + 2
    hooks[path] = {
        pre = pre,
        post = post,
        pre_id = next_id - 1,
        post_id = next_id,
    }
    return next_id - 1, next_id
end

function UnregisterHook(path, pre_id, post_id)
    local hook = assert(hooks[path], "unknown hook")
    assert(hook.pre_id == pre_id and hook.post_id == post_id)
    if fail_unregister then error("mock unregistration failure") end
    hooks[path] = nil
end

function MakeActionHandle()
    next_id = next_id + 1
    return next_id
end

function ExecuteInGameThreadWithDelay(handle, delay, callback)
    assert(type(handle) == "number" and type(delay) == "number")
    queue[handle] = callback
end

function CancelDelayedAction(handle)
    if queue[handle] == nil then return false end
    cancelled[handle] = true
    return true
end

function IsValidDelayedActionHandle(handle)
    return queue[handle] ~= nil and cancelled[handle] ~= true
end

function IsDelayedActionActive(handle)
    return IsValidDelayedActionHandle(handle)
end

function ClearAllDelayedActions()
    clear_count = clear_count + 1
    return 0
end

local function run(handle)
    local callback = assert(queue[handle], "missing queued callback")
    queue[handle] = nil
    callback()
end

local Runtime = assert(loadfile(scripts .. "/hook_registry.lua"))()
local Actions = assert(loadfile(scripts .. "/actions.lua"))()
local logs = {}
local first = Runtime.start("OffDutyTestRuntime")
assert(first.generation == 1 and clear_count == 1)

local hook_calls = 0
first:register_hook("/Script/Test:Event", function() hook_calls = hook_calls + 1 end)
local stale_hook = hooks["/Script/Test:Event"].pre
stale_hook()
assert(hook_calls == 1)

local dispatch
first:bind("persistent", function(callback)
    binding_registrations = binding_registrations + 1
    dispatch = callback
end, function() hook_calls = hook_calls + 10 end)
dispatch()
assert(hook_calls == 11 and binding_registrations == 1)

local actions = Actions.new(first, {
    valid = function(value) return value ~= nil and value:IsValid() end,
    log = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
})
local object = { IsValid = function() return true end }
local fired = 0
local first_handle = actions:schedule_after("retry", 1, function() fired = fired + 1 end, object)
local stale_handle = actions:schedule_after("retry", 2, function() fired = fired + 100 end, object)
run(first_handle)
assert(fired == 1)
assert(actions:cancel_group("retry", "succeeded") == 1)
queue[stale_handle]() -- Simulate work already copied into the engine dispatch queue.
assert(fired == 1 and cancelled[stale_handle])

local invalid = { IsValid = function() return false end }
local invalid_handle = actions:schedule_after(nil, 1, function() fired = fired + 1000 end, invalid)
run(invalid_handle)
assert(fired == 1 and #logs >= 2)

local pending = actions:schedule_after("reload", 1, function() fired = fired + 10000 end, object)
local second = Runtime.start("OffDutyTestRuntime")
assert(not first.alive and second.alive and second.generation == 2)
assert(hooks["/Script/Test:Event"] == nil and cancelled[pending])
assert(clear_count == 3)
stale_hook()
dispatch()
assert(hook_calls == 11, "retired callbacks must be inert")

second:bind("persistent", function() error("dispatcher registered twice") end,
    function() hook_calls = hook_calls + 100 end)
dispatch()
assert(hook_calls == 111 and binding_registrations == 1)

second:register_hook("/Script/Test:Retry", function() end)
fail_unregister = true
local reload_ok = pcall(Runtime.start, "OffDutyTestRuntime")
assert(not reload_ok and not second.alive)
assert(hooks["/Script/Test:Retry"], "failed hook cleanup must remain retryable")
fail_unregister = false
local third = Runtime.start("OffDutyTestRuntime")
assert(third.generation == 3 and hooks["/Script/Test:Retry"] == nil)
third:teardown("test complete")
assert(clear_count == 7)

print("owned actions, hook cleanup, and reload dispatcher tests passed")
