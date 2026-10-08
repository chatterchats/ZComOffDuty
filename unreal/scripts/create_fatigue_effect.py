"""Create or update Off Duty's Unreal assets in the SWZC Merged Kit (editor Python).

Run headless through the editor's Python commandlet (see tools/build_plugin.sh):
    UnrealEditor-Cmd SWZeroCompany.uproject -run=pythonscript -script=<this file>

Assets (plugin OffDuty, mounted at /OffDuty/):
- /OffDuty/GameFeatureData            UBitReactorModGameFeatureData, as the Modkit's mod wizard creates
- /OffDuty/Effects/GE_OffDuty_Fatigue fatigue counter, one stack per fatigue point

GE_OffDuty_Fatigue copies the pattern of the game's GE_Injured, the effect that survives saves and
missions: infinite, AggregateByTarget, bIncludeInSaveData=true, bTerminateWithCombat=false. It has no
modifiers, executions or components, so it does nothing on its own; Off Duty reads its stack count.
"""
import sys

import unreal

PLUGIN_ROOT = "/OffDuty"
EFFECT_DIR = PLUGIN_ROOT + "/Effects"
EFFECT_NAME = "GE_OffDuty_Fatigue"
FEATURE_DATA_NAME = "GameFeatureData"
STACK_LIMIT = 10  # far above any designed fatigue level; Off Duty caps it lower in Lua

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


def ensure_feature_data():
    path = PLUGIN_ROOT + "/" + FEATURE_DATA_NAME
    if existing(path) is not None:
        log("feature data present: " + path)
        return
    factory = unreal.DataAssetFactory()
    factory.set_editor_property("data_asset_class", load_class("/Script/BitReactorModRuntime.BitReactorModGameFeatureData"))
    data = asset_tools.create_asset(FEATURE_DATA_NAME, PLUGIN_ROOT, None, factory)
    if data is None:
        fail("could not create " + path + " (is the OffDuty plugin mounted at /OffDuty/?)")
    assets.save_loaded_asset(data, only_if_is_dirty=False)
    log("created feature data: " + path)


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

    blueprint.modify()
    if not assets.save_loaded_asset(blueprint, only_if_is_dirty=False):
        fail("could not save " + path)
    log("saved effect: %s | %s" % (path, ", ".join("%s=%s" % item for item in EFFECT_DEFAULTS.items())))


ensure_feature_data()
ensure_effect()
unreal.log("OFFDUTY_RESULT ok")
