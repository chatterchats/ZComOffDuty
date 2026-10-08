-- Off Duty Probe v0.1.0 (development tool, not for release)
-- Loader-thread composition only; hooks install after the game-thread handoff.
local VERSION = "0.1.0"
for _, module in ipairs({"hook_registry", "actions", "logging", "config", "probe"}) do
    package.loaded[module] = nil
end
local Runtime = require("hook_registry")
local Actions = require("actions")
local Logging = require("logging")
local Probe = require("probe")
local runtime = Runtime.start("OffDutyProbeRuntime", {
    clear_all = OffDutyProbeClearDelayedActionsOnReload ~= false,
})
local logger = Logging.new(runtime, { tag = "[OffDutyProbe]" })
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
    logger:log("WARNING: off_duty_probe.log unavailable; diagnostics remain in UE4SS.log")
end

return actions:schedule_after("bootstrap", 0, function()
    local ok, err = pcall(function()
        Probe.start(runtime, actions, logger, require("config"))
    end)
    if not ok then
        logger:log("ERROR: game-thread setup failed | %s", tostring(err))
        runtime:teardown("setup failed")
        error(err)
    end
end)
