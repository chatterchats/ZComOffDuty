-- Run from repository root: tools/run-tests.sh rules
local scripts = assert(arg[1], "pass the mod Scripts directory")
package.path = scripts .. "/?.lua;" .. package.path
local rules = require("rules")

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
    end
end
local function tier_id(points, preset)
    local tier = rules.tier(points, preset)
    return tier and tier.id or "rested"
end

-- Hard preset: tiers at 1 / 3 / 5, cap 7.
for points, expected in pairs({ [0] = "rested", [1] = "tired", [2] = "tired", [3] = "exhausted",
                                [4] = "exhausted", [5] = "spent", [7] = "spent" }) do
    eq(tier_id(points, "hard"), expected, "hard tier at " .. points)
end
-- Standard preset: 2 / 4 / 6, cap 6.
for points, expected in pairs({ [1] = "rested", [2] = "tired", [4] = "exhausted", [6] = "spent" }) do
    eq(tier_id(points, "standard"), expected, "standard tier at " .. points)
end
eq(tier_id(3, "nonsense"), "exhausted", "unknown preset falls back to hard")

-- Gain caps at the preset's cap; recovery floors at 0.
eq(rules.after_mission(6, {}), 7, "hard cap")
eq(rules.after_mission(5, { preset = "standard" }), 6, "standard cap")
eq(rules.after_mission(0, { fatigue_per_mission = 3 }), 3, "custom gain")
eq(rules.after_rest(1, {}), 0, "rest to zero")
eq(rules.after_rest(0, {}), 0, "never negative")
eq(rules.after_rest(5, { recovery_per_turn = 2 }), 3, "custom rest")

-- Settings are clamped (values.lua can be hand-edited).
local s = rules.normalise({ preset = "x", fatigue_per_mission = 99, recovery_per_turn = -4, ap_loss = false })
eq(s.preset, "hard", "bad preset"); eq(s.gain, 7, "gain clamp"); eq(s.rest, 0, "rest clamp"); eq(s.ap_loss, false, "ap_loss off")
eq(rules.normalise({}).ap_loss, true, "ap_loss default on")
-- Idempotent: callers pass normalised settings back in.
local custom = rules.normalise({ preset = "standard", fatigue_per_mission = 3, recovery_per_turn = 2, ap_loss = false })
local again = rules.normalise(custom)
eq(again.preset, "standard", "renormalise preset"); eq(again.gain, 3, "renormalise gain")
eq(again.rest, 2, "renormalise rest"); eq(again.ap_loss, false, "renormalise ap_loss")
eq(rules.after_mission(0, custom), 3, "after_mission with normalised settings")

eq(rules.turns_to_rest(7, {}), 7, "turns to rest")
eq(rules.turns_to_rest(5, { recovery_per_turn = 2 }), 3, "turns to rest rounds up")
eq(rules.turns_to_rest(3, { recovery_per_turn = 0 }), nil, "no recovery")

-- One push-through cycle on hard: 2 missions in a row is Exhausted, a third is Spent.
local points = 0
for _ = 1, 3 do points = rules.after_mission(points, {}) end
eq(points, 6, "three missions"); eq(tier_id(points), "spent", "three missions tier")

-- Text mentions the operator's numbers.
local text = rules.tooltip(rules.tier_by_id("spent"), 6, {})
assert(text:find("Fatigue <Bold>6</> of 7", 1, true), "tooltip points")
assert(text:find("6</> turns off duty", 1, true), "tooltip rest turns")
assert(rules.status_description(rules.tier_by_id("tired")):find("Rest off duty", 1, true), "status text")
-- The AP-loss line follows the setting.
local spent = rules.tier_by_id("spent")
assert(rules.tooltip(spent, 6, {}):find("lose <Bold>1 AP", 1, true), "AP line when on")
assert(not rules.tooltip(spent, 6, { ap_loss = false }):find("AP", 1, true), "no AP line when off")
assert(rules.status_description(spent, {}):find("1 AP", 1, true), "status AP line when on")
assert(not rules.status_description(spent, { ap_loss = false }):find("AP", 1, true), "status no AP line when off")
eq(#rules.penalties(rules.tier_by_id("tired"), {}), 1, "Tired has no AP line")
print("rules ok")
