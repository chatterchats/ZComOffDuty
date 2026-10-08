# Practical UE4SS Lua Modding for Star Wars: Zero Company

> A compact guide to reliable Lua mods for **Star Wars: Zero Company**, adapted
> from Elliott Tate's broader
> [UE4SS guide for Subnautica 2](https://gist.github.com/elliotttate/f10daaa59bd9cdc7f608ccd7a1767b2d).
> It keeps the transferable UE4SS practices and removes game-specific APIs,
> frameworks, networking, and filesystem assumptions.

## Scope

This guide assumes the UE4SS build and Zero Company integration commonly used
by the ZCom modding community. Confirm the available functions in your installed
build before depending on newer APIs.

It intentionally excludes:

- `UEHelpers` and Subnautica-specific gameplay classes;
- `SN2ModSettings` and its shared-variable conventions;
- Subnautica multiplayer and networking patterns;
- Subnautica install paths and loader DLL details;
- the older `LoopAsync` to `ExecuteInGameThread` readiness pattern; and
- game-specific C++ examples.

The authoritative API references remain the
[UE4SS Lua API](https://github.com/UE4SS-RE/RE-UE4SS/blob/main/docs/lua-api.md)
and its
[delayed-action documentation](https://github.com/UE4SS-RE/RE-UE4SS/blob/main/docs/lua-api/global-functions/delayedactions.md).

## Minimal mod layout

```text
My Mod/
├── enabled.txt
└── Scripts/
    ├── main.lua
    ├── actions.lua
    ├── hook_registry.lua
    ├── logging.lua
    └── feature.lua
```

Keep `main.lua` as the composition root. It should create one runtime context,
initialize modules, install hooks, and report that the mod is ready. Put feature
logic and mutable state in focused modules before the entry script approaches
Lua's 200-local limit.

## The eight core practices

| Practice | Rule |
| --- | --- |
| Owned delayed actions | Create handles, retain them, and give related work a cancellation group. |
| UObject validity | Call `IsValid()` immediately before every delayed use. |
| Session cancellation | Cancel pending work when its screen, popup, import, or gameplay attempt ends. |
| Hook ownership | Retain the path plus both hook IDs and unregister them on reload. |
| Dedicated logging | Mirror important messages to a per-mod file with session generations. |
| Modular scripts | Separate infrastructure and large workflows from `main.lua`. |
| Event-driven readiness | Begin work from a relevant hook or activation event, then use bounded retries. |
| Careful object notifications | Use `NotifyOnNewObject` only when construction is the correct signal. Defer risky work. |

## UObject safety

`obj ~= nil` is not enough. A Lua reference can outlive its Unreal object.

```lua
local function uobject_is_valid(object)
    if object == nil then return false end
    local ok, value = pcall(function()
        return object:IsValid()
    end)
    return ok and value == true
end
```

Validate at the point of use, especially inside delayed callbacks. A check made
when scheduling work says nothing about the object's state when that work runs.

```lua
local expected_generation = state.generation
schedule_after("screen", 100, function()
    if expected_generation ~= state.generation then return end
    if not uobject_is_valid(widget) then return end
    widget:SetVisibility(0)
end, widget)
```

Use `pcall` around uncertain reflected property reads and UFunction calls, but do
not treat it as protection from every crash. A native access violation can end
the process before Lua receives an error. Avoid known-dangerous calls during
object, Blueprint, or WidgetTree construction.

Only unwrap `RemoteUnrealParam` or array-element wrappers with `:get()` at
documented callback boundaries. Do not probe arbitrary userdata for a `get`
method; missing UObject members may be represented by callable-looking
placeholders in some UE4SS builds.

## Game-thread work and owned delayed actions

Touch UObjects on the game thread. Hook callbacks normally arrive there already.
For deferred UObject work, prefer the delayed game-thread action API over worker
timers.

```lua
local handle = MakeActionHandle()

ExecuteInGameThreadWithDelay(handle, 100, function()
    if not uobject_is_valid(captured_object) then return end
    do_work(captured_object)
end)
```

Useful controls include:

```lua
IsValidDelayedActionHandle(handle)
IsDelayedActionActive(handle)
CancelDelayedAction(handle)
ClearAllDelayedActions() -- actions owned by the current mod
```

Store handles by workflow rather than in one anonymous list:

```lua
local groups = {
    screen_install = {},
    popup_retirement = {},
    import_create = {},
    verification = {},
}
```

When a workflow is replaced or completed, cancel its group immediately. Keep
generation and validity checks as secondary guards because an already-dispatched
callback may still reach its Lua closure.

Prefer a bounded sequence of retries. Stop after success or a clear timeout, and
log which condition failed to become ready.

## Event-driven readiness

Do not start a permanent readiness poll at module load. Use a stable event that
belongs to the feature:

- a screen's activation or deactivation;
- a known button click or navigation event;
- a gameplay UFunction associated with the ability;
- a map or lifecycle hook; or
- object construction when a newly created instance is genuinely the target.

An event may fire slightly before all dependent properties exist. Schedule a
small, bounded game-thread retry after the event rather than doing invasive work
inside the event callback.

For UI, wait for the live runtime instance to be attached and stable. Prefer
activation-based discovery and reuse existing native widgets where possible.
Widget classes, class default objects, templates, and live widget instances are
not interchangeable.

## `NotifyOnNewObject`

`NotifyOnNewObject` is useful for runtime objects such as actors, animation
assets, or other instances that must be observed as they are constructed. It is
not a universal readiness signal.

```lua
NotifyOnNewObject("/Script/Engine.AnimMontage", function(object)
    schedule_after("montage_readiness", 0, function()
        if not uobject_is_valid(object) then return end
        inspect_montage(object)
    end, object)
end)
```

Return `true` when a one-shot observer has found its target:

```lua
NotifyOnNewObject("/Script/CoreUObject.Class", function(class)
    if not current_runtime.alive then return true end
    if not is_target_class(class) then return false end

    schedule_after("class_discovery", 0, function()
        install_class_hooks(class)
    end, class)
    return true
end)
```

Avoid modifying live UI from a Blueprint/widget construction callback. Character
Share demonstrated that these callbacks can arrive while Zero Company is still
building class defaults or template WidgetTrees. Observe a safer activation or
navigation event instead.

For observers that must remain active, register one persistent dispatcher and
replace its guarded target on hot reload. This prevents each reload from adding
another permanent observer.

## Hooks and hot reload

`RegisterHook` returns two IDs. Retain both with the exact path.

```lua
local pre_id, post_id = RegisterHook(path, pre_callback, post_callback)
hooks[path] = {
    path = path,
    pre_id = pre_id,
    post_id = post_id,
}
```

Teardown must use all three values:

```lua
for path, hook in pairs(hooks) do
    UnregisterHook(path, hook.pre_id, hook.post_id)
    hooks[path] = nil
end
```

A reload-safe runtime should:

1. mark the previous instance inactive;
2. disable persistent dispatchers;
3. cancel every owned delayed action;
4. unregister eversomey retained hook ID pair;
5. close its dedicated log; and
6. install the replacement instance only after cleanup succeeds.

Guard every registered callback with the runtime instance that created it:

```lua
local function guard(runtime, callback)
    return function(...)
        if runtime.alive then return callback(...) end
    end
end
```

If hook removal fails, keep its registry entry so a later teardown can retry.
Do not silently install a replacement while the old native hook may still exist.

## Sessions and generations

A session is any period during which delayed work remains relevant: an open
screen, a popup, an import, an overwrite, or one ability presentation.

Increment a generation when the session starts, closes, or is replaced. Capture
that scalar in callbacks and compare it before touching state. Cancel the owned
handles at the same boundary.

```lua
local function close_session(reason)
    state.generation = state.generation + 1
    actions.cancel_group("session", reason)
    state.active_object = nil
end
```

Prefer retaining scalar identities, names, and GUID strings across asynchronous
work. If a UObject must be captured, keep its lifetime short and validate it at
execution.

## Logging

Prefix shared UE4SS output so it can be filtered:

```lua
print(string.format("[MyMod] %s\n", message))
```

For mods with multiple callbacks or crash-sensitive workflows, also append to a
dedicated log beside the installed mod. Include UTC time, runtime generation,
workflow generation, transitions, success, cancellation, and failure reasons.

```text
2026-09-14T18:30:00Z [runtime=2 screen=5 import=3] [MyMod]
WORKFLOW TRANSITION: import validating -> creating
```

Open and write the file through `pcall`, flush after each line, and fall back to
`UE4SS.log` when the dedicated file cannot be opened. Close the handle during
runtime teardown.

Avoid high-frequency success spam. Log state changes and decisions that help
reconstruct what happened immediately before a crash.

## Modular structure

Split by ownership and lifecycle, not by arbitrary line count. A useful layout
for a growing mod is:

```text
Scripts/
├── main.lua            # version, dependencies, composition
├── state.lua           # mutable per-instance state
├── common.lua          # guarded UObject/property helpers
├── actions.lua         # owned delayed actions and groups
├── hook_registry.lua   # hook IDs and reload teardown
├── logging.lua         # shared and dedicated logs
├── ui.lua              # UI discovery and installation
└── feature_name.lua    # one substantial workflow or ability
```

Small mods do not need every file. Extract `actions.lua`, `hook_registry.lua`,
and `logging.lua` first when lifecycle complexity appears. Split feature logic
when new abilities or workflows create clear boundaries.

Give each module an explicit context rather than copying mutable globals:

```lua
return function(ctx)
    function ctx.feature.start()
        ctx.logging.log("Feature started")
    end
end
```

Reload module factories when developing, but let the runtime registry retire the
old instance before the new context installs hooks or actions.

## Configuration and persistence

Use a returned Lua table for static defaults. For Zero Company in-game settings,
use the framework actually supported by the target mod setup, such as MXM, and
keep defaults functional when that optional dependency is absent.

Treat game-owned state as authoritative. After a mutation, re-read the native
manager or ViewModel and verify the result instead of assuming a successful Lua
call changed the saved game.

When writing files, validate paths, guard `io.open`, and prefer a temporary-file
replacement for important persistent data. Do not carry Subnautica-specific path
rules into Zero Company; resolve the installed mod directory from the running
script when possible.

## UI guidance

- Modify only live runtime widgets.
- Reuse native controls and containers when practical.
- Give injected widgets stable names so reloads can adopt them.
- Check whether a widget already exists before creating another.
- Cancel UI work when the owning screen deactivates.
- Never retain a widget from a closed screen without a validity and generation
  check.
- Keep mutations narrow; do not rebuild a native list when hiding or decorating
  one verified row is enough.

## Development checklist

Before release:

- Open, close, and reopen every affected screen.
- Repeat the workflow several times in one session.
- Hot reload while actions are pending and confirm hooks/widgets are not
  duplicated.
- Test a captured UObject becoming invalid before its callback runs.
- Cancel or replace a workflow while it is waiting.
- Confirm every installed hook is recorded with both IDs.
- Exercise missing optional dependencies and unavailable UObjects.
- Check the dedicated log and `UE4SS.log` around failures.
- Test with other mods that touch the same screen or native function.
- Keep the changelog and packaged version metadata synchronized.

## Compact rule set

1. Let events start work.
2. Run UObject work on the game thread.
3. Validate UObjects at execution time.
4. Own and cancel delayed actions.
5. Track and unregister both hook IDs.
6. Use generations to invalidate stale callbacks.
7. Keep construction callbacks light and defer invasive work.
8. Make reload cleanup explicit and retryable.
9. Log transitions with enough context to reconstruct a crash.
10. Split modules when ownership boundaries become clear.
