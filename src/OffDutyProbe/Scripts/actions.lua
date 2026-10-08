-- Off Duty Probe: owned delayed game-thread actions and cancellable retry groups.
local M = {}

function M.new(runtime, options)
    options = options or {}
    if type(MakeActionHandle) ~= "function"
        or type(ExecuteInGameThreadWithDelay) ~= "function"
        or type(CancelDelayedAction) ~= "function"
        or type(IsValidDelayedActionHandle) ~= "function"
        or type(IsDelayedActionActive) ~= "function" then
        error("Off Duty Probe requires the UE4SS delayed game-thread action system")
    end

    local self = {
        runtime = runtime,
        groups = {},
        valid = options.valid or function(value) return value ~= nil end,
        log = options.log or function() end,
    }

    function self:cancel_group(group, reason)
        local group_actions = self.groups[group]
        if group_actions == nil then return 0 end
        self.groups[group] = nil

        local cancelled, active = 0, 0
        for handle in pairs(group_actions) do
            local valid_ok, handle_valid = pcall(IsValidDelayedActionHandle, handle)
            local active_ok, handle_active = pcall(IsDelayedActionActive, handle)
            if active_ok and handle_active == true then active = active + 1 end
            if valid_ok and handle_valid == true then
                local cancel_ok, did_cancel = pcall(CancelDelayedAction, handle)
                if cancel_ok and did_cancel == true then cancelled = cancelled + 1 end
            end
            runtime:finish_action(handle)
        end

        if cancelled > 0 then
            self.log(
                "Cancelled action group | group=%s | cancelled=%d | active=%d | reason=%s",
                tostring(group),
                cancelled,
                active,
                tostring(reason or "superseded")
            )
        end
        return cancelled
    end

    function self:cancel_all(reason)
        local groups = {}
        for group in pairs(self.groups) do groups[#groups + 1] = group end
        local cancelled = 0
        for _, group in ipairs(groups) do
            cancelled = cancelled + self:cancel_group(group, reason)
        end
        return cancelled
    end

    function self:schedule_after(group, delay_ms, callback, ...)
        if not runtime.alive then return nil end

        local captured_count = select("#", ...)
        local captured_uobjects = { ... }
        local handle = MakeActionHandle()
        local group_actions = nil

        if group ~= nil then
            group_actions = self.groups[group] or {}
            self.groups[group] = group_actions
            group_actions[handle] = true
        end

        local function invoke()
            runtime:finish_action(handle)
            if not runtime.alive then return end

            if group_actions ~= nil then
                -- A cancelled/replaced group may already have reached UE4SS's
                -- dispatch queue. Its callback must still remain inert.
                if self.groups[group] ~= group_actions then return end
                group_actions[handle] = nil
                if next(group_actions) == nil then self.groups[group] = nil end
            end

            for index = 1, captured_count do
                if not self.valid(captured_uobjects[index]) then
                    self.log(
                        "Skipped delayed action | group=%s | invalid captured UObject #%d",
                        tostring(group),
                        index
                    )
                    return
                end
            end

            callback()
        end

        runtime:track_action(handle)
        local ok, err = pcall(
            ExecuteInGameThreadWithDelay,
            handle,
            math.max(0, tonumber(delay_ms) or 0),
            invoke
        )
        if not ok then
            runtime:finish_action(handle)
            if group_actions ~= nil then
                group_actions[handle] = nil
                if next(group_actions) == nil and self.groups[group] == group_actions then
                    self.groups[group] = nil
                end
            end
            error("Unable to schedule delayed action: " .. tostring(err))
        end
        return handle
    end

    return self
end

return M
