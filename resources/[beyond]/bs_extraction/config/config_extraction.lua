-- BeyondSurvival - bs_extraction config: the danger zone. Placed inside bs_zombies' 'los_santos' spawn zone on purpose, so gunfire reported to 'bs:world:noise' already turns into heat via bs_director without extra wiring.

Extraction = {}

Extraction.Zones = {
    {
        id     = 'downtown_ls',
        label  = 'Downtown Danger Zone',
        coords = vector3(200.0, -900.0, 30.0),
        radius = 350.0,

        -- Reach one of these and hold still to get out clean.
        extractionPoints = {
            { id = 'rooftop_a', label = 'Rooftop Extract',  coords = vector3(230.0, -920.0, 31.0), radius = 6.0, dwellSeconds = 25 },
            { id = 'metro_b',   label = 'Metro Extract',    coords = vector3(150.0, -880.0, 29.5), radius = 6.0, dwellSeconds = 25 },
        },

        -- Paid on a clean extraction. Separate from bs_core's Config.Rewards on purpose: this is zone risk pay, not a per-action reward.
        rewardMoney = 300,
        rewardXp    = 150,
    },
}

Extraction.Settings = {
    -- How long a player-vs-player kill inside a zone marks the killer Rogue.
    rogueWindowSeconds     = 300,
    -- Bounty paid to whoever kills a Rogue while they are still flagged.
    bountyBase             = 500,
    bountyPerKill          = 250,
    -- Same attacker can't farm the same victim for bounty/rogue flags back to back.
    killCooldownSeconds    = 20,

    -- Zone membership is reported by the client every couple of seconds and sanity-checked against travel speed. Anything faster than this between two reports is ignored as spoofed.
    zoneUpdateIntervalMs   = 2000,
    maxPlausibleSpeed      = 100.0,   -- m/s; a jet is ~150+, a sprinting ped ~7

    -- Aim-and-hold, not the ALT-dot system: an extraction point is a place to stand.
    dwellCancelDistance    = 8.0,
}

function Extraction.ZoneFor(x, y, z)
    for _, zone in ipairs(Extraction.Zones) do
        local dx, dy = zone.coords.x - x, zone.coords.y - y
        if (dx * dx + dy * dy) <= (zone.radius * zone.radius) then
            return zone
        end
    end
    return nil
end

function Extraction.GetZone(id)
    for _, zone in ipairs(Extraction.Zones) do
        if zone.id == id then return zone end
    end
    return nil
end
