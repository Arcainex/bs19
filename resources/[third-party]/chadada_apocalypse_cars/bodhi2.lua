-- bodhi2.lua - prop layout for the base-game "bodhi2" (Chadada Apocalypse Cars).
-- Positions and rotations are Chadada's. Creation and cleanup are handled by ap_core.lua.

ApocalypseCars.Register("bodhi2", "motor", {
    { -- prop2
        model = "prop_mb_crate_01a",
        off = { 0.0, -2.0, -0.18 }, rot = { 0.0, 0.0, -90.0 },
    },
    { -- prop3
        model = "hei_prop_cntrdoor_mph_l",
        off = { 1.0, -1.6, 0.0 }, rot = { 270.0, 80.0, 180.0 },
    },
    { -- prop4
        model = "hei_prop_cntrdoor_mph_r",
        off = { -1.0, -1.6, 0.0 }, rot = { 270.0, 280.0, 180.0 },
    },
    { -- prop6
        model = "prop_barrel_exp_01a",
        off = { 0.0, -0.75, 0.18 }, rot = { 0.0, 90.0, 180.0 },
    },
    { -- prop7
        model = "prop_hobo_seat_01",
        off = { 0.73, -1.5, -0.18 }, rot = { 0.0, 0.0, 90.0 },
    },
    { -- prop8
        model = "frag_plank_a",
        off = { 0.0, -1.3, 1.25 }, rot = { 90.0, 90.0, 0.0 },
    },
    { -- prop9
        model = "frag_plank_a",
        off = { 0.0, -0.68, 1.25 }, rot = { 90.0, 90.0, 0.0 },
    },
    { -- prop10
        model = "frag_plank_a",
        off = { 0.0, -1.93, 1.25 }, rot = { 90.0, 90.0, 0.0 },
    },
    { -- prop11
        model = "frag_plank_a",
        off = { 0.0, -2.56, 1.25 }, rot = { 90.0, 90.0, 0.0 },
    },
})
