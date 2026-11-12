-- Off Duty Probe: per-instance ownership for hooks, actions, and persistent
-- dispatchers across same-state UE4SS script reloads.
local M = {}

function M.start(key, options)
    options = options or {}
    assert(type(UnregisterHook) == "function", "UE4SS UnregisterHook is required")

    local previous = rawget(_G, key)
    if previous then previous:teardown("script reload") end

    local self = {
        alive = true,
        hooks = {},
        actions = {},
        bindings = previous and previous.bindings or {},
        generation = (previous and previous.generation or 0) + 1,
        clear_all = options.clear_all ~= false,
    }

    function self:guard(callback)
        return function(...)
            if self.alive then return callback(...) end
        end
    end

    -- APIs such as NotifyOnNewObject and MXM.OnChange do not provide removable
    -- IDs. Register one stable dispatcher, then replace only its guarded target
    -- when this mod instance reloads.
    function self:bind(id, register, callback)
        local binding = self.bindings[id]
        if binding == nil then
            binding = {}
            register(function(...)
                if binding.callback then return binding.callback(...) end
            end)
            self.bindings[id] = binding
        end
        binding.callback = self:guard(callback)
    end

    function self:register_keybind(keycode, modifiers, callback)
        local parts = { tostring(keycode) }
        for _, modifier in ipairs(modifiers or {}) do
            parts[#parts + 1] = tostring(modifier)
        end
        self:bind("key:" .. table.concat(parts, ":"), function(dispatch)
            RegisterKeyBind(keycode, modifiers, dispatch)
        end, callback)
    end

    function self:register_hook(path, pre, post)
        assert(self.alive, "cannot register a hook after teardown")
        local prior = self.hooks[path]
        if prior then return prior.pre_id, prior.post_id end

        local pre_id, post_id = RegisterHook(
            path,
            self:guard(pre),
            post and self:guard(post) or nil
        )
        assert(pre_id ~= nil and post_id ~= nil,
            "RegisterHook must return both IDs for " .. tostring(path))
        self.hooks[path] = {
            path = path,
            pre_id = pre_id,
            post_id = post_id,
        }
        return pre_id, post_id
    end

    function self:track_action(handle)
        if handle ~= nil then self.actions[handle] = true end
        return handle
    end

    function self:finish_action(handle)
        if handle ~= nil then self.actions[handle] = nil end
    end

    function self:teardown(reason)
        self.alive = false

        for _, binding in pairs(self.bindings) do
            binding.callback = nil
        end

        for handle in pairs(self.actions) do
            pcall(CancelDelayedAction, handle)
            self.actions[handle] = nil
        end

        if self.clear_all and type(ClearAllDelayedActions) == "function" then
            local ok, err = pcall(ClearAllDelayedActions)
            if not ok then
                error("Delayed-action cleanup failed: " .. tostring(err))
            end
        end

        local failures = {}
        for path, hook in pairs(self.hooks) do
            local ok, err = pcall(
                UnregisterHook,
                path,
                hook.pre_id,
                hook.post_id
            )
            if ok then
                self.hooks[path] = nil
            else
                failures[#failures + 1] = path .. ": " .. tostring(err)
            end
        end
        if #failures > 0 then error(table.concat(failures, "\n")) end

        if self.on_teardown then
            local cleanup = self.on_teardown
            self.on_teardown = nil
            cleanup(reason)
        end
    end

    -- Retire any unowned delayed actions left by a pre-migration instance.
    if self.clear_all and type(ClearAllDelayedActions) == "function" then
        ClearAllDelayedActions()
    end

    rawset(_G, key, self)
    return self
end

return M
