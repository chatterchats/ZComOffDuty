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

-- Every preset: tiers at 2 / 4 / 6, cap 7; presets differ only in recovery.
for _, preset in ipairs({ "easy", "standard", "hard", "nonsense" }) do
    for points, expected in pairs({ [0] = "rested", [1] = "rested", [2] = "tired", [3] = "tired", [4] = "exhausted",
                                    [5] = "exhausted", [6] = "spent", [7] = "spent" }) do
        eq(tier_id(points, preset), expected, preset .. " tier at " .. points)
    end
    eq(rules.after_mission(6, { preset = preset }), 7, preset .. " cap")
end
eq(rules.normalise({ preset = "nonsense" }).preset, "standard", "unknown preset falls back to standard")
eq(rules.after_mission(0, { fatigue_per_mission = 3 }), 3, "custom gain")

-- Recovery per turn off duty: Easy 3, Standard 2, Hard 1.5 (1, then 2: a banked half point).
eq((rules.after_rest(7, { preset = "easy" })), 4, "easy -3")
eq((rules.after_rest(7, {})), 5, "standard -2 (default)")
local after, banked = rules.after_rest(7, { preset = "hard" })
eq(after, 6, "hard first turn -1"); eq(banked, 2, "hard banks a half (2 quarters)")
after, banked = rules.after_rest(after, { preset = "hard" }, banked)
eq(after, 4, "hard second turn -2"); eq(banked, 0, "bank spent")
eq((rules.after_rest(1, {})), 0, "rest to zero"); eq((rules.after_rest(0, {})), 0, "never negative")
local _, kept = rules.after_rest(1, { preset = "hard" })
eq(kept, 0, "nothing banked once rested")

-- Once Crew Quarters allows 12+ operators, recovery halves (three squads to stay rested).
eq(rules.recovery({}, 11), 2, "standard below 12"); eq(rules.recovery({}, 12), 1, "standard at 12+")
eq(rules.recovery({ preset = "easy" }, 13), 1.5, "easy at 12+"); eq(rules.recovery({ preset = "hard" }, 12), 0.75, "hard at 12+")
eq(rules.recovery({}, nil), 2, "unknown cap counts as below 12")
local p, q, sequence = 7, 0, {}
for _ = 1, 4 do p, q = rules.after_rest(p, { preset = "hard" }, q, 12); sequence[#sequence + 1] = p end
eq(table.concat(sequence, ","), "7,6,5,4", "hard 0.75: 0, 1, 1, 1 over four turns")
-- Three squads rotating stay rested at 12+ on Standard (+2, then -1, -1).
p = 0
for _ = 1, 4 do
    eq(tier_id(p), "rested", "three squads deploy rested at 12+")
    p = rules.after_mission(p, {})
    p = rules.after_rest(p, {}, 0, 12); p = rules.after_rest(p, {}, 0, 12)
end
assert(rules.tooltip(rules.tier_by_id("tired"), 2, {}, false, nil, 12):find("removes 1 (halved: room for 12+ operators)", 1, true), "halved tooltip")
eq(rules.format_number(0.75), "0.75", "format 0.75"); eq(rules.format_number(1.5), "1.5", "format 1.5")
eq(rules.normalise({ recovery_per_turn = 3 }).rest, 2, "1.0.0's recovery setting is ignored")

-- Two squads alternating stay rested on Standard; each mission in a row is one tier worse.
local points = 0
for _ = 1, 6 do
    eq(tier_id(points), "rested", "alternating squads deploy rested")
    points = rules.after_mission(points, {})
    points = rules.after_rest(points, {})
end
points = 0
for _, expected in ipairs({ "rested", "tired", "exhausted", "spent" }) do
    eq(tier_id(points), expected, "back-to-back mission tier")
    points = rules.after_mission(points, {})
end

-- Settings are clamped (values.lua can be hand-edited).
local s = rules.normalise({ preset = "x", fatigue_per_mission = 99, ap_loss = false })
eq(s.preset, "standard", "bad preset"); eq(s.gain, 7, "gain clamp"); eq(s.ap_loss, false, "ap_loss off")
eq(rules.normalise({}).ap_loss, true, "ap_loss default on")
-- Idempotent: callers pass normalised settings back in.
local custom = rules.normalise({ preset = "hard", fatigue_per_mission = 3, ap_loss = false })
local again = rules.normalise(custom)
eq(again.preset, "hard", "renormalise preset"); eq(again.gain, 3, "renormalise gain")
eq(again.rest, 1.5, "renormalise rest"); eq(again.ap_loss, false, "renormalise ap_loss")
eq(rules.after_mission(0, custom), 3, "after_mission with normalised settings")

eq(rules.turns_to_rest(7, {}), 4, "turns to rest (standard: 7 5 3 1 0)")
eq(rules.turns_to_rest(7, { preset = "hard" }), 5, "turns to rest (hard: 7 6 4 3 1 0)")
eq(rules.turns_to_rest(0, {}), 0, "already rested")

-- Text mentions the operator's numbers.
local text = rules.tooltip(rules.tier_by_id("spent"), 6, {})
assert(text:find("Fatigue <Bold>6</> of 7", 1, true), "tooltip points")
assert(text:find("3</> turns off duty", 1, true), "tooltip rest turns")
assert(rules.tooltip(rules.tier_by_id("spent"), 6, { preset = "hard" }):find("removes 1.5", 1, true), "hard tooltip says 1.5")
assert(rules.status_description(rules.tier_by_id("tired")):find("Rest off duty", 1, true), "status text")
-- The AP-loss line follows the setting.
local spent = rules.tier_by_id("spent")
assert(rules.tooltip(spent, 6, {}):find("lose <Bold>1 AP", 1, true), "AP line when on")
assert(not rules.tooltip(spent, 6, { ap_loss = false }):find("AP", 1, true), "no AP line when off")
assert(rules.status_description(spent, {}):find("1 AP", 1, true), "status AP line when on")
assert(not rules.status_description(spent, { ap_loss = false }):find("AP", 1, true), "status no AP line when off")
eq(#rules.penalties(rules.tier_by_id("tired"), {}), 2, "Tired: hit and health, no AP line")
eq(#rules.penalties(rules.tier_by_id("spent"), {}), 4, "Spent: hit, health, movement, AP")
eq(rules.tier_by_id("spent").accuracy_stacks, 4, "Spent -20% hit is 4 stacks")
-- Required operators go in at half their fatigue, rounded down.
eq(rules.mission_points(5, true), 2, "required: half of 5"); eq(rules.mission_points(5, false), 5, "not required: full")
eq(rules.mission_points(1, true), 0, "required: half of 1 rounds down")
-- Fatigue starts at a cycle (default 5); an unreadable turn counts as active.
assert(not rules.active(4, {}) and rules.active(5, {}) and rules.active(nil, {}), "start cycle 5")
assert(rules.active(1, { start_cycle = 1 }) and not rules.active(9, { start_cycle = 10 }), "custom start cycle")
eq(rules.normalise({ start_cycle = 0 }).start, 1, "start cycle clamps to 1")
assert(rules.tooltip(rules.RESTED, 0, {}, false, 5):find("Fatigue tracking starts after cycle <Bold>5</>.", 1, true), "early tooltip")
-- The squad-select tooltip says when a required operator's fatigue counts as half.
local req = rules.tooltip(rules.tier_by_id("tired"), 5, {}, true)
assert(req:find("<Bold>Required:</> fatigue counts as half for this mission (2 instead of 5).", 1, true), req)
assert(req:find("Fatigue <Bold>5</> of 7", 1, true), "required tooltip keeps the real fatigue")
assert(not rules.tooltip(rules.tier_by_id("tired"), 5, {}):find("Required", 1, true), "no required line otherwise")
local waived = rules.tooltip(rules.REQUIRED_RESTED, 1, {}, true)
assert(waived:find("(0 instead of 1)", 1, true) and waived:find("Next mission: no penalty.", 1, true), waived)
local rested = rules.tooltip(rules.RESTED, 0, {}, true)
assert(rested:find("Next mission: no penalty.", 1, true) and not rested:find("instead of", 1, true), "nothing to halve")
assert(rested:find("<Bold>Required</> for this mission.", 1, true), "required at 0 fatigue still says so")
assert(not rules.tooltip(rules.RESTED, 0, {}):find("Required", 1, true), "plain rested: no required line")
print("rules ok")
