-- Run from repository root: tools/run-tests.sh logging
local scripts = assert(arg[1], "pass the mod Scripts directory")
local writes, console = {}, {}
local closed, prior_teardown = false, false
local original_open, original_print = io.open, print

io.open = function(path, mode)
    assert(path:match("off_duty%.log$") and mode == "a")
    return {
        setvbuf = function() end,
        write = function(_, value) writes[#writes + 1] = value end,
        flush = function() end,
        close = function() closed = true end,
    }
end
print = function(value) console[#console + 1] = tostring(value) end

local runtime = {
    generation = 9,
    on_teardown = function(reason)
        assert(reason == "test")
        prior_teardown = true
    end,
}
local Logging = assert(loadfile(scripts .. "/logging.lua"))()
local logger = Logging.new(runtime, { tag = "[OffDuty]" })
logger:transition("runtime", "loading", "line one\nline two")
logger:log("Rate changed | %sx", 4)
runtime.on_teardown("test")

io.open, print = original_open, original_print
local output = table.concat(writes)
assert(logger.LOG_PATH and logger.LOG_PATH:match("off_duty%.log$"))
assert(output:find("[runtime=9]", 1, true))
assert(output:find(
    "WORKFLOW TRANSITION | runtime | idle -> loading; line one line two",
    1,
    true
))
assert(output:find("[OffDuty] Rate changed | 4x", 1, true))
assert(#console == 3 and closed and prior_teardown)
print("Off Duty dedicated logging tests passed")
