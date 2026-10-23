-- dloader.lua - prop layout for the base-game "dloader" (Chadada Apocalypse Cars).
-- Positions and rotations are Chadada's. Creation and cleanup are handled by ap_core.lua.

ApocalypseCars.Register("dloader", "motor", {
    { -- prop1
        model = "prop_wall_light_15a",
        off = { 0.0, -0.35, 1.3 }, rot = { 0.0, 0.0, 180.0 },
    },
    { -- prop2
        model = "prop_box_wood02a",
        off = { 0.0, -1.7, 0.98 }, rot = { 0.0, 0.0, -90.0 }, softPin = false,
    },
    { -- prop3
        model = "prop_container_door_mb_l",
        off = { 1.0, -1.6, 0.5 }, rot = { 270.0, 80.0, 180.0 }, softPin = false,
    },
    { -- prop4
        model = "prop_container_door_mb_r",
        off = { -1.0, -1.6, 0.5 }, rot = { 270.0, 280.0, 180.0 }, softPin = false,
    },
    { -- prop6
        model = "prop_box_wood02a",
        off = { 0.0, -1.7, 0.35 }, rot = { 0.0, 0.0, -90.0 }, softPin = false,
    },
    { -- prop7
        model = "prop_jerrycan_01a",
        off = { 0.61, -1.5, 0.35 }, rot = { 0.0, 0.0, 90.0 }, softPin = false,
    },
    { -- prop8
        model = "frag_plank_a",
        off = { 0.0, -1.3, 1.75 }, rot = { 90.0, 90.0, 0.0 }, softPin = false,
    },
    { -- prop9
        model = "frag_plank_a",
        off = { 0.0, -0.68, 1.75 }, rot = { 90.0, 90.0, 0.0 }, softPin = false,
    },
    { -- prop10
        model = "frag_plank_a",
        off = { 0.0, -1.93, 1.75 }, rot = { 90.0, 90.0, 0.0 }, softPin = false,
    },
    { -- prop11
        model = "frag_plank_a",
        off = { 0.0, -2.56, 1.75 }, rot = { 90.0, 90.0, 0.0 }, softPin = false,
    },
    { -- prop12
        model = "prop_railsleepers01",
        off = { 0.0, -2.8, 1.65 }, rot = { 90.0, 90.0, 0.0 }, softPin = false,
    },
    { -- prop13
        model = "prop_railsleepers01",
        off = { 0.0, -0.27, 1.65 }, rot = { 90.0, 90.0, 0.0 }, softPin = false,
    },
})
