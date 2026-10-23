-- Boosters: single-use personal buffs, 3 slots, PvE only.
-- Deployables and the riot shield live in bs_gadgets. Item defs are in bs_inventory/config/config_items.lua (category 'booster').

Boosters = {}

Boosters.Slots = 3
-- 6/7/8: hotbar owns 1-5, gadgets 9/0.
Boosters.DefaultKeys = { '6', '7', '8' }
Boosters.Command = 'bs_booster%d'   -- key set name; changed so new default keys apply to existing players
Boosters.MetaKey = 'boosters'       -- character metadata: { [1]=item, [2]=item, [3]=item }
Boosters.UseDelayMs = 600           -- server-side anti-spam between any two uses

-- item name -> behaviour. cooldown is per TYPE, in seconds.
Boosters.Types = {
    booster_adrenaline = {
        kind = 'adrenaline', label = 'Adrenaline', cooldown = 180,
        duration = 15, speed = 1.25,
    },
    -- Steadier aim: recoil and sway multiplied by `steady` (bs_skills reads it).
    booster_focus = {
        kind = 'focus', label = 'Focus', cooldown = 180,
        duration = 45, steady = 0.55,
    },
    -- Painkiller drip: small heal every tick, stops if you die.
    booster_regen = {
        kind = 'regen', label = 'Painkiller drip', cooldown = 200,
        duration = 40, tickMs = 2000, healPerTick = 3,
    },
    -- Thick skin: a share of every zombie bite is ignored.
    booster_fortify = {
        kind = 'fortify', label = 'Fortify', cooldown = 220,
        duration = 40, reduce = 0.35,
    },
}

function Boosters.IsBooster(item) return Boosters.Types[item] ~= nil end
