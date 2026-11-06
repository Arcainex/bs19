-- bs_inventory - Dark Zone items (bs_darkzone): found in DZ crates or given by DZ ranks, never sold.
-- Merged like config_items_jobs.lua: an id that already exists is left alone.

local add = {
    dz_flare      = { label = 'Signal flare', category = 'tool', weight = 0.3, w = 1, h = 2, stack = 5, usable = false, value = 60 },
    dz_intel      = { label = 'Field intel', category = 'junk', weight = 0.1, w = 1, h = 1, stack = 10, usable = false, value = 120 },
    dz_sample     = { label = 'Infected tissue sample', category = 'trophy', weight = 0.2, w = 1, h = 1, stack = 10, usable = false, value = 300 },

    -- Named weapons: fitted parts out of the box, tint and a little more damage while held (bs_darkzone client).
    dz_pdw_warden = { label = 'Warden PDW', category = 'weapon', weight = 2.6, w = 3, h = 2, stack = 1, usable = true, value = 4200,
                      data = { weapon = 'WEAPON_COMBATPDW', spawnRounds = 30,
                               defaultMeta = { attachments = { muzzle = 'suppressor', scope = 'scope', grip = 'grip', light = 'flashlight', mag = 'extmag' } } } },
    dz_rifle_revenant = { label = 'Revenant rifle', category = 'weapon', weight = 4.0, w = 4, h = 2, stack = 1, usable = true, value = 6500,
                      data = { weapon = 'WEAPON_MILITARYRIFLE', spawnRounds = 30,
                               defaultMeta = { attachments = { muzzle = 'suppressor', scope = 'scope', light = 'flashlight', mag = 'extmag' } } } },
    dz_shotgun_breacher = { label = 'Breacher shotgun', category = 'weapon', weight = 3.8, w = 4, h = 2, stack = 1, usable = true, value = 5800,
                      data = { weapon = 'WEAPON_HEAVYSHOTGUN', spawnRounds = 6,
                               defaultMeta = { attachments = { muzzle = 'suppressor', grip = 'grip', light = 'flashlight', mag = 'extmag' } } } },

    -- Boosters and gadget (behaviour in bs_boosters / bs_gadgets config).
    booster_dz_overdrive = { label = 'Overdrive', category = 'booster', weight = 0.1, w = 1, h = 1, stack = 5, usable = false, value = 380, data = { booster = true } },
    booster_dz_ironhide  = { label = 'Ironhide', category = 'booster', weight = 0.2, w = 1, h = 1, stack = 5, usable = false, value = 420, data = { booster = true } },
    booster_dz_sentry    = { label = 'Sentry turret', category = 'gadget', weight = 3.0, w = 2, h = 2, stack = 1, usable = false, value = 900, data = { gadget = true } },
}

for id, def in pairs(add) do
    if Items.Definitions[id] == nil then Items.Definitions[id] = def end
end

-- Rounds for the named weapons
local function ammoFor(id, weapon)
    local d = Items.Definitions[id]
    if d and d.data and type(d.data.ammoFor) == 'table' then
        for _, w in ipairs(d.data.ammoFor) do if w == weapon then return end end
        table.insert(d.data.ammoFor, weapon)
    end
end
ammoFor('ammo_pistol', 'WEAPON_COMBATPDW')
ammoFor('ammo_rifle', 'WEAPON_MILITARYRIFLE')
ammoFor('ammo_shotgun', 'WEAPON_HEAVYSHOTGUN')
