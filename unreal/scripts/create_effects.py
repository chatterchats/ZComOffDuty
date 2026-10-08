"""Create or update Off Duty's gameplay effects in the SWZC Merged Kit (editor Python).

Run headless through the editor's Python commandlet (see tools/build_plugin.sh):
    UnrealEditor-Cmd SWZeroCompany.uproject -run=pythonscript -script=<this file>

OffDuty is a Modkit "override" mod: packaging remaps the plugin's content onto /Game
(Config/DefaultOffDuty.ini), so /OffDuty/OffDuty/Effects/<name> in the editor is
/Game/OffDuty/Effects/<name> in game. The pak goes in Content/Paks/~mods and mounts at startup.

Effects (all UBitReactorGameplayEffect Blueprints):
- GE_OffDuty_Fatigue: the fatigue counter, one stack per point. Infinite, survives saves and missions.
  The hub save only keeps character effects tagged BitReactor.GameplayEffect.Persists, so it has that
  asset tag. No modifiers: it does nothing on its own.
- GE_OffDuty_Exhausted / GE_OffDuty_Spent: next-mission penalties, queued with
  UBrunoGameStatics::AddNextMissionCharacterEffect like the game's GE_Lose_NextMission_* effects and
  copying their pattern (bTerminateWithCombat, not saved, TemporaryPenalty + StatusEffect.Negative tags,
  BrunoGameEffectUIData for the briefing). Percentages use MultiplyAdditive, which the engine multiplies
  by the stack count, so these never stack (limit 1): one effect per tier instead.
  Accuracy uses the game's own GE_Lose_NextMission_RangedAccuracy (-5% per stack), which keeps the
  native "Penalty from Operation" line in the hit breakdown.
"""
import sys

import unreal

PLUGIN_ROOT = "/OffDuty"
EFFECT_DIR = PLUGIN_ROOT + "/OffDuty/Effects"  # -> /Game/OffDuty/Effects after the remap

PERSISTS = "BitReactor.GameplayEffect.Persists"
PENALTY_TAGS = ["BitReactor.AbilityEffect.Strike.TemporaryPenalty", "BitReactor.GameplayEffect.StatusEffect.Negative"]
HEALTH = ("BitReactorHealthSet", "MaxHealth")
MOVEMENT = ("BitReactorCombatSet", "MovementPerAP")
MAX_HEALTH = '<Keyword id="UI.Keyword.Health">Max Health</>'

COMMON = {
    "duration_policy": unreal.GameplayEffectDurationType.INFINITE,
    "stacking_type": unreal.GameplayEffectStackingType.AGGREGATE_BY_TARGET,
    "stack_duration_refresh_policy": unreal.GameplayEffectStackingDurationPolicy.NEVER_REFRESH,
    "stack_period_reset_policy": unreal.GameplayEffectStackingPeriodPolicy.NEVER_RESET,
    "stack_expiration_policy": unreal.GameplayEffectStackingExpirationPolicy.CLEAR_ENTIRE_STACK,
}
NEXT_MISSION_PENALTY = dict(COMMON, stack_limit_count=1, include_in_save_data=False, terminate_with_combat=True)

EFFECTS = [
    {
        "name": "GE_OffDuty_Fatigue",
        "defaults": dict(COMMON, stack_limit_count=10, include_in_save_data=True, terminate_with_combat=False),
        "asset_tags": [PERSISTS],
        "modifiers": [],
    },
    {
        "name": "GE_OffDuty_Exhausted",
        "defaults": NEXT_MISSION_PENALTY,
        "asset_tags": PENALTY_TAGS,
        "modifiers": [(HEALTH, "MultiplyAdditive", 0.9)],
        "ui": ("Exhausted", "Reduces %s by <Bold>10%%</>." % MAX_HEALTH),
    },
    {
        "name": "GE_OffDuty_Spent",
        "defaults": NEXT_MISSION_PENALTY,
        "asset_tags": PENALTY_TAGS,
        "modifiers": [(HEALTH, "MultiplyAdditive", 0.8), (MOVEMENT, "MultiplyAdditive", 0.9)],
        "ui": ("Spent", "Reduces %s by <Bold>20%%</> and <Bold>Movement</> by <Bold>10%%</>." % MAX_HEALTH),
    },
]

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


def modifier(attribute, op, value):
    """An FGameplayModifierInfo in the engine's text format (as exported from GE_Shocked)."""
    owner, name = attribute
    info = unreal.GameplayModifierInfo()
    info.import_text(
        '(Attribute=(AttributeName="%s",Attribute=/Script/BitReactorGame.%s:%s,'
        "AttributeOwner=\"/Script/CoreUObject.Class'/Script/BitReactorGame.%s'\"),"
        "ModifierOp=%s,ModifierMagnitude=(MagnitudeCalculationType=ScalableFloat,"
        "ScalableFloatMagnitude=(Value=%f)))" % (name, owner, name, owner, op, value))
    exported = info.export_text()
    if name not in exported or op not in exported or ("Value=%f" % value) not in exported:
        fail("modifier did not import as %s %s %s: %s" % (name, op, value, exported))
    return info


def set_by_unreal_name(target, name, value):
    # Components such as AssetTagsGameplayEffectComponent aren't exposed as Python types, so their
    # properties go by Unreal name; fall back to the Python name for exposed ones.
    python_name = "".join("_" + c.lower() if c.isupper() else c for c in name).lstrip("_")
    errors = []
    for candidate in (name, python_name):
        try:
            target.set_editor_property(candidate, value)
            return candidate
        except Exception as error:
            errors.append("%s: %s" % (candidate, error))
    fail("could not set %s on %s: %s" % (name, target.get_class().get_name(), " | ".join(errors)))


def component(defaults, class_path):
    """The effect's component of this class, created if missing."""
    component_class = load_class(class_path)
    components = list(defaults.get_editor_property("ge_components"))
    found = next((c for c in components if c is not None and c.get_class() == component_class), None)
    if found is None:
        found = unreal.new_object(component_class, outer=defaults, name=component_class.get_name() + "_0")
        components.append(found)
        defaults.set_editor_property("ge_components", components)
    return found


def apply_asset_tags(defaults, tags):
    wanted = inherited_tags(tags)
    tags_component = component(defaults, "/Script/GameplayAbilities.AssetTagsGameplayEffectComponent")
    name = set_by_unreal_name(tags_component, "InheritableAssetTags", wanted)
    exported = tags_component.get_editor_property(name).export_text()
    missing = [tag for tag in tags if tag not in exported]
    if missing:
        fail("asset tags not applied (registered?): %s | %s" % (missing, exported))
    # The game's own effects also carry the pre-5.3 field; keep it in step when the editor allows it.
    try:
        defaults.set_editor_property("inheritable_gameplay_effect_tags", wanted)
    except Exception as error:
        log("InheritableGameplayEffectTags not settable: %s" % error)


def apply_ui(defaults, name, description):
    ui = component(defaults, "/Script/Bruno.BrunoGameEffectUIData")
    set_by_unreal_name(ui, "DisplayableEffectName", unreal.Text(name))
    set_by_unreal_name(ui, "GenericDescription", unreal.Text(description))
    tag = unreal.GameplayTag()
    tag.import_text('(TagName="UI.Notification.StatusEffect.Negative")')
    set_by_unreal_name(ui, "NotificationTag", tag)


def ensure_effect(spec):
    path = EFFECT_DIR + "/" + spec["name"]
    parent = load_class("/Script/BitReactorGame.BitReactorGameplayEffect")
    blueprint = existing(path)
    if blueprint is None:
        factory = unreal.BlueprintFactory()
        factory.set_editor_property("parent_class", parent)
        blueprint = asset_tools.create_asset(spec["name"], EFFECT_DIR, unreal.Blueprint, factory)
        if blueprint is None:
            fail("could not create " + path)
        log("created: " + path)
    else:
        log("updating: " + path)

    # Compile first: a compile reinstances the class default object.
    unreal.BlueprintEditorLibrary.compile_blueprint(blueprint)
    generated = unreal.BlueprintEditorLibrary.generated_class(blueprint)
    if generated is None or not unreal.MathLibrary.class_is_child_of(generated, parent):
        fail(spec["name"] + ": generated class is not a BitReactorGameplayEffect")
    defaults = unreal.get_default_object(generated)

    for name, value in spec["defaults"].items():
        defaults.set_editor_property(name, value)
        if defaults.get_editor_property(name) != value:
            fail("%s: %s is %r after setting %r" % (spec["name"], name, defaults.get_editor_property(name), value))
    defaults.set_editor_property("modifiers", [modifier(*m) for m in spec["modifiers"]])
    if len(defaults.get_editor_property("modifiers")) != len(spec["modifiers"]):
        fail(spec["name"] + ": modifiers not applied")
    if len(defaults.get_editor_property("executions")) != 0:
        fail(spec["name"] + ": executions must be empty")
    apply_asset_tags(defaults, spec["asset_tags"])
    if "ui" in spec:
        apply_ui(defaults, *spec["ui"])

    blueprint.modify()
    if not assets.save_loaded_asset(blueprint, only_if_is_dirty=False):
        fail("could not save " + path)
    log("saved: %s | modifiers=%s | tags=%s" % (path, spec["modifiers"], spec["asset_tags"]))


for effect in EFFECTS:
    ensure_effect(effect)
unreal.log("OFFDUTY_RESULT ok")
