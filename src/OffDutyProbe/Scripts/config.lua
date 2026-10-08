-- Off Duty Probe settings. Edit, then reload the mod (or restart the game).
return {
    -- Ctrl+Shift+T test target: case-insensitive substring of the operator's full
    -- name. Empty picks the first roster operator who is not Away.
    test_character_name = "",

    -- Next-mission effect applied by Ctrl+Shift+T. The game ships:
    --   GE_Lose_NextMission_RangedAccuracy  (AccuracyReduction +1 per stack)
    --   GE_Lose_NextMission_LoseMaxHealth   (MaxHealth -2 per stack)
    test_effect = "GE_Lose_NextMission_RangedAccuracy",

    -- Passed as PrimaryMagnitude. Whether this scales the modifier or the stack
    -- count is one of the things the probe is meant to find out.
    test_magnitude = 5,

    -- High-frequency hooks (roster tiles) log their first N calls, then every Nth.
    log_first_calls = 5,
    log_every_nth_call = 50,
}
