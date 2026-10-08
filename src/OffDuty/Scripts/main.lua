-- Off Duty v0.1.0
-- Operator fatigue and recovery. In development: this build starts the runtime
-- and logs only; fatigue tracking lands once the probe questions are answered
-- (docs/phase0-findings.md).
local VERSION = "0.1.0"
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = assert(source:match("^(.*[/\\])"), "Scripts directory unavailable")
-- Explicit path: never resolve another mod's generic module names.
package.path = directory .. "?.lua;" .. package.path
for _, module in ipairs({"hook_registry", "actions", "logging"}) do
    package.loaded[module] = nil
end
local Runtime = require("hook_registry")
local Actions = require("actions")
local Logging = require("logging")
local runtime = Runtime.start("OffDutyRuntime", {
    clear_all = OffDutyClearDelayedActionsOnReload ~= false,
})
local logger = Logging.new(runtime, { tag = "[OffDuty]" })
local actions = Actions.new(runtime, {
    valid = function(obj)
        if not obj then return false end
        local ok, result = pcall(function() return obj:IsValid() end)
        return ok and result == true
    end,
    log = function(...) logger:log(...) end,
})
logger:transition("runtime", "loading", "version=" .. VERSION)
if logger.LOG_PATH then
    logger:log("Dedicated log | %s", logger.LOG_PATH)
else
    logger:log("WARNING: off_duty.log unavailable; diagnostics remain in UE4SS.log")
end

-- This MUST remain the final operation: all Unreal work starts on the game
-- thread, never during loader registration.
return actions:schedule_after("bootstrap", 0, function()
    logger:transition("runtime", "ready", "no gameplay changes in this build")
end)
