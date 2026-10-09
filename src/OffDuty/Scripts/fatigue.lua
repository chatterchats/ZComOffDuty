-- The fatigue loop. Fatigue lives in the save as GE_OffDuty_Fatigue stacks on each operator.
--
--   Mission start (ApplyNextMissionEffectsToCharacter, once per deployed operator, also on a tactical save
--   load), processed once the mission is ready:
--     new mission: apply the tier their current fatigue puts them in (accuracy stacks + tier effect),
--       mark them deployed this turn (GE_OffDuty_Deployed, saved), add the mission's fatigue (capped);
--     loaded save (marker present): fatigue is already counted; restore the tier only.
--   Strategy turn end (EndStrategyTurn): every roster operator who isn't away and wasn't deployed
--     recovers; the deployed marker is cleared. Away operators (operations) are frozen.
--   Player turn start (OnTeamTurnStarted with PlayerTeam): Exhausted/Spent operators roll to lose 1 AP.
-- Only roster operators take part (guest units such as Rex aren't on the roster).
local Rules = require("rules")
local Game = require("game")

local M = {}

local MISSION_START = "/Script/Bruno.BrunoGameStatics:ApplyNextMissionEffectsToCharacter"
local END_TURN = "/Script/Bruno.BrunoStrategyTurnManager:EndStrategyTurn"
local TEAM_TURN = "/Script/BitReactorGame.BitReactorAbilitySystemComponent:OnTeamTurnStarted"
local AP_LOSS_DELAY_MS = 250 -- after the game's own turn-start AP refill

function M.new(ctx)
    local g, log, actions, settings = ctx.game, ctx.log, ctx.actions, ctx.settings
    local self = {}

    local function current_settings() return Rules.normalise(settings()) end

    local function tier_effect_present(asc)
        for _, tier in ipairs(Rules.TIERS) do
            if g.effect_count(asc, g.effect_class(tier.effect)) > 0 then return tier end
        end
        return nil
    end

    -- Mission start ---------------------------------------------------------------------------------

    -- The hook fires while the mission map loads: before the roster can be read, and on a tactical save
    -- load while the save is still restoring effects (both verified; touching effects then crashed the
    -- game, and "mission ready" came too early). So: note whether this is a save load, wait until the
    -- roster is readable, the mission is ready and no save is loading, then process. A loaded save never
    -- adds fatigue (the mission was counted when it started); it only restores the tier.
    local READY_RETRY_MS = { 250, 500, 1000, 2000, 4000, 8000, 16000 }
    local SAVE_SETTLE_MS = 500
    local process_mission_start

    local function on_mission_start(_, character)
        local actor = g.unwrap(character)
        if not g.is_actor(actor) then return end
        local name = g.character_name(actor) or g.full_name(actor)
        local id = g.character_id(actor)
        if not id then log("WARNING: mission start | %s | no character ID; skipped", name); return end
        local attempt, settled = 0, false
        local from_save = g.was_loaded_from_save(actor) or g.loading_from_save()
        local function try()
            attempt = attempt + 1
            local loading = g.loading_from_save()
            from_save = from_save or loading or g.was_loaded_from_save(actor)
            local wco = not loading and g.world_context() or nil
            local ids = wco and g.roster_ids(wco) or {}
            if loading or next(ids) == nil or not g.mission_ready(g.mission_actor()) then
                local delay = READY_RETRY_MS[attempt]
                if delay then
                    actions:schedule_after("mission_start", delay, g.safe("mission start retry", try), actor)
                else
                    log("WARNING: mission start | %s | mission or roster not ready after %d tries; no fatigue this mission",
                        name, attempt)
                end
                return
            end
            if not ids[id] then
                log("Mission start | %s | not on the roster (guest unit); no fatigue", name)
                return
            end
            if from_save and not settled then
                settled = true -- one more beat after the load reports done
                actions:schedule_after("mission_start", SAVE_SETTLE_MS, g.safe("mission start settle", try), actor)
                return
            end
            process_mission_start(actor, name, attempt, from_save)
        end
        try()
    end

    local function apply_tier(asc, tier, name)
        -- apply_effect returns nil on success, so no `x and apply() or "error"` shortcuts here.
        local accuracy, effect = g.load_class(Game.ACCURACY), g.effect_class(tier.effect)
        local err
        if not accuracy then err = "accuracy effect unavailable"
        else
            local missing = tier.accuracy_stacks - g.effect_count(asc, accuracy)
            if missing > 0 then err = g.apply_effect(asc, accuracy, missing) end
        end
        if not err then
            if not effect then err = tier.effect .. " unavailable"
            elseif g.effect_count(asc, effect) < 1 then err = g.apply_effect(asc, effect, 1) end
        end
        -- Game state is authoritative: re-read what actually applied.
        local summary = string.format("%s (%s %d, accuracy stacks %d)", tier.name, tier.effect,
            g.effect_count(asc, effect), g.effect_count(asc, accuracy))
        if err or g.effect_count(asc, effect) < 1 then
            log("WARNING: mission start | %s | %s penalty not applied | %s", name, tier.name, tostring(err))
        end
        return summary
    end

    function process_mission_start(actor, name, attempt, from_save)
        if not g.valid(actor) then return end
        local asc = g.asc(actor)
        local fatigue_class, deployed_class = g.effect_class(Game.FATIGUE), g.effect_class(Game.DEPLOYED)
        if not asc or not fatigue_class or not deployed_class then
            log("WARNING: mission start | %s | ability system or Off Duty effects unavailable (is OffDuty_P installed?)", name)
            return
        end
        local s = current_settings()
        local cap = Rules.preset(s.preset).cap
        local fatigue = g.effect_count(asc, fatigue_class)
        if fatigue > cap then
            fatigue = g.set_effect_count(asc, fatigue_class, cap)
            log("WARNING: mission start | %s | fatigue was above the cap; clamped to %d", name, fatigue)
        end
        local ready_note = attempt > 1 and string.format(" (ready after %d tries)", attempt) or ""

        local marked = g.effect_count(asc, deployed_class) > 0
        if from_save or marked then
            -- A tactical save loaded (or a second call): fatigue is already counted. Restore the tier: the
            -- saved tier effect if the save kept it, else the tier this mission started at.
            if from_save and not marked then
                log("Mission resumed | %s | save has no deployed marker (saved before Off Duty counted it); no gain", name)
            end
            local tier = tier_effect_present(asc)
                or Rules.tier(math.max(fatigue - s.gain, 0), s.preset)
            local summary = tier and apply_tier(asc, tier, name) or "rested"
            log("Mission resumed | %s | fatigue %d unchanged | %s%s", name, fatigue, summary, ready_note)
            return
        end

        actions:cancel_group("ap_loss", "mission start") -- a new mission session
        local tier = Rules.tier(fatigue, s.preset)
        local summary = tier and apply_tier(asc, tier, name) or "rested"
        g.apply_effect(asc, deployed_class, 1)
        if g.effect_count(asc, deployed_class) < 1 then
            log("WARNING: mission start | %s | deployed marker not applied; turn-end recovery may count them", name)
        end
        local after = g.set_effect_count(asc, fatigue_class, Rules.after_mission(fatigue, s))
        log("Mission start | %s | fatigue %d -> %d | %s%s", name, fatigue, after, summary, ready_note)
        if ctx.on_mission_start then ctx.on_mission_start() end
    end

    -- Strategy turn end -----------------------------------------------------------------------------

    local function on_end_turn()
        actions:cancel_group("ap_loss", "strategy turn end")
        local wco = g.world_context()
        local fatigue_class, deployed_class = g.effect_class(Game.FATIGUE), g.effect_class(Game.DEPLOYED)
        if not wco or not fatigue_class or not deployed_class then
            log("WARNING: turn end | world or Off Duty effects unavailable; no recovery this turn")
            return
        end
        local s = current_settings()
        local rested, frozen, deployed, missing = 0, 0, 0, 0
        for _, member in ipairs(g.roster(wco)) do
            local asc = member.actor and g.asc(member.actor)
            if not asc then
                missing = missing + 1
            elseif g.effect_count(asc, deployed_class) > 0 then
                g.set_effect_count(asc, deployed_class, 0)
                deployed = deployed + 1
            elseif member.away then
                frozen = frozen + 1
            else
                local before = math.min(g.effect_count(asc, fatigue_class), Rules.preset(s.preset).cap)
                if before > 0 then
                    g.set_effect_count(asc, fatigue_class, Rules.after_rest(before, s))
                    rested = rested + 1
                end
            end
        end
        log("Turn end | %d recovered, %d deployed this turn, %d away (frozen), %d without a hub actor",
            rested, deployed, frozen, missing)
    end

    -- Player turn start: AP loss ----------------------------------------------------------------------

    local function on_team_turn(context, team)
        if not current_settings().ap_loss then return end
        local team_name = g.full_name(g.unwrap(team))
        -- Exact class: WorldTeam_PrePlayer also starts a turn each round, before the AP refill.
        if not team_name:find(Game.PLAYER_TEAM, 1, true) then return end
        local asc = g.unwrap(context)
        if not g.valid(asc) then return end
        local owner = (g.call(asc, "GetOwner"))
        if not g.valid(owner) or (g.call(g.unit_statics(), "IsPlayerTeamMember", owner)) ~= true then return end
        local tier = tier_effect_present(asc)
        if not tier or tier.ap_loss <= 0 or math.random() >= tier.ap_loss then return end
        local name = g.character_name(owner) or g.full_name(owner)
        actions:schedule_after("ap_loss", AP_LOSS_DELAY_MS, function()
            local class = g.effect_class(Game.LOSE_AP)
            local err = "GE_OffDuty_LoseAP unavailable"
            if class then err = g.apply_effect(asc, class, 1) end
            log("AP loss | %s | %s%s", name, tier.name, err and (" | " .. err) or "")
        end, asc, owner)
    end

    function self:install()
        pcall(function() math.randomseed(os.time()) end)
        for path, callback in pairs({ [MISSION_START] = on_mission_start, [END_TURN] = on_end_turn,
                                      [TEAM_TURN] = on_team_turn }) do
            local wrapped = g.safe(path:match(":(.+)$"), callback)
            local ok, err = pcall(function() ctx.runtime:register_hook(path, function() end, wrapped) end)
            log("%s | %s%s", ok and "Hooked" or "ERROR: hook failed", path, ok and "" or (" | " .. tostring(err)))
        end
    end

    return self
end

return M
