-- Off Duty Probe settings. Edit, then reload the mod (or restart the game).
return {
    -- Ctrl+Shift+T test target: case-insensitive substring of the operator's full
    -- name. Empty picks the first roster operator who is not Away.
    test_character_name = "",

    -- Next-mission effect applied by Ctrl+Shift+T. The game ships:
    --   GE_Lose_NextMission_RangedAccuracy  (AccuracyReduction +1 per stack)
    --   GE_Lose_NextMission_LoseMaxHealth   (MaxHealth -2 per stack)
    test_effect = "GE_Lose_NextMission_RangedAccuracy",

    -- Passed as PrimaryMagnitude. Runs 2-3: it doesn't scale the shipped
    -- accuracy effect; each Ctrl+Shift+T adds one -5% stack.
    test_magnitude = 1,

    -- AP-loss experiment: chance per turn to lose 1 AP for operators carrying a tier's penalty.
    -- test_ap_loss_chance overrides both while testing (set nil for the real odds).
    ap_loss_chance = { Exhausted = 0.05, Spent = 0.10 },
    test_ap_loss_chance = 0.5,
    -- Applied after this delay so the game's own turn-start AP refill happens first.
    ap_loss_delay_ms = 250,

    -- The probe's own gameplay: tiers at mission start, in-mission debuff text, AP-loss rolls. Off with
    -- the real mod (src/OffDuty) installed, which does all three; keep the probe for its keys and dumps.
    auto_tier = false,
    -- Draw the Zzz icon on the in-mission debuff: true, false (keep the game's Lethargy icon), or
    -- "compare" (Tired keeps the brush type, Exhausted/Spent set it to None; see which shows the Zzz).
    status_icon = true,

    -- Ctrl+Shift+F sets these exact counts (case-insensitive name substring); press again to reset
    -- to them. Defaults cover each tier (1 Tired, 3 Exhausted, 5/7 Spent) and 0/1/2 injuries.
    -- Never more than 2 injuries: a third kills the operator. The probe caps it at 2 regardless.
    test_squad = {
        -- Simtest squad (tools/simtest.py): clean baseline, no fatigue and no injuries. Press Ctrl+Shift+F in the
        -- sandbox Den, then `campaign baseline` saves it as the baseline every run resets to.
        { name = "Tesh", fatigue = 0, injuries = 0 },
        { name = "Kabb", fatigue = 0, injuries = 0 },
        { name = "Luco", fatigue = 0, injuries = 0 },
        { name = "Jae", fatigue = 0, injuries = 0 },
    },

    -- High-frequency hooks (roster tiles) log their first N calls, then every Nth.
    log_first_calls = 5,
    log_every_nth_call = 50,
}
