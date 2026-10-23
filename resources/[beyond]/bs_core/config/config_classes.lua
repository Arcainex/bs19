-- Playable classes. Add or remove freely: the character creator, skill module and spawn logic all read this table.

Config = Config or {}

Config.Classes = {
    survivor = {
        label       = 'Survivor',
        description = 'A generalist. Carries more, eats less, dies slower.',
        icon        = 'survivor',
        order       = 1,
        stats = {
            maxHealth       = 200,
            armorCap        = 100,
            staminaMult     = 1.00,
            carryWeight     = 45.0,
            meleeDamageMult = 1.00,
            hungerRate      = 0.85,
            thirstRate      = 0.85,
        },
        startingSkills = { survival = 1 },
        -- Origin is only a class: stats and starting skills, not a look. Clothing is appearance, chosen at the wardrobe NPC and saved with the character; it never arrives in the bag. The items below are supplies.
        startingItems  = {
            { item = 'bandage', amount = 2 },
            { item = 'water_bottle', amount = 1 },
            { item = 'canned_food', amount = 1 },
        },
    },

    hunter = {
        label       = 'Hunter',
        description = 'Trades durability for damage. Quieter, faster, deadlier.',
        icon        = 'hunter',
        order       = 2,
        stats = {
            maxHealth       = 175,
            armorCap        = 75,
            staminaMult     = 1.25,
            carryWeight     = 35.0,
            meleeDamageMult = 1.30,
            hungerRate      = 1.10,
            thirstRate      = 1.10,
        },
        startingSkills = { combat = 2 },
        startingItems  = {
            { item = 'hunting_knife', amount = 1 },
            { item = 'water_bottle', amount = 1 },
            -- Dressed for being outside for a long time.
        },
    },

    medic = {
        label       = 'Medic',
        description = 'Heals faster, revives others, makes medical supplies count.',
        icon        = 'medic',
        order       = 3,
        stats = {
            maxHealth       = 180,
            armorCap        = 90,
            staminaMult     = 1.00,
            carryWeight     = 40.0,
            meleeDamageMult = 0.90,
            hungerRate      = 0.95,
            thirstRate      = 0.95,
        },
        startingSkills = { medical = 2 },
        startingItems  = {
            { item = 'medkit', amount = 1 },
            { item = 'bandage', amount = 4 },
            -- The one piece of kit that is also part of the job.
        },
    },

    engineer = {
        label       = 'Engineer',
        description = 'Builds, repairs and crafts. Fortifications are cheaper. Better at coaxing a temporary fix to hold.',
        icon        = 'engineer',
        order       = 4,
        stats = {
            maxHealth       = 190,
            armorCap        = 110,
            staminaMult     = 0.90,
            carryWeight     = 55.0,
            meleeDamageMult = 1.05,
            hungerRate      = 1.00,
            thirstRate      = 1.00,
            -- Added onto bs_vehicles' tempFixSuccessChance (see vehicles:tempfix in bs_vehicles/server/sv_main.lua). Engineer is the closest fit to a mechanic; any class added later for that should carry this stat.
            tempFixBonus    = 0.20,
        },
        startingSkills = { crafting = 2 },
        startingItems  = {
            { item = 'toolbox', amount = 1 },
            { item = 'scrap_metal', amount = 5 },
        },
    },

    -- Mechanic: close to the Engineer but not the same. Engineers build (fortifications, crafted gear); Mechanics keep things running (vehicles, temporary fixes) and are lighter on their feet.
    -- Both get an easier needle game when jump-starting a dead fuel pump (Vehicles.Pumps.jump.classes).
    mechanic = {
        label       = 'Mechanic',
        description = 'Keeps things running. Better with vehicles, and can coax power out of a dead forecourt.',
        icon        = 'engineer',
        order       = 5,
        stats = {
            maxHealth       = 180,
            armorCap        = 95,
            staminaMult     = 1.00,
            carryWeight     = 48.0,
            meleeDamageMult = 1.00,
            hungerRate      = 1.00,
            thirstRate      = 1.00,
            -- Better than the Engineer here: a temporary fix on a car is the Mechanic's whole trade.
            tempFixBonus    = 0.30,
        },
        startingSkills = { crafting = 1 },
        startingItems  = {
            { item = 'toolbox', amount = 1 },
            { item = 'fuel_can', amount = 1 },
        },
    },
}

-- Returns the class table, falling back to the first configured class.
function Config.GetClass(id)
    if id and Config.Classes[id] then return Config.Classes[id], id end
    for key, class in pairs(Config.Classes) do return class, key end
end

function Config.ClassList()
    local out = {}
    for key, class in pairs(Config.Classes) do
        out[#out + 1] = {
            id = key,
            label = class.label,
            description = class.description,
            icon = class.icon,
            order = class.order or 99,
            stats = class.stats,
            skills = class.startingSkills,
            items = class.startingItems,
        }
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end
