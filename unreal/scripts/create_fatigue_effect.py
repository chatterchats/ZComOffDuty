"""Create or update Off Duty's Unreal assets in the SWZC Merged Kit (editor Python).

Run headless through the editor's Python commandlet (see tools/build_plugin.sh):
    UnrealEditor-Cmd SWZeroCompany.uproject -run=pythonscript -script=<this file>

OffDuty is a Modkit "override" mod: packaging remaps the plugin's content onto /Game
(Config/DefaultOffDuty.ini), so /OffDuty/OffDuty/Effects/GE_OffDuty_Fatigue in the editor is
/Game/OffDuty/Effects/GE_OffDuty_Fatigue in game. The pak goes in Content/Paks/~mods and mounts at
startup, before any save loads. (A "Content Mod" mounted at /OffDuty/ wasn't loadable in game.)

GE_OffDuty_Fatigue copies the pattern of the game's GE_Injured: infinite, AggregateByTarget,
bTerminateWithCombat=false, bIncludeInSaveData=true (that flag governs mid-mission saves). The hub save
only keeps effects whose asset tags include BitReactor.GameplayEffect.Persists (every one of the 21
effect classes in a real hub save has it), so the effect carries that tag through an
AssetTagsGameplayEffectComponent. No modifiers or executions: it does nothing on its own; Off Duty reads
its stack count.
"""
import sys

import unreal

PLUGIN_ROOT = "/OffDuty"
EFFECT_DIR = PLUGIN_ROOT + "/OffDuty/Effects"  # -> /Game/OffDuty/Effects after the remap
EFFECT_NAME = "GE_OffDuty_Fatigue"
STACK_LIMIT = 10  # far above any designed fatigue level; Off Duty caps it lower in Lua
PERSIST_TAG = "BitReactor.GameplayEffect.Persists"  # the hub save's filter for character effects

EFFECT_DEFAULTS = {
    "duration_policy": unreal.GameplayEffectDurationType.INFINITE,
    "stacking_type": unreal.GameplayEffectStackingType.AGGREGATE_BY_TARGET,
    "stack_limit_count": STACK_LIMIT,
    "stack_duration_refresh_policy": unreal.GameplayEffectStackingDurationPolicy.NEVER_REFRESH,
    "stack_period_reset_policy": unreal.GameplayEffectStackingPeriodPolicy.NEVER_RESET,
    "stack_expiration_policy": unreal.GameplayEffectStackingExpirationPolicy.CLEAR_ENTIRE_STACK,
    # UBitReactorGameplayEffect
    "include_in_save_data": True,
    "terminate_with_combat": False,
}

asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
assets = unreal.EditorAssetLibrary


def log(message):
    unreal.log("OFFDUTY | " + message)


def fail(message):
    unreal.log_error("OFFDUTY_RESULT failed | " + message)
    sys.exit(1)


def existing(path):
    # Load from disk: in a commandlet the asset registry may not have scanned the plugin yet,
    # so does_asset_exist() can miss an asset whose file is already there.
    return unreal.load_asset(path)


def load_class(path):
    cls = unreal.load_class(None, path)
    if cls is None:
        fail("class not found: " + path)
    return cls


def inherited_tags(tags):
    # ParentTags is derived by the engine and can't be text-imported.
    container = "(GameplayTags=(%s))" % ",".join('(TagName="%s")' % tag for tag in tags)
    value = unreal.InheritedTagContainer()
    value.import_text("(CombinedTags=%s,Added=%s,Removed=(GameplayTags=()))" % (container, container))
    return value


def ensure_asset_tags(defaults):
    """Give the effect the Persists asset tag through an AssetTagsGameplayEffectComponent."""
    wanted = inherited_tags([PERSIST_TAG])
    # Not exposed as a Python type: load the class and set its properties by name.
    component_class = load_class("/Script/GameplayAbilities.AssetTagsGameplayEffectComponent")
    components = list(defaults.get_editor_property("ge_components"))
    component = next((c for c in components if c is not None and c.get_class() == component_class), None)
    if component is None:
        component = unreal.new_object(component_class, outer=defaults, name="AssetTagsGameplayEffectComponent_0")
        components.append(component)
        defaults.set_editor_property("ge_components", components)
    # The class isn't exposed to Python, so its properties go by their Unreal names.
    name = None
    errors = []
    for candidate in ("InheritableAssetTags", "inheritable_asset_tags"):
        try:
            component.set_editor_property(candidate, wanted)
            name = candidate
            break
        except Exception as error:
            errors.append("%s: %s" % (candidate, error))
    if name is None:
        fail("could not set the component's asset tags: " + " | ".join(errors))
    exported = component.get_editor_property(name).export_text()
    if PERSIST_TAG not in exported:
        fail("asset tag not applied (is %s registered?): %s" % (PERSIST_TAG, exported))
    # The game's own effects also carry the pre-5.3 field; keep it in step when the editor allows it.
    try:
        defaults.set_editor_property("inheritable_gameplay_effect_tags", wanted)
        log("asset tags: component + InheritableGameplayEffectTags = " + PERSIST_TAG)
    except Exception as error:  # deprecated property may be read-only to Python
        log("asset tags: component = %s (InheritableGameplayEffectTags not settable: %s)" % (PERSIST_TAG, error))


def ensure_effect():
    path = EFFECT_DIR + "/" + EFFECT_NAME
    parent = load_class("/Script/BitReactorGame.BitReactorGameplayEffect")
    blueprint = existing(path)
    if blueprint is not None:
        log("updating effect: " + path)
    else:
        factory = unreal.BlueprintFactory()
        factory.set_editor_property("parent_class", parent)
        blueprint = asset_tools.create_asset(EFFECT_NAME, EFFECT_DIR, unreal.Blueprint, factory)
        if blueprint is None:
            fail("could not create " + path)
        log("created effect: " + path)

    # Compile first: a compile reinstances the class default object.
    unreal.BlueprintEditorLibrary.compile_blueprint(blueprint)
    generated = unreal.BlueprintEditorLibrary.generated_class(blueprint)
    if generated is None or not unreal.MathLibrary.class_is_child_of(generated, parent):
        fail("generated class is not a BitReactorGameplayEffect")
    defaults = unreal.get_default_object(generated)
    for name, value in EFFECT_DEFAULTS.items():
        defaults.set_editor_property(name, value)
    for name, value in EFFECT_DEFAULTS.items():
        actual = defaults.get_editor_property(name)
        if actual != value:
            fail("%s is %r after setting %r" % (name, actual, value))
    for name in ("modifiers", "executions"):
        if len(defaults.get_editor_property(name)) != 0:
            fail(name + " must be empty")
    ensure_asset_tags(defaults)

    blueprint.modify()
    if not assets.save_loaded_asset(blueprint, only_if_is_dirty=False):
        fail("could not save " + path)
    log("saved effect: %s | %s" % (path, ", ".join("%s=%s" % item for item in EFFECT_DEFAULTS.items())))


ensure_effect()
unreal.log("OFFDUTY_RESULT ok")
