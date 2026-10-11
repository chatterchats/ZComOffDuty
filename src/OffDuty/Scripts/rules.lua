-- Fatigue rules: presets, tiers, gain and recovery, and the player-facing text.
-- Pure Lua (no Unreal calls), so tests can load it directly.
local M = {}

-- Presets differ in recovery per strategy turn off duty; the tiers (2 / 4 / 6) and cap (7) are shared.
-- With the default +2 per mission and Standard's -2, two squads alternating stay rested, and each mission
-- in a row puts an operator one tier higher. Once Crew Quarters allows THREE_SQUADS operators, recovery
-- halves, so it takes three squads to stay rested. Fractions are kept as banked quarter points.
M.PRESETS = {
    easy = { label = "Easy", recovery = 3, tired = 2, exhausted = 4, spent = 6, cap = 7 },
    standard = { label = "Standard", recovery = 2, tired = 2, exhausted = 4, spent = 6, cap = 7 },
    hard = { label = "Hard", recovery = 1.5, tired = 2, exhausted = 4, spent = 6, cap = 7 },
}
M.DEFAULT_PRESET = "standard"
M.THREE_SQUADS = 12 -- operator cap (Crew Quarters) at which recovery halves
M.DEFAULT_START_CYCLE = 5

-- Highest first. accuracy_stacks: the game's GE_Lose_NextMission_RangedAccuracy (-5% each).
-- level: 1 Tired, 2 Exhausted, 3 Spent (also the Zzz icon index).
M.TIERS = {
    {
        id = "spent", level = 3, name = "Spent", label = "SPENT",
        effect = "GE_OffDuty_Spent", accuracy_stacks = 4, ap_loss = 0.15,
        colour = "ColorBank.UI.AccentRed1",
        intro = "Running on empty.",
        penalties = { "<Bold>-20%</> Chance-To-Hit", "<Bold>-20%</> Max Health", "<Bold>-10%</> Movement" },
        ap_penalty = "<Bold>15%</> chance each turn to lose <Bold>1 AP</>",
    },
    {
        id = "exhausted", level = 2, name = "Exhausted", label = "EXHAUSTED",
        effect = "GE_OffDuty_Exhausted", accuracy_stacks = 2, ap_loss = 0.10,
        colour = "ColorBank.UI.AccentYellow", -- renders orange in game
        intro = "Pushed too hard for too long.",
        penalties = { "<Bold>-10%</> Chance-To-Hit", "<Bold>-10%</> Max Health" },
        ap_penalty = "<Bold>10%</> chance each turn to lose <Bold>1 AP</>",
    },
    {
        id = "tired", level = 1, name = "Tired", label = "TIRED",
        effect = "GE_OffDuty_Tired", accuracy_stacks = 1, ap_loss = 0,
        colour = { R = 0.98, G = 0.75, B = 0.07, A = 1.0 }, -- the palette has no true yellow
        intro = "Worn down from back-to-back deployments.",
        penalties = { "<Bold>-5%</> Chance-To-Hit", "<Bold>-5%</> Max Health" },
    },
}

-- Squad select only: a required operator left without a tier (half their fatigue is below Tired, or they
-- have none) gets this banner rather than RESTED. Not a tier (no effect, never applied in mission).
M.REQUIRED_RESTED = {
    id = "required", level = 1, name = "Required", label = "REQUIRED",
    colour = { R = 0.62, G = 0.72, B = 0.82, A = 1.0 },
    penalties = {},
}

-- Squad-slot banner for an operator with no tier, so every filled slot shows one. Level 0: no Zzz icon.
M.RESTED = {
    id = "rested", level = 0, name = "Rested", label = "RESTED",
    colour = { R = 0.45, G = 0.80, B = 0.50, A = 1.0 },
    penalties = {},
}

-- 2 -> "2", 1.5 -> "1.5", 0.75 -> "0.75"
function M.format_number(value)
    if value == math.floor(value) then return string.format("%d", value) end
    return (string.format("%.2f", value):gsub("0+$", ""))
end

local by_id = {}
for _, tier in ipairs(M.TIERS) do by_id[tier.id] = tier end

function M.tier_by_id(id) return by_id[id] end

function M.tier_by_level(level)
    for _, tier in ipairs(M.TIERS) do if tier.level == level then return tier end end
    return nil
end

function M.preset(name)
    return M.PRESETS[name] or M.PRESETS[M.DEFAULT_PRESET]
end

local function whole(value, default, low, high)
    value = math.floor(tonumber(value) or default)
    return math.max(low, math.min(high, value))
end

-- Settings come from MXM (or a hand-edited values.lua): clamp everything. Idempotent: an already
-- normalised table (gain/start keys) passes through unchanged. Recovery (rest) comes from the preset;
-- 1.0.0's recovery_per_turn setting is ignored.
function M.normalise(settings)
    settings = settings or {}
    local gain = settings.fatigue_per_mission
    if gain == nil then gain = settings.gain end
    local start = settings.start_cycle
    if start == nil then start = settings.start end
    local preset = M.PRESETS[settings.preset] and settings.preset or M.DEFAULT_PRESET
    return {
        preset = preset,
        gain = whole(gain, 2, 0, 7),
        rest = M.PRESETS[preset].recovery,
        ap_loss = settings.ap_loss ~= false,
        start = whole(start, M.DEFAULT_START_CYCLE, 1, 99),
    }
end

-- Fatigue only counts after a chosen cycle: early on the roster is too small to rotate. `turn` is the
-- game's strategy turn, which runs one behind the cycle it displays (turn 5 is "Cycle 6"), so a setting of
-- 5 starts fatigue on Cycle 6: "after cycle 5". An unreadable turn counts as active, so a failed read never
-- silently switches the mod off.
function M.active(turn, settings)
    turn = tonumber(turn)
    return turn == nil or turn >= M.normalise(settings).start
end

-- The tier for a fatigue count, or nil when rested.
function M.tier(points, preset_name)
    local preset = M.preset(preset_name)
    points = tonumber(points) or 0
    for _, tier in ipairs(M.TIERS) do
        if points >= preset[tier.id] then return tier end
    end
    return nil
end

-- Fatigue that sets a deployed operator's tier: a mission's required operators (story missions that
-- can't launch without them) go in at half their fatigue, rounded down. Their real fatigue doesn't change
-- and the mission still adds the usual gain.
function M.mission_points(points, required)
    points = tonumber(points) or 0
    if required then return math.floor(points / 2) end
    return points
end

function M.after_mission(points, settings)
    local s = M.normalise(settings)
    return math.min((tonumber(points) or 0) + s.gain, M.preset(s.preset).cap)
end

-- Recovery per strategy turn off duty: the preset's, halved once the operator cap reaches THREE_SQUADS.
-- An unknown cap (nil) counts as below it.
function M.recovery(settings, roster_cap)
    local rest = M.normalise(settings).rest
    if (tonumber(roster_cap) or 0) >= M.THREE_SQUADS then return rest / 2 end
    return rest
end

-- One strategy turn off duty. Recovery is counted in quarter points so fractions (Hard's 1.5, 0.75 with a
-- big roster) work with whole fatigue stacks: `banked` is the carried remainder, 0-3 quarters (saved as
-- GE_OffDuty_RestCredit stacks). Returns the new fatigue and the new remainder; nothing stays banked once
-- fatigue reaches 0.
function M.after_rest(points, settings, banked, roster_cap)
    points = tonumber(points) or 0
    local quarters = math.floor(M.recovery(settings, roster_cap) * 4 + 0.5) + (tonumber(banked) or 0)
    local after = math.max(points - math.floor(quarters / 4), 0)
    return after, after > 0 and quarters % 4 or 0
end

-- Strategy turns off duty until fully rested.
function M.turns_to_rest(points, settings, banked, roster_cap)
    points = tonumber(points) or 0
    local turns = 0
    while points > 0 and turns < 99 do
        points, banked = M.after_rest(points, settings, banked, roster_cap)
        turns = turns + 1
    end
    return turns
end

-- A tier's penalty lines under these settings (the AP-loss line only while AP loss is on).
function M.penalties(tier, settings)
    local lines = {}
    for _, penalty in ipairs(tier.penalties) do lines[#lines + 1] = penalty end
    if tier.ap_penalty and M.normalise(settings).ap_loss then lines[#lines + 1] = tier.ap_penalty end
    return lines
end

-- In-mission debuff description (shared per tier, so no per-operator numbers).
function M.status_description(tier, settings)
    local lines = { tier.intro }
    for _, penalty in ipairs(M.penalties(tier, settings)) do lines[#lines + 1] = penalty end
    lines[#lines + 1] = "Rest off duty to recover."
    return table.concat(lines, "\n")
end

-- Squad-select tooltip for one operator. `tier` is the tier they deploy at; for a required operator that
-- comes from half their fatigue (M.mission_points), and the tooltip says so.
-- starts_after: the cycle setting, given while fatigue hasn't started yet. roster_cap: the operator cap
-- (Crew Quarters), which halves recovery at THREE_SQUADS.
function M.tooltip(tier, points, settings, required, starts_after, roster_cap)
    local s = M.normalise(settings)
    local cap = M.preset(s.preset).cap
    local rest = M.recovery(s, roster_cap)
    local lines = {
        string.format("Fatigue <Bold>%d</> of %d. Each mission adds %d; each turn off duty removes %s%s.",
            points, cap, s.gain, M.format_number(rest),
            rest < s.rest and string.format(" (halved: room for %d+ operators)", M.THREE_SQUADS) or ""),
    }
    if starts_after then
        lines[#lines + 1] = string.format("Fatigue tracking starts after cycle <Bold>%d</>.", starts_after)
    end
    if required and points > 0 then
        lines[#lines + 1] = string.format("<Bold>Required:</> fatigue counts as half for this mission (%d instead of %d).",
            M.mission_points(points, true), points)
    elseif required then
        lines[#lines + 1] = "<Bold>Required</> for this mission."
    end
    lines[#lines + 1] = ""
    local penalties = M.penalties(tier, settings)
    if #penalties == 0 then
        lines[#lines + 1] = "Next mission: no penalty."
    else
        lines[#lines + 1] = "Next mission:"
        for _, penalty in ipairs(penalties) do lines[#lines + 1] = "  " .. penalty end
    end
    local turns = M.turns_to_rest(points, settings, 0, roster_cap)
    if turns > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("Fully rested after <Bold>%d</> turn%s off duty.", turns, turns == 1 and "" or "s")
    end
    return table.concat(lines, "\n")
end

return M
