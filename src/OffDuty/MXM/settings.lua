return {
    id      = "OffDuty",
    name    = "Off Duty",
    version = "1.1.2",
    description = "Operator fatigue and recovery. Changes apply from the next mission or strategy turn.",

    settings = {
        { type = "header", name = "Fatigue" },

        { key = "preset", type = "choice",
          name = "Preset", default = "standard",
          choices = {
              { value = "easy", label = "Easy: recover 3 per turn off duty" },
              { value = "standard", label = "Standard: recover 2 per turn off duty" },
              { value = "hard", label = "Hard: recover 1.5 per turn off duty" },
          },
          desc = "How fast operators recover off duty; halved once Crew Quarters has room for 12+ operators. Every preset: Tired at 2 fatigue, Exhausted at 4, Spent at 6; fatigue caps at 7." },

        { key = "fatigue_per_mission", type = "number",
          name = "Fatigue per mission", default = 2,
          min = 0, max = 4, step = 1,
          desc = "Added to every operator who deploys." },

        { key = "start_cycle", type = "number",
          name = "Fatigue starts after cycle", default = 5,
          min = 1, max = 20, step = 1,
          desc = "Until this cycle is over, missions add no fatigue and no penalties apply, while the early roster is too small to rotate." },

        { type = "header", name = "Penalties" },

        { key = "ap_loss", type = "bool",
          name = "Exhausted and Spent can lose AP", default = true,
          desc = "10% (Exhausted) or 15% (Spent) chance each turn to lose 1 AP." },
    },
}
