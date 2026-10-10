return {
    id      = "OffDuty",
    name    = "Off Duty",
    version = "0.1.0",
    description = "Operator fatigue and recovery. Changes apply from the next mission or strategy turn.",

    settings = {
        { type = "header", name = "Fatigue" },

        { key = "preset", type = "choice",
          name = "Preset", default = "hard",
          choices = {
              { value = "hard", label = "Hard: tiers at 1 / 3 / 5, cap 7" },
              { value = "standard", label = "Standard: tiers at 2 / 4 / 6, cap 6" },
          },
          desc = "Fatigue points at which an operator becomes Tired, Exhausted and Spent." },

        { key = "fatigue_per_mission", type = "number",
          name = "Fatigue per mission", default = 2,
          min = 0, max = 4, step = 1,
          desc = "Added to every operator who deploys." },

        { key = "recovery_per_turn", type = "number",
          name = "Recovery per turn off duty", default = 1,
          min = 0, max = 3, step = 1,
          desc = "Removed each strategy turn an operator sits out. Operators away on an operation don't change." },

        { type = "header", name = "Penalties" },

        { key = "ap_loss", type = "bool",
          name = "Exhausted and Spent can lose AP", default = true,
          desc = "5% (Exhausted) or 10% (Spent) chance each turn to lose 1 AP." },

        { type = "header", name = "Display" },

        { key = "status_ui", type = "bool",
          name = "Show fatigue as an in-mission debuff", default = true,
          desc = "Name, description and Zzz icon in the Inspect panel and beside the health bar. The penalties apply either way." },
    },
}
