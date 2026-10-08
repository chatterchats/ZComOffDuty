-- Off Duty Probe: shared UE4SS output plus a dedicated per-mod session log.
local M = {}

function M.new(runtime, options)
    options = options or {}
    local tag = tostring(options.tag or "[OffDutyProbe]")

    local function source_log_path()
        if not debug or type(debug.getinfo) ~= "function" then return nil end
        local ok, info = pcall(debug.getinfo, 1, "S")
        if not ok or not info or type(info.source) ~= "string" then return nil end
        local source = info.source:gsub("^@", "")
        local script_dir = source:match("^(.*)[/\\][^/\\]+$")
        if not script_dir then return nil end
        local mod_dir = script_dir:match("^(.*)[/\\][Ss]cripts$") or script_dir
        local separator = source:find("\\", 1, true) and "\\" or "/"
        return mod_dir .. separator .. "off_duty_probe.log"
    end

    local function try_open(path)
        if type(path) ~= "string" or path == ""
            or type(io) ~= "table" or type(io.open) ~= "function" then
            return nil
        end
        local ok, handle = pcall(io.open, path, "a")
        if not ok or handle == nil then return nil end
        pcall(function() handle:setvbuf("no") end)
        return handle
    end

    local candidates = {}
    local resolved = source_log_path()
    if resolved then candidates[#candidates + 1] = resolved end
    local fallbacks = {
        "ue4ss\\Mods\\Off Duty Probe\\off_duty_probe.log",
        "ue4ss/Mods/Off Duty Probe/off_duty_probe.log",
        "ue4ss\\Mods\\OffDutyProbe\\off_duty_probe.log",
        "ue4ss/Mods/OffDutyProbe/off_duty_probe.log",
        "Mods\\Off Duty Probe\\off_duty_probe.log",
        "Mods/Off Duty Probe/off_duty_probe.log",
        "off_duty_probe.log",
    }
    for _, path in ipairs(fallbacks) do candidates[#candidates + 1] = path end

    local log_file = nil
    local self = { LOG_PATH = nil, workflow_states = {} }
    for _, path in ipairs(candidates) do
        local handle = try_open(path)
        if handle then
            log_file = handle
            self.LOG_PATH = path
            break
        end
    end

    local function timestamp()
        if type(os) == "table" and type(os.date) == "function" then
            local ok, value = pcall(os.date, "!%Y-%m-%dT%H:%M:%SZ")
            if ok and value then return tostring(value) end
        end
        return "time-unavailable"
    end

    function self:log(fmt, ...)
        local message = select("#", ...) > 0
            and string.format(tostring(fmt), ...)
            or tostring(fmt)
        local line = tag .. " " .. message
        print(line .. "\n")
        if log_file then
            pcall(function()
                log_file:write(string.format(
                    "%s [runtime=%s] %s\n",
                    timestamp(),
                    tostring(runtime.generation or 0),
                    line
                ))
                log_file:flush()
            end)
        end
    end

    function self:transition(workflow, next_state, detail)
        workflow = tostring(workflow or "unknown")
        next_state = tostring(next_state or "unknown")
        local previous = self.workflow_states[workflow] or "idle"
        self.workflow_states[workflow] = next_state
        local suffix = detail ~= nil and detail ~= ""
            and ("; " .. tostring(detail):gsub("[\r\n]+", " ")) or ""
        self:log(
            "WORKFLOW TRANSITION | %s | %s -> %s%s",
            workflow,
            previous,
            next_state,
            suffix
        )
    end

    local prior_teardown = runtime.on_teardown
    runtime.on_teardown = function(reason)
        self:transition("runtime", "retired", reason or "teardown")
        if log_file then
            pcall(function() log_file:close() end)
            log_file = nil
        end
        if prior_teardown then prior_teardown(reason) end
    end

    return self
end

return M
