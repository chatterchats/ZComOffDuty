-- Off Duty v0.1.0
-- Operator fatigue and recovery. Loader-thread composition only: hooks, UObject work and settings
-- start on the game thread (the final scheduled action below).
local VERSION = "0.1.0"
local MOD_FOLDER = "OffDuty"
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = assert(source:match("^(.*[/\\])"), "Scripts directory unavailable")
-- Explicit path: never resolve another mod's generic module names.
package.path = directory .. "?.lua;" .. package.path
for _, module in ipairs({"hook_registry", "actions", "logging", "MXM", "rules", "game", "icons", "fatigue",
                         "status_ui", "squad_ui"}) do
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

local function start()
    local log = function(...) logger:log(...) end
    -- MXM's client library (unmodified, as its author requires) polls its values file with LoopAsync:
    -- file reads only, no UObjects. A hot reload starts another poll; restart the game to drop them.
    local Settings = require("MXM")
    local game = require("game").new(log)
    local ctx = {
        runtime = runtime, actions = actions, log = log, game = game, mod_folder = MOD_FOLDER,
        settings = function() return Settings.All() end,
    }
    ctx.icons = require("icons").new(ctx)
    require("fatigue").new(ctx):install()
    require("status_ui").new(ctx):install()
    local squad = require("squad_ui").new(ctx)
    squad:install()
    -- MXM calls OnChange from its LoopAsync poll, off the game thread: only schedule game-thread work.
    runtime:bind("settings_changed", function(dispatch) Settings.OnChange(dispatch) end, function(_, changed)
        actions:schedule_after("settings_changed", 0, function()
            log("Settings changed | %s", table.concat(changed or {}, ", "))
            squad:refresh_all()
        end)
    end)
    local s = require("rules").normalise(Settings.All())
    logger:transition("runtime", "ready", string.format("preset=%s gain=%d rest=%d ap_loss=%s",
        s.preset, s.gain, s.rest, tostring(s.ap_loss)))
end

-- This MUST remain the final operation: all Unreal work starts on the game
-- thread, never during loader registration.
return actions:schedule_after("bootstrap", 0, function()
    local ok, err = pcall(start)
    if not ok then
        logger:log("ERROR: game-thread setup failed | %s", tostring(err))
        runtime:teardown("setup failed")
        error(err)
    end
end)
