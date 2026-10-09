-- Fatigue rules: presets, tiers, gain and recovery, and the player-facing text.
-- Pure Lua (no Unreal calls), so tests can load it directly.
local M = {}

-- Thresholds per preset (fatigue points at which each tier starts) and the cap.
M.PRESETS = {
    hard = { label = "Hard", tired = 1, exhausted = 3, spent = 5, cap = 7 },
    standard = { label = "Standard", tired = 2, exhausted = 4, spent = 6, cap = 6 },
}
M.DEFAULT_PRESET = "hard"

-- Highest first. accuracy_stacks: the game's GE_Lose_NextMission_RangedAccuracy (-5% each).
-- level: 1 Tired, 2 Exhausted, 3 Spent (also the Zzz icon index).
M.TIERS = {
    {
        id = "spent", level = 3, name = "Spent", label = "SPENT",
        effect = "GE_OffDuty_Spent", accuracy_stacks = 3, ap_loss = 0.10,
        colour = "ColorBank.UI.AccentRed1",
        intro = "Running on empty.",
        penalties = { "<Bold>-15%</> Chance-To-Hit", "<Bold>-10%</> Max Health", "<Bold>-5%</> Movement",
                      "<Bold>10%</> chance each turn to lose <Bold>1 AP</>" },
    },
    {
        id = "exhausted", level = 2, name = "Exhausted", label = "EXHAUSTED",
        effect = "GE_OffDuty_Exhausted", accuracy_stacks = 2, ap_loss = 0.05,
        colour = "ColorBank.UI.AccentYellow", -- renders orange in game
        intro = "Pushed too hard for too long.",
        penalties = { "<Bold>-10%</> Chance-To-Hit", "<Bold>-5%</> Max Health",
                      "<Bold>5%</> chance each turn to lose <Bold>1 AP</>" },
    },
    {
        id = "tired", level = 1, name = "Tired", label = "TIRED",
        effect = "GE_OffDuty_Tired", accuracy_stacks = 1, ap_loss = 0,
        colour = { R = 0.98, G = 0.75, B = 0.07, A = 1.0 }, -- the palette has no true yellow
        intro = "Worn down from back-to-back deployments.",
        penalties = { "<Bold>-5%</> Chance-To-Hit" },
    },
}

local by_id = {}
for _, tier in ipairs(M.TIERS) do by_id[tier.id] = tier end

function M.tier_by_id(id) return by_id[id] end

function M.preset(name)
    return M.PRESETS[name] or M.PRESETS[M.DEFAULT_PRESET]
end

local function whole(value, default, low, high)
    value = math.floor(tonumber(value) or default)
    return math.max(low, math.min(high, value))
end

-- Settings come from MXM (or a hand-edited values.lua): clamp everything.
function M.normalise(settings)
    settings = settings or {}
    return {
        preset = M.PRESETS[settings.preset] and settings.preset or M.DEFAULT_PRESET,
        gain = whole(settings.fatigue_per_mission, 2, 0, 7),
        rest = whole(settings.recovery_per_turn, 1, 0, 7),
        ap_loss = settings.ap_loss ~= false,
    }
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

function M.after_mission(points, settings)
    local s = M.normalise(settings)
    return math.min((tonumber(points) or 0) + s.gain, M.preset(s.preset).cap)
end

function M.after_rest(points, settings)
    local s = M.normalise(settings)
    return math.max((tonumber(points) or 0) - s.rest, 0)
end

-- Strategy turns off duty until fully rested (nil if recovery is off).
function M.turns_to_rest(points, settings)
    local s = M.normalise(settings)
    points = tonumber(points) or 0
    if points <= 0 then return 0 end
    if s.rest <= 0 then return nil end
    return math.ceil(points / s.rest)
end

-- In-mission debuff description (shared per tier, so no per-operator numbers).
function M.status_description(tier)
    local lines = { tier.intro }
    for _, penalty in ipairs(tier.penalties) do lines[#lines + 1] = penalty end
    lines[#lines + 1] = "Rest off duty to recover."
    return table.concat(lines, "\n")
end

-- Squad-select tooltip for one operator.
function M.tooltip(tier, points, settings)
    local s = M.normalise(settings)
    local cap = M.preset(s.preset).cap
    local lines = {
        string.format("Fatigue <Bold>%d</> of %d. Each mission adds %d; each turn off duty removes %d.",
            points, cap, s.gain, s.rest),
        "",
        "Next mission:",
    }
    for _, penalty in ipairs(tier.penalties) do lines[#lines + 1] = "  " .. penalty end
    local turns = M.turns_to_rest(points, settings)
    if turns then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("Fully rested after <Bold>%d</> turn%s off duty.", turns, turns == 1 and "" or "s")
    end
    return table.concat(lines, "\n")
end

return M
