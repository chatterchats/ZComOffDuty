-- The fatigue loop against a fake game layer (effects are per-operator counters).
-- Run from repository root: tools/run-tests.sh fatigue
local scripts = assert(arg[1], "pass the mod Scripts directory")
package.path = scripts .. "/?.lua;" .. package.path
FName = FName or function(name) return name end -- UE4SS global
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
local required = {} -- the current mission's required operators: id -> blocking
cycle = 10 -- strategy turn (global so tests can move it); fatigue starts at cycle 5 by default
roster_cap = 8 -- operator cap (Crew Quarters); recovery halves at 12
mission_ready = true
loading_save = false
local settings = { preset = "hard" } -- Hard: tiers 2 / 4 / 6, recovery 1.5 (1, then 2)
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
    required_ids = function() return required end,
    strategy_turn = function() return cycle end,
    roster_cap = function() return roster_cap end,
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
local tesh = operator("Tesh", "T", 2)
local kabb = operator("Kabb", "K", 4)
local kara = operator("Kara", "N", 6)
local benched = operator("Luco", "L", 3)
local away = operator("Jae", "J", 4, { away = true })
local absent = operator("Ghost", "G", 2, { no_actor = true })
local rex = operator("Rex", "R", 0) -- guest: not on the roster
roster = { tesh, kabb, kara, benched, away, absent }

-- Mission start: tier from current fatigue, deployed marker, then +2 (capped).
for _, op in ipairs({ tesh, kabb, kara, rex }) do mission_start(nil, op) end
eq(tesh.effects.GE_OffDuty_Tired, 1, "Tesh tired effect"); eq(tesh.effects[ACCURACY], 1, "Tesh accuracy")
eq(tesh.effects[Game.FATIGUE], 4, "Tesh fatigue +2")
eq(kabb.effects.GE_OffDuty_Exhausted, 1, "Kabb exhausted effect"); eq(kabb.effects[ACCURACY], 2, "Kabb accuracy")
eq(kabb.effects[Game.FATIGUE], 6, "Kabb fatigue +2")
eq(kara.effects.GE_OffDuty_Spent, 1, "Kara spent effect"); eq(kara.effects[ACCURACY], 4, "Kara accuracy")
eq(kara.effects[Game.FATIGUE], 7, "Kara capped at 7")
eq(kabb.effects[Game.DEPLOYED], 3, "Kabb marked deployed, tier Exhausted recorded (1 + 2)")
eq(tesh.effects[Game.DEPLOYED], 2, "Tesh marker records Tired")
eq(rex.effects[Game.FATIGUE], 0, "guest untouched"); eq(rex.effects[Game.DEPLOYED], nil, "guest not marked")

-- Before the starting cycle (default 5) a mission adds no fatigue and applies no tier.
cycle = 3
local early = operator("Rookie", "RK", 3)
roster[#roster + 1] = early
mission_start(nil, early)
eq(early.effects[Game.FATIGUE], 3, "before cycle 5: no gain"); eq(early.effects.GE_OffDuty_Tired, nil, "no tier")
eq(early.effects[Game.DEPLOYED], nil, "no marker")
assert(logs[#logs]:find("cycle 4, fatigue starts after cycle 5", 1, true), logs[#logs]) -- turn 3 shows as Cycle 4
settings = { preset = "hard", start_cycle = 1 }
local first = operator("Day One", "D1", 0)
roster[#roster + 1] = first
mission_start(nil, first)
eq(first.effects[Game.FATIGUE], 2, "start_cycle 1: counts from the first cycle")
settings = { preset = "hard" }
cycle = 10

-- Required operators go in at half their fatigue (rounded down); fatigue itself still gains as usual.
-- Every listed operator counts, blocking or not (a locked story operator reads non-blocking).
local hero = operator("Hawks", "H", 6)      -- Spent at 6; half is 3: Tired
local forced = operator("Cly", "C", 4)      -- Exhausted at 4; half is 2: Tired
local rested = operator("Tel", "E", 2)      -- Tired at 2; half is 1: rested
local suggested = operator("Xel", "XL", 4)  -- listed, non-blocking: still half (2, Tired)
roster[#roster + 1], roster[#roster + 2], roster[#roster + 3], roster[#roster + 4] = hero, forced, rested, suggested
required = { H = true, C = true, E = true, XL = false }
for _, op in ipairs({ hero, forced, rested, suggested }) do mission_start(nil, op) end
eq(hero.effects.GE_OffDuty_Tired, 1, "required Spent operator goes in Tired"); eq(hero.effects.GE_OffDuty_Spent, nil, "no Spent effect")
eq(hero.effects[ACCURACY], 1, "required: Tired accuracy only"); eq(hero.effects[Game.FATIGUE], 7, "required: fatigue still +2 (capped)")
eq(hero.effects[Game.DEPLOYED], 2, "required: marker records the tier they went in at")
eq(forced.effects.GE_OffDuty_Tired, 1, "required Exhausted operator goes in Tired"); eq(forced.effects[Game.FATIGUE], 6, "required: +2")
eq(rested.effects.GE_OffDuty_Tired, nil, "required Tired operator goes in rested"); eq(rested.effects[ACCURACY], nil, "no accuracy loss")
eq(suggested.effects.GE_OffDuty_Tired, 1, "non-blocking listing is still required"); eq(suggested.effects.GE_OffDuty_Exhausted, nil, "not Exhausted")
assert(table.concat(logs, "\n"):find("Hawks | fatigue 6 -> 7 | required: tier from half fatigue (3)", 1, true), "required logged")
required = {}

-- At mission load the roster can't be read yet: processing waits for it.
local unreadable = 2
local roster_ids = g.roster_ids
g.roster_ids = function(...)
    if unreadable > 0 then unreadable = unreadable - 1; return {} end
    return roster_ids(...)
end
local late = operator("Tel-Rea", "V", 2)
roster[#roster + 1] = late
mission_start(nil, late)
eq(late.effects[Game.FATIGUE], 4, "processed once the roster answers")
eq(late.effects.GE_OffDuty_Tired, 1, "late: tier applied")
unreadable = 99
local never = operator("Luco2", "L2", 1)
roster[#roster + 1] = never
mission_start(nil, never)
eq(never.effects[Game.FATIGUE], 1, "roster never readable: untouched")
assert(logs[#logs]:find("not ready after 34 tries", 1, true), logs[#logs])
g.roster_ids = roster_ids

-- A six-operator squad deploys while the mission loads. Each readiness check walks every object in the
-- game (FindAllOf), so one check serves the whole squad, retried on its own schedule, and the world
-- context it found is the one processing uses.
local queued = {}
local run_now = ctx.actions.schedule_after
ctx.actions.schedule_after = function(_, _, _, callback) queued[#queued + 1] = callback end
local function step()
    local callbacks = queued
    queued = {}
    for _, callback in ipairs(callbacks) do callback() end
end
local checks, contexts = 0, 0
local mission_actor, world_context = g.mission_actor, g.world_context
g.mission_actor = function() checks = checks + 1; return {} end
g.world_context = function() contexts = contexts + 1; return {} end
mission_ready = false
local squad = {}
for index = 1, 6 do
    squad[index] = operator("Squad" .. index, "SQ" .. index, 0)
    roster[#roster + 1] = squad[index]
end
for _, op in ipairs(squad) do mission_start(nil, op) end
eq(checks, 1, "six operators at mission load: one check")
eq(#queued, 1, "one retry scheduled for the squad")
step(); step()
eq(checks, 3, "one check per retry")
eq(squad[1].effects[Game.FATIGUE], 0, "not processed before the mission is ready")
mission_ready = true
contexts = 0
step()
for _, op in ipairs(squad) do eq(op.effects[Game.FATIGUE], 2, op.name .. " processed once ready") end
eq(contexts, 1, "processing reuses the check's world context")
eq(#queued, 0, "nothing left scheduled")
assert(logs[#logs]:find("Squad6 | fatigue 0 -> 2 | rested (ready after 4 tries)", 1, true), logs[#logs])
-- The next mission's squad starts a check of its own.
local next_op = operator("Next", "NX", 0)
roster[#roster + 1] = next_op
mission_start(nil, next_op)
eq(next_op.effects[Game.FATIGUE], 2, "a later mission start is checked again")
ctx.actions.schedule_after = run_now
g.mission_actor, g.world_context = mission_actor, world_context

-- A second call in the same turn changes nothing.
mission_start(nil, kabb)
eq(kabb.effects[Game.FATIGUE], 6, "no double gain"); eq(kabb.effects[ACCURACY], 2, "no double penalty")

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
eq(restored.effects[ACCURACY], 4, "loaded save: accuracy re-applied for the tier")
assert(logs[#logs]:find("Mission resumed", 1, true), logs[#logs])
g.loading_from_save = function() return false end
-- An older save without the tier effect: fall back to the tier this mission started at (fatigue - gain).
local old = operator("Old", "O1", 6, { effects = { [Game.FATIGUE] = 6, [Game.DEPLOYED] = 1 }, from_save = true })
roster[#roster + 1] = old
mission_start(nil, old)
eq(old.effects.GE_OffDuty_Exhausted, 1, "old save: tier from fatigue before the mission (4)")
eq(old.effects[Game.FATIGUE], 6, "old save: no gain")
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
-- Hard recovers 1.5: 1 and a banked half point (GE_OffDuty_RestCredit), then 2.
end_turn()
eq(kabb.effects[Game.FATIGUE], 6, "deployed don't recover"); eq(kabb.effects[Game.DEPLOYED], 0, "marker cleared")
eq(benched.effects[Game.FATIGUE], 2, "benched recover 1 (Hard)"); eq(benched.effects[Game.REST_CREDIT], 2, "half point banked (2 quarters)")
eq(away.effects[Game.FATIGUE], 4, "away frozen")
eq(absent.effects[Game.FATIGUE], 2, "no hub actor: unchanged")
-- Next turn everyone sits out: the deployed recover too.
end_turn()
eq(kabb.effects[Game.FATIGUE], 5, "recovers the turn after (1, banks a half)"); eq(kabb.effects[Game.REST_CREDIT], 2, "Kabb banked")
eq(benched.effects[Game.FATIGUE], 0, "banked half + 1.5 = 2"); eq(benched.effects[Game.REST_CREDIT], 0, "bank spent")

-- Settings: Standard preset (recovery 2) and a custom gain.
settings = { preset = "standard", fatigue_per_mission = 3 }
local std = operator("Tel", "E", 3)
roster[#roster + 1] = std
mission_start(nil, std) -- 3 is Tired (2), not Exhausted (4)
eq(std.effects.GE_OffDuty_Tired, 1, "standard tier"); eq(std.effects[Game.FATIGUE], 6, "standard +3")
end_turn(); end_turn()
eq(std.effects[Game.FATIGUE], 4, "rest 2 per turn after the deployed turn")
roster_cap = 12 -- room for three squads: Standard recovers 1
end_turn()
eq(std.effects[Game.FATIGUE], 3, "recovery halves once the operator cap reaches 12")
assert(logs[#logs]:find("recovery 1 | operator cap 12", 1, true), logs[#logs])
roster_cap = 8
settings = { preset = "hard" }

-- AP loss: only the real PlayerTeam turn, only Exhausted/Spent, at their odds.
local real_random = math.random
local function team(path) return { full_name = "BlueprintGeneratedClass " .. path } end
local PLAYER = team(Game.PLAYER_TEAM)
local PRE_PLAYER = team("/Game/Game/GameData/Teams/WorldTeam_PrePlayer.WorldTeam_PrePlayer_C")
local spent = operator("BR-1", "B", 0, { effects = { GE_OffDuty_Spent = 1 } })
local exhausted = operator("Kabb2", "K2", 0, { effects = { GE_OffDuty_Exhausted = 1 } })
local enemy = operator("Trooper", "X", 0, { effects = { GE_OffDuty_Spent = 1 }, player = false })

math.random = function() return 0.10 end -- below Spent's 15%, at Exhausted's 10%
team_turn(spent, PRE_PLAYER)
eq(spent.effects[Game.LOSE_AP], nil, "WorldTeam_PrePlayer doesn't roll")
team_turn(spent, PLAYER)
eq(spent.effects[Game.LOSE_AP], 1, "Spent loses AP at 10% < 15%")
team_turn(exhausted, PLAYER)
eq(exhausted.effects[Game.LOSE_AP], nil, "Exhausted safe at 10% (needs < 10%)")
team_turn(enemy, PLAYER)
eq(enemy.effects[Game.LOSE_AP], nil, "non-player units never roll")
team_turn(tesh, PLAYER)
eq(tesh.effects[Game.LOSE_AP], nil, "Tired never loses AP")
settings = { ap_loss = false }
team_turn(spent, PLAYER)
eq(spent.effects[Game.LOSE_AP], 1, "AP loss off in settings")
math.random = real_random

-- Downed operators are logged on change (they keep some health; the tag marks them).
g.call = function(object, method, arg)
    if method == "GetOwner" then return object.owner end
    if method == "IsPlayerTeamMember" then return arg and arg.player == true end
    if method == "HasMatchingGameplayTag" then return object.downed == true end
end
local down = operator("Gizi", "Z", 0)
down.downed = true
team_turn(down, PLAYER)
assert(logs[#logs]:find("Squad | Gizi downed", 1, true), logs[#logs])
local before = #logs
team_turn(down, PLAYER)
assert(#logs == before or not logs[#logs]:find("Gizi", 1, true), "logged once while downed")
down.downed = false
team_turn(down, PLAYER)
assert(logs[#logs]:find("Squad | Gizi revived", 1, true), logs[#logs])

-- Penalties never touch injuries.
for _, op in ipairs(roster) do assert(op.effects.GE_Injured == nil, "no injuries added") end
print("fatigue ok")
