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
- GE_OffDuty_Deployed: a saved marker (Persists, no modifiers) for operators who deployed this strategy turn.
- GE_OffDuty_LoseAP: instant ActionPoints -1, applied by Off Duty when a fatigued operator's
  turn-start roll hits (a turn is 3 AP; the game refills them at the next turn start).
- GE_OffDuty_Tired / GE_OffDuty_Exhausted / GE_OffDuty_Spent: next-mission penalties, queued with
  UBrunoGameStatics::AddNextMissionCharacterEffect like the game's GE_Lose_NextMission_* effects and
  copying their pattern (bTerminateWithCombat, not saved, TemporaryPenalty + StatusEffect.Negative tags).
  Percentages use MultiplyAdditive, which the engine multiplies by the stack count, so these never stack
  (limit 1): one effect per tier instead. Tired has no modifiers of its own (its accuracy is the game's
  effect); it exists so the tier shows in mission.
  Each carries BRG_StatusEffectUIData, the component GE_Injured uses, so the tactical Inspect panel lists
  it under Debuffs. The list takes a status's name, description and icon from its StatusEffectTag's tag
  UI data, so each tier has its own tag (OffDuty.Status.<Tier>, Config/Tags/OffDutyTags.ini) whose text
  Off Duty fills in at runtime; the game's own tag, Lethargy, belongs to the Seer's drain. A GameplayEffect's UI data is found as its first UGameplayEffectUIData
  component, so the strategy-side BrunoGameEffectUIData these used to carry is removed.
  Accuracy uses the game's own GE_Lose_NextMission_RangedAccuracy (-5% per stack), which keeps the
  native "Penalty from Operation" line in the hit breakdown.

"""
import sys

import unreal

PLUGIN_ROOT = "/OffDuty"
EFFECT_DIR = PLUGIN_ROOT + "/OffDuty/Effects"  # -> /Game/OffDuty/Effects after the remap

PERSISTS = "BitReactor.GameplayEffect.Persists"
PENALTY_TAGS = ["BitReactor.AbilityEffect.Strike.TemporaryPenalty", "BitReactor.GameplayEffect.StatusEffect.Negative"]
# Tier effects also show beside the health bar and on the HUD portraits: those status lists take effects
# tagged br.UI.Effect.CoreCondition (GE_Injured and Backup Available carry it).
TIER_TAGS = PENALTY_TAGS + ["br.UI.Effect.CoreCondition"]
HEALTH = ("BitReactorHealthSet", "MaxHealth")
MOVEMENT = ("BitReactorCombatSet", "MovementPerAP")
ACTION_POINTS = ("BitReactorCombatSet", "ActionPoints")
MAX_HEALTH = '<Keyword id="UI.Keyword.Health">Max Health</>'
STATUS_TAG = "OffDuty.Status.%s"
STATUS_ICON = "ImageBank.Icon.Lethargy"
BRUNO_UI_DATA = "/Script/Bruno.BrunoGameEffectUIData"
STATUS_UI_DATA = "/Script/BitReactorGame.BRG_StatusEffectUIData"

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
        # "Deployed this strategy turn": set at mission start, cleared at turn end, so recovery skips
        # operators who played (saved, like the fatigue counter, so a reload can't lose it).
        "name": "GE_OffDuty_Deployed",
        "defaults": dict(COMMON, stack_limit_count=1, include_in_save_data=True, terminate_with_combat=False),
        "asset_tags": [PERSISTS],
        "modifiers": [],
    },
    {
        "name": "GE_OffDuty_Tired",
        "defaults": NEXT_MISSION_PENALTY,
        "asset_tags": TIER_TAGS,
        "modifiers": [],
        "ui": ("Tired", "Worn down from back-to-back deployments. <Bold>-5%</> Chance-To-Hit."),
    },
    {
        "name": "GE_OffDuty_Exhausted",
        "defaults": NEXT_MISSION_PENALTY,
        "asset_tags": TIER_TAGS,
        "modifiers": [(HEALTH, "MultiplyAdditive", 0.95)],
        "ui": ("Exhausted", "Pushed too hard for too long. <Bold>-10%%</> Chance-To-Hit, <Bold>-5%%</> %s, "
                            "<Bold>5%%</> chance each turn to lose <Bold>1 AP</>." % MAX_HEALTH),
    },
    {
        "name": "GE_OffDuty_Spent",
        "defaults": NEXT_MISSION_PENALTY,
        "asset_tags": TIER_TAGS,
        "modifiers": [(HEALTH, "MultiplyAdditive", 0.9), (MOVEMENT, "MultiplyAdditive", 0.95)],
        "ui": ("Spent", "Running on empty. <Bold>-15%%</> Chance-To-Hit, <Bold>-10%%</> %s, <Bold>-5%%</> "
                        "Movement, <Bold>10%%</> chance each turn to lose <Bold>1 AP</>." % MAX_HEALTH),
    },
    {
        "name": "GE_OffDuty_LoseAP",
        "defaults": {"duration_policy": unreal.GameplayEffectDurationType.INSTANT,
                     "stacking_type": unreal.GameplayEffectStackingType.NONE,
                     "include_in_save_data": False, "terminate_with_combat": True},
        "asset_tags": ["BitReactor.GameplayEffect.StatusEffect.Negative"],
        "modifiers": [(ACTION_POINTS, "AddBase", -1.0)],
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


def get_by_unreal_name(target, name):
    python_name = "".join("_" + c.lower() if c.isupper() else c for c in name).lstrip("_")
    errors = []
    for candidate in (name, python_name):
        try:
            return target.get_editor_property(candidate)
        except Exception as error:
            errors.append("%s: %s" % (candidate, error))
    fail("could not read %s on %s: %s" % (name, target.get_class().get_name(), " | ".join(errors)))


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


def gameplay_tag(name):
    tag = unreal.GameplayTag()
    tag.import_text('(TagName="%s")' % name)
    if name not in tag.export_text():
        fail("gameplay tag did not import (registered?): " + name)
    return tag


def remove_components(defaults, class_path):
    component_class = load_class(class_path)
    components = [c for c in defaults.get_editor_property("ge_components")
                  if c is not None and c.get_class() != component_class]
    defaults.set_editor_property("ge_components", components)


def apply_ui(defaults, name, description):
    status_tag = STATUS_TAG % name
    # Only the first UI data component counts, so drop the strategy-side one before adding ours.
    remove_components(defaults, BRUNO_UI_DATA)
    ui = component(defaults, STATUS_UI_DATA)
    set_by_unreal_name(ui, "StatusEffectTag", gameplay_tag(status_tag))
    set_by_unreal_name(ui, "PreviewTitle", unreal.Text(name))
    set_by_unreal_name(ui, "PreviewDescription", unreal.Text(description))
    icon = get_by_unreal_name(ui, "PreviewStatusEffectIcon")
    icon.import_text('(ImageReferenceType=ImageBank,ImageBankTag=(TagName="%s"))' % STATUS_ICON)
    name = set_by_unreal_name(ui, "PreviewStatusEffectIcon", icon)
    exported = ui.get_editor_property(name).export_text()
    if STATUS_ICON not in exported:
        fail("status icon not applied: " + exported)


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
    tags = list(spec["asset_tags"])
    if "ui" in spec:
        # The status view model exposes only asset tags, so each tier carries its own tag to tell them apart.
        tags.append(STATUS_TAG % spec["ui"][0])
    apply_asset_tags(defaults, tags)
    if "ui" in spec:
        apply_ui(defaults, *spec["ui"])

    blueprint.modify()
    if not assets.save_loaded_asset(blueprint, only_if_is_dirty=False):
        fail("could not save " + path)
    log("saved: %s | modifiers=%s | tags=%s" % (path, spec["modifiers"], tags))


for effect in EFFECTS:
    ensure_effect(effect)
unreal.log("OFFDUTY_RESULT ok")
