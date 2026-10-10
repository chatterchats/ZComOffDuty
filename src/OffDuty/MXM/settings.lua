return {
    id      = "OffDuty",
    name    = "Off Duty",
    version = "1.0.0",
    description = "Operator fatigue and recovery. Changes apply from the next mission or strategy turn.",

    settings = {
        { type = "header", name = "Fatigue" },

        { key = "preset", type = "choice",
          name = "Preset", default = "standard",
          choices = {
              { value = "easy", label = "Easy: tiers at 3 / 5 / 7" },
              { value = "standard", label = "Standard: tiers at 2 / 4 / 6" },
              { value = "hard", label = "Hard: tiers at 1 / 3 / 5" },
          },
          desc = "Fatigue points at which an operator becomes Tired, Exhausted and Spent. Fatigue caps at 7." },

        { key = "fatigue_per_mission", type = "number",
          name = "Fatigue per mission", default = 2,
          min = 0, max = 4, step = 1,
          desc = "Added to every operator who deploys." },

        { key = "recovery_per_turn", type = "number",
          name = "Recovery per turn off duty", default = 1,
          min = 0, max = 3, step = 1,
          desc = "Removed each strategy turn an operator sits out. Operators away on an operation don't change." },

        { key = "start_cycle", type = "number",
          name = "Fatigue starts at cycle", default = 5,
          min = 1, max = 20, step = 1,
          desc = "Before this cycle missions add no fatigue and no penalties apply, while the early roster is too small to rotate." },

        { type = "header", name = "Penalties" },

        { key = "ap_loss", type = "bool",
          name = "Exhausted and Spent can lose AP", default = true,
          desc = "10% (Exhausted) or 15% (Spent) chance each turn to lose 1 AP." },
    },
}
