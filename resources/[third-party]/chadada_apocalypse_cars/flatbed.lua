-- flatbed.lua - prop layout for the base-game "flatbed" (Chadada Apocalypse Cars).
-- Positions and rotations are Chadada's. Creation and cleanup are handled by ap_core.lua.

ApocalypseCars.Register("flatbed", "motor", {
    { -- prop2
        model = "prop_container_03_ld",
        off = { 0.0, -2.4, 0.3 }, rot = { 0.0, 0.0, 0.0 }, collision = true,
    },
    { -- prop3
        model = "prop_chair_08",
        off = { 0.95, -2.4, 1.0 }, rot = { 0.0, 0.0, -90.0 },
    },
    { -- prop4
        model = "prop_chair_08",
        off = { 0.95, -3.4, 1.0 }, rot = { 0.0, 0.0, -90.0 },
    },
    { -- prop5
        model = "prop_chair_08",
        off = { 0.95, -4.4, 1.0 }, rot = { 0.0, 0.0, -90.0 },
    },
    { -- prop6
        model = "prop_chair_08",
        off = { 0.95, -1.4, 1.0 }, rot = { 0.0, 0.0, -90.0 },
    },
    { -- prop7
        model = "prop_chair_08",
        off = { 0.95, -2.4, 1.0 }, rot = { 0.0, 0.0, -90.0 },
    },
    { -- prop8
        model = "prop_chair_08",
        off = { -0.95, -1.4, 1.0 }, rot = { 0.0, 0.0, 90.0 },
    },
    { -- prop9
        model = "prop_chair_08",
        off = { -0.95, -2.4, 1.0 }, rot = { 0.0, 0.0, 90.0 },
    },
    { -- prop10
        model = "prop_chair_08",
        off = { -0.95, -3.4, 1.0 }, rot = { 0.0, 0.0, 90.0 },
    },
    { -- prop11
        model = "prop_chair_08",
        off = { -0.95, -4.4, 1.0 }, rot = { 0.0, 0.0, 90.0 },
    },
    { -- prop12
        model = "prop_chair_08",
        off = { -0.95, -0.4, 1.0 }, rot = { 0.0, 0.0, 90.0 },
    },
    { -- prop13
        model = "prop_chair_08",
        off = { 0.95, -0.4, 1.0 }, rot = { 0.0, 0.0, -90.0 },
    },
    { -- prop14
        model = "prop_ballistic_shield",
        off = { 0.0, 4.36, 0.2 }, rot = { 0.0, 0.0, 180.0 },
    },
    { -- prop15
        model = "prop_ballistic_shield",
        off = { 0.65, 4.35, 0.2 }, rot = { 0.0, 0.0, 180.0 },
    },
    { -- prop16
        model = "prop_ballistic_shield",
        off = { -0.65, 4.35, 0.2 }, rot = { 0.0, 0.0, 180.0 },
    },
})
