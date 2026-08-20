-- Reference configuration for Claude to adapt to the actual WICK codebase.
-- Do not assume this exact ModuleScript location is correct.

return {
    Encounter = {
        CandleCount = 8,
        MeleeTriggerRadius = 6.0,
        MajorAttackRepeatLimit = 2,

        AttackDowntime = {
            Early = { Min = 2.2, Max = 3.0 }, -- 0-2 candles
            Mid   = { Min = 1.9, Max = 2.6 }, -- 3-5
            Late  = { Min = 1.6, Max = 2.3 }, -- 6-7
        },

        Weights = {
            Dripstone = 34,
            BoulderBurst = 32,
            SummonGnawers = 22,
        },
    },

    Visual = {
        OrbitStoneCount = 6,
        BasePowerColor = Color3.fromRGB(138, 92, 240),
        HoverAmplitude = 0.18,
        HoverFrequency = 0.55,
        CapePanelCount = 5,
    },

    Animations = {
        Idle = {
            Id = "rbxassetid://REPLACE_ME",
            Duration = 6.00,
            Loop = true,
        },
        Dripstone = {
            Id = "rbxassetid://REPLACE_ME",
            Duration = 2.60,
            ImpactTime = 1.62,
        },
        BoulderBurst = {
            Id = "rbxassetid://REPLACE_ME",
            Duration = 2.45,
            ConjureTime = 0.18,
            Fire1Time = 0.92,
            Fire2Time = 1.16,
        },
        SummonGnawers = {
            Id = "rbxassetid://REPLACE_ME",
            Duration = 3.05,
            SpawnTime = 1.42,
        },
        MeleeDoubleRake = {
            Id = "rbxassetid://REPLACE_ME",
            Duration = 1.55,
            Hit1Time = 0.56,
            Hit2Time = 0.82,
        },
        CandleRecoil = {
            Id = "rbxassetid://REPLACE_ME",
            Duration = 1.70,
        },
        Banish = {
            Id = "rbxassetid://REPLACE_ME",
            Duration = 3.40,
            ReliefSwapTime = 3.20,
        },
    },

    Attacks = {
        Dripstone = {
            SoloCount = 4,
            DuoCount = 5,
            PartyCount = 6,
            Radius = 2.9,
            Damage = 38,
        },

        BoulderBurst = {
            Count = 2,
            ShotSpacing = 0.24,
            Radius = 2.0,
            Speed = 42,
            MaxDistance = 50,
            Damage = 34,
            PredictionSeconds = 0.16,
            Knockback = 28,
        },

        SummonGnawers = {
            SoloCount = 1,
            DuoCount = 2,
            PartyCount = 2,
            ActiveCap = 4,
        },

        Melee = {
            TriggerRadius = 6.0,
            DamagePerSwipe = 21,
            KnockbackSecondSwipe = 24,
            MaxRootLunge = 1.4,
        },
    },

    Audio = {
        SoundGroupName = "BossSFX",
        RollOffMode = Enum.RollOffMode.InverseTapered,
    },

    Remotes = {
        FXEventName = "UnlittiusFX",
    },
}
