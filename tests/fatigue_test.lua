-- The fatigue loop against a fake game layer (effects are per-operator counters).
-- Run from repository root: tools/run-tests.sh fatigue
local scripts = assert(arg[1], "pass the mod Scripts directory")
package.path = scripts .. "/?.lua;" .. package.path
local Game = require("game")
local Fatigue = require("fatigue")

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what, tostring(expected), tostring(actual)), 2)
    end
end

-- Operators: the actor doubles as its own ability system component.
local function operator(name, id, fatigue, extra)
    local op = { actor = true, name = name, id = id, effects = { [Game.FATIGUE] = fatigue or 0 }, player = true }
    for k, v in pairs(extra or {}) do op[k] = v end
    op.owner = op
    return op
end

local roster, logs, hooks, scheduled = {}, {}, {}, 0
mission_ready = true
loading_save = false
local settings = {}
local g = {
    unwrap = function(x) return x end,
    valid = function(x) return x ~= nil end,
    is_actor = function(x) return type(x) == "table" and x.actor == true end,
    full_name = function(x) return type(x) == "table" and (x.full_name or x.name) or tostring(x) end,
    character_name = function(a) return a.name end,
    character_id = function(a) return a.id end,
    world_context = function() return {} end,
    roster = function()
        local members = {}
        for _, op in ipairs(roster) do
            members[#members + 1] = { id = op.id, away = op.away == true, actor = not op.no_actor and op or nil }
        end
        return members
    end,
    roster_ids = function()
        local ids = {}
        for _, op in ipairs(roster) do ids[op.id] = true end
        return ids
    end,
    asc = function(actor) return actor end,
    effect_class = function(name) return name end,
    load_class = function(path) return path end,
    effect_count = function(asc, class) return asc and class and asc.effects[class] or 0 end,
    apply_effect = function(asc, class, times)
        asc.effects[class] = (asc.effects[class] or 0) + (times or 1)
    end,
    set_effect_count = function(asc, class, target) asc.effects[class] = target; return target end,
    call = function(object, method)
        if method == "GetOwner" then return object.owner end
        if method == "IsPlayerTeamMember" then return nil end -- see unit_statics below
    end,
    unit_statics = function() return nil end,
    safe = function(_, callback) return callback end, -- let errors fail the test
    mission_actor = function() return {} end,
    loading_from_save = function() return loading_save end,
    was_loaded_from_save = function(actor) return actor.from_save == true end,
    mission_ready = function() return mission_ready end,
}
-- IsPlayerTeamMember is called on unit_statics() with the owner: route it through the owner.
g.call = function(object, method, arg)
    if method == "GetOwner" then return object.owner end
    if method == "IsPlayerTeamMember" then return arg and arg.player == true end
end

local ctx = {
    game = g,
    log = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
    settings = function() return settings end,
    runtime = { register_hook = function(_, path, _, post) hooks[path:match(":(.+)$")] = post end },
    actions = {
        cancel_group = function() end,
        schedule_after = function(_, _, _, callback) scheduled = scheduled + 1; callback() end,
    },
}
Fatigue.new(ctx):install()
local mission_start, end_turn, team_turn = hooks.ApplyNextMissionEffectsToCharacter, hooks.EndStrategyTurn,
    hooks.OnTeamTurnStarted
assert(mission_start and end_turn and team_turn, "hooks installed")

local ACCURACY = Game.ACCURACY
local tesh = operator("Tesh", "T", 1)
local kabb = operator("Kabb", "K", 3)
local kara = operator("Kara", "N", 6)
local benched = operator("Luco", "L", 3)
local away = operator("Jae", "J", 4, { away = true })
local absent = operator("Ghost", "G", 2, { no_actor = true })
local rex = operator("Rex", "R", 0) -- guest: not on the roster
roster = { tesh, kabb, kara, benched, away, absent }

-- Mission start: tier from current fatigue, deployed marker, then +2 (capped).
for _, op in ipairs({ tesh, kabb, kara, rex }) do mission_start(nil, op) end
eq(tesh.effects.GE_OffDuty_Tired, 1, "Tesh tired effect"); eq(tesh.effects[ACCURACY], 1, "Tesh accuracy")
eq(tesh.effects[Game.FATIGUE], 3, "Tesh fatigue +2")
eq(kabb.effects.GE_OffDuty_Exhausted, 1, "Kabb exhausted effect"); eq(kabb.effects[ACCURACY], 2, "Kabb accuracy")
eq(kabb.effects[Game.FATIGUE], 5, "Kabb fatigue +2")
eq(kara.effects.GE_OffDuty_Spent, 1, "Kara spent effect"); eq(kara.effects[ACCURACY], 3, "Kara accuracy")
eq(kara.effects[Game.FATIGUE], 7, "Kara capped at 7")
eq(kabb.effects[Game.DEPLOYED], 3, "Kabb marked deployed, tier Exhausted recorded (1 + 2)")
eq(tesh.effects[Game.DEPLOYED], 2, "Tesh marker records Tired")
eq(rex.effects[Game.FATIGUE], 0, "guest untouched"); eq(rex.effects[Game.DEPLOYED], nil, "guest not marked")

-- At mission load the roster can't be read yet: processing waits for it.
local unreadable = 2
local roster_ids = g.roster_ids
g.roster_ids = function(...)
    if unreadable > 0 then unreadable = unreadable - 1; return {} end
    return roster_ids(...)
end
local late = operator("Tel-Rea", "V", 1)
roster[#roster + 1] = late
mission_start(nil, late)
eq(late.effects[Game.FATIGUE], 3, "processed once the roster answers")
eq(late.effects.GE_OffDuty_Tired, 1, "late: tier applied")
unreadable = 99
local never = operator("Luco2", "L2", 1)
roster[#roster + 1] = never
mission_start(nil, never)
eq(never.effects[Game.FATIGUE], 1, "roster never readable: untouched")
assert(logs[#logs]:find("not ready after 8 tries", 1, true), logs[#logs])
g.roster_ids = roster_ids

-- A second call in the same turn changes nothing.
mission_start(nil, kabb)
eq(kabb.effects[Game.FATIGUE], 5, "no double gain"); eq(kabb.effects[ACCURACY], 2, "no double penalty")

-- Loading a tactical save: the hook fires before the save restores effects (mission not ready yet).
-- Once ready, the restored marker means "already counted": no gain; the tier is restored.
local restored = operator("Saved", "S1", 5, { effects = {}, from_save = true }) -- effects arrive with the save
roster[#roster + 1] = restored
local load_checks = 0
loading_save = true
g.loading_from_save = function()
    load_checks = load_checks + 1
    if load_checks < 4 then return true end
    -- the save's effects are restored by the time loading reports done
    -- tier effects aren't saved; the marker records the starting tier (Spent: 1 + 3)
    restored.effects[Game.FATIGUE] = 5; restored.effects[Game.DEPLOYED] = 4
    return false
end
mission_start(nil, restored)
eq(restored.effects[Game.FATIGUE], 5, "loaded save: no gain")
eq(restored.effects.GE_OffDuty_Spent, 1, "loaded save: tier restored from the marker")
eq(restored.effects[ACCURACY], 3, "loaded save: accuracy re-applied for the tier")
assert(logs[#logs]:find("Mission resumed", 1, true), logs[#logs])
g.loading_from_save = function() return false end
-- An older save without the tier effect: fall back to the tier this mission started at (fatigue - gain).
local old = operator("Old", "O1", 5, { effects = { [Game.FATIGUE] = 5, [Game.DEPLOYED] = 1 }, from_save = true })
roster[#roster + 1] = old
mission_start(nil, old)
eq(old.effects.GE_OffDuty_Exhausted, 1, "old save: tier from fatigue before the mission (3)")
eq(old.effects[Game.FATIGUE], 5, "old save: no gain")
-- Fatigue above the cap (an earlier bug) is clamped.
local over = operator("Over", "O2", 9, { effects = { [Game.FATIGUE] = 9, [Game.DEPLOYED] = 1 } })
roster[#roster + 1] = over
mission_start(nil, over)
eq(over.effects[Game.FATIGUE], 7, "clamped to cap")
-- A save made mid-mission before Off Duty counted it (no marker): resumed, no gain.
local unmarked = operator("Unmarked", "U1", 3, { from_save = true })
roster[#roster + 1] = unmarked
mission_start(nil, unmarked)
eq(unmarked.effects[Game.FATIGUE], 3, "loaded save without marker: no gain")
eq(unmarked.effects[Game.DEPLOYED], nil, "loaded save without marker: not marked")

-- A rested operator deploys with no penalty.
local fresh = operator("Cly", "C", 0)
roster[#roster + 1] = fresh
mission_start(nil, fresh)
eq(fresh.effects[ACCURACY], nil, "rested: no accuracy penalty"); eq(fresh.effects[Game.FATIGUE], 2, "rested +2")

-- Turn end: deployed keep their fatigue (marker cleared), benched recover, away are frozen.
end_turn()
eq(kabb.effects[Game.FATIGUE], 5, "deployed don't recover"); eq(kabb.effects[Game.DEPLOYED], 0, "marker cleared")
eq(benched.effects[Game.FATIGUE], 2, "benched recover 1")
eq(away.effects[Game.FATIGUE], 4, "away frozen")
eq(absent.effects[Game.FATIGUE], 2, "no hub actor: unchanged")
-- Next turn everyone sits out: the deployed recover too.
end_turn()
eq(kabb.effects[Game.FATIGUE], 4, "recovers the turn after")
eq(benched.effects[Game.FATIGUE], 1, "benched again")

-- Settings: Standard preset and custom gain/rest.
settings = { preset = "standard", fatigue_per_mission = 3, recovery_per_turn = 2 }
local std = operator("Tel", "E", 3)
roster[#roster + 1] = std
mission_start(nil, std) -- 3 on Standard is Tired (2), not Exhausted (4)
eq(std.effects.GE_OffDuty_Tired, 1, "standard tier"); eq(std.effects[Game.FATIGUE], 6, "standard +3, cap 6")
end_turn(); end_turn()
eq(std.effects[Game.FATIGUE], 4, "rest 2 per turn after the deployed turn")
settings = {}

-- AP loss: only the real PlayerTeam turn, only Exhausted/Spent, at their odds.
local real_random = math.random
local function team(path) return { full_name = "BlueprintGeneratedClass " .. path } end
local PLAYER = team(Game.PLAYER_TEAM)
local PRE_PLAYER = team("/Game/Game/GameData/Teams/WorldTeam_PrePlayer.WorldTeam_PrePlayer_C")
local spent = operator("BR-1", "B", 0, { effects = { GE_OffDuty_Spent = 1 } })
local exhausted = operator("Kabb2", "K2", 0, { effects = { GE_OffDuty_Exhausted = 1 } })
local enemy = operator("Trooper", "X", 0, { effects = { GE_OffDuty_Spent = 1 }, player = false })

math.random = function() return 0.05 end -- below Spent's 10%, at Exhausted's 5%
team_turn(spent, PRE_PLAYER)
eq(spent.effects[Game.LOSE_AP], nil, "WorldTeam_PrePlayer doesn't roll")
team_turn(spent, PLAYER)
eq(spent.effects[Game.LOSE_AP], 1, "Spent loses AP at 5% < 10%")
team_turn(exhausted, PLAYER)
eq(exhausted.effects[Game.LOSE_AP], nil, "Exhausted safe at 5% (needs < 5%)")
team_turn(enemy, PLAYER)
eq(enemy.effects[Game.LOSE_AP], nil, "non-player units never roll")
team_turn(tesh, PLAYER)
eq(tesh.effects[Game.LOSE_AP], nil, "Tired never loses AP")
settings = { ap_loss = false }
team_turn(spent, PLAYER)
eq(spent.effects[Game.LOSE_AP], 1, "AP loss off in settings")
math.random = real_random

-- Penalties never touch injuries.
for _, op in ipairs(roster) do assert(op.effects.GE_Injured == nil, "no injuries added") end
print("fatigue ok")
