-- bs_vip - config. VIP buys looks and comfort, never an edge: no damage, armour, speed, loot, XP, money, storage, queue skipping or teleports.
-- Three tiers, each a level. A perk has a `minTier`; a player gets it when their tier level is at least that.

Vip = {}

Vip.Settings = {
    -- false = VIP off for this server: everyone gets every perk and the Tebex hook is ignored.
    enabled       = true,
    statusCommand = 'vip',
    panelCommand  = 'bs_vippanel',
    panelKey      = 'F7',
    -- How often online VIPs are checked for an expired subscription, ms.
    expirySweepMs = 300000,
}

-- Server palette. Color pickers only offer these plus unlocked tier colors.
Vip.Palette = {
    { id = 'rust',     label = 'Rust',     hex = '#b7472a' },
    { id = 'copper',   label = 'Copper',   hex = '#e08c46' },
    { id = 'ash',      label = 'Ash',      hex = '#8f8b83' },
    { id = 'bone',     label = 'Bone',     hex = '#e6dcc6' },
    { id = 'charcoal', label = 'Charcoal', hex = '#4a4744' },
    { id = 'blood',    label = 'Blood',    hex = '#9e2222' },
}

-- Tiers. `level` is what perks compare against. `grantUnlocks` are given once when the tier is granted and never taken back.
Vip.Tiers = {
    supporter = {
        id = 'supporter', level = 1, label = 'Supporter', colour = '#7fd4a2',
        grantUnlocks = { { type = 'title', id = 'vip_supporter_title', label = 'Supporter' } },
    },
    patron = {
        id = 'patron', level = 2, label = 'Patron', colour = '#e0b341',
        grantUnlocks = { { type = 'title', id = 'vip_patron_title', label = 'Patron' } },
    },
    legend = {
        id = 'legend', level = 3, label = 'Legend', colour = '#d0643c',
        grantUnlocks = { { type = 'title', id = 'vip_legend_title', label = 'Legend' } },
    },
}

Vip.Order = { 'supporter', 'patron', 'legend' }

-- Perks. All cosmetic or convenience. Numbers here are read by the resource that applies them (through bs_vip exports).
Vip.Perks = {
    -- Tier 1
    tagStyle        = { minTier = 1, label = 'Name-tag style & colour' },
    chatBadge       = { minTier = 1, label = 'Chat badge & name colour' },
    plateText       = { minTier = 1, label = 'Custom plate text' },
    combatColours   = { minTier = 1, label = 'Health bar & hit marker colours' },
    -- Tier 2
    blipColour      = { minTier = 2, label = 'Squad map blip colour' },
    hudColour       = { minTier = 2, label = 'Squad HUD name colour' },
    emoteFavourites = { minTier = 2, label = 'Extra emote favourites', bonus = 10 },
    tailorOutfits   = { minTier = 2, label = 'Extra tailor outfit slots', bonus = 5 },
    tailorDiscount  = { minTier = 2, label = 'Tailor discount', pct = 15 },
    stashSkin       = { minTier = 2, label = 'Stash marker skin' },
    stashName       = { minTier = 2, label = 'Rename stashes' },
    killfeedStyle   = { minTier = 2, label = 'Kill feed & death screen style' },
    -- Tier 3
    exclusiveEmotes = { minTier = 3, label = 'Exclusive emotes & walks' },
    boosterSkins    = { minTier = 3, label = 'Drone & turret skins' },
    profileBanner   = { minTier = 3, label = 'Scoreboard banner' },
    appearanceChange = { minTier = 3, label = 'Free monthly appearance change' },
    extraCharacter  = { minTier = 3, label = 'Extra character slot', bonus = 1 },
}

-- Display order in the panel.
Vip.PerkOrder = {
    'tagStyle', 'chatBadge', 'plateText', 'combatColours',
    'blipColour', 'hudColour', 'emoteFavourites', 'tailorOutfits', 'tailorDiscount',
    'stashSkin', 'stashName', 'killfeedStyle',
    'exclusiveEmotes', 'boosterSkins', 'profileBanner', 'appearanceChange', 'extraCharacter',
}

-- Name-tag looks. 'default' = keep the faction look. The rest are CSS
-- classes in bs_factions/html/tags.html (tag--st-<id>).
Vip.TagStyles = {
    { id = 'default', label = 'Faction default' },
    { id = 'plain',   label = 'Plain' },
    { id = 'stencil', label = 'Stencil' },
    { id = 'glow',    label = 'Glow' },
    { id = 'chevron', label = 'Chevron' },
    { id = 'elite',   label = 'Elite' },
    { id = 'pulse',   label = 'Pulse' },
    { id = 'scan',    label = 'Scanline' },
}

-- GTA blip colour ids, limited to ones that sit near the palette.
Vip.BlipColours = {
    { id = 2,  label = 'Green (default)', hex = '#71cb71' },
    { id = 1,  label = 'Red',     hex = '#e03232' },
    { id = 17, label = 'Orange',  hex = '#f0a050' },
    { id = 5,  label = 'Yellow',  hex = '#eec64e' },
    { id = 4,  label = 'White',   hex = '#f0f0f0' },
    { id = 39, label = 'Grey',    hex = '#9b9b9b' },
    { id = 76, label = 'Dark red', hex = '#a01414' },
}

-- Owner-only marker shown over your own buried stash. Local prop, nobody
-- else sees it (stashes stay secret).
Vip.StashSkins = {
    { id = 'none',   label = 'None (text only)' },
    { id = 'cairn',  label = 'Stone cairn',  model = 'prop_rock_4_c' },
    { id = 'crate',  label = 'Old crate',    model = 'prop_box_wood02a' },
    { id = 'flag',   label = 'Marker cone',  model = 'prop_mp_cone_04' },
}

-- Booster skins. Drone skin = colour of the marks it draws. Turret skin =
-- tint on the sandbag base / gun. Both cosmetic, same stats.
Vip.DroneSkins = {
    { id = 'default', label = 'Standard', zombie = 1, loot = 5 },
    { id = 'ember',   label = 'Ember',    zombie = 17, loot = 46 },
    { id = 'ghost',   label = 'Ghost',    zombie = 4,  loot = 39 },
}
Vip.TurretSkins = {
    { id = 'default', label = 'Standard', tint = 0, gunTint = 0 },
    { id = 'desert',  label = 'Desert',   tint = 2, gunTint = 4 },
    { id = 'night',   label = 'Night',    tint = 7, gunTint = 1 },
    { id = 'gilded',  label = 'Gilded',   tint = 5, gunTint = 2 },
}

-- Config hooks only: the choice is stored and exposed through exports.bs_vip:GetCosmetic(src, key). Nothing draws them yet.
Vip.KillfeedStyles = { { id = 'default', label = 'Standard' }, { id = 'rust', label = 'Rust frame' }, { id = 'minimal', label = 'Minimal' } }
Vip.DeathStyles    = { { id = 'default', label = 'Standard' }, { id = 'ash', label = 'Ash fade' }, { id = 'static', label = 'Static' } }
Vip.Banners        = { { id = 'none', label = 'None' }, { id = 'wasteland', label = 'Wasteland' }, { id = 'ember', label = 'Ember' }, { id = 'redline', label = 'Redline' } }

-- Plate customiser. Checked after upper-casing; any listed word inside the
-- plate (spaces removed) refuses it.
Vip.Plate = {
    minLength = 1,
    maxLength = 8,
    cooldownSec = 60,
    blocklist = {
        'FUCK', 'SHIT', 'CUNT', 'NIGG', 'FAG', 'RAPE', 'NAZI', 'HITLER',
        'KKK', 'PENIS', 'DICK', 'COCK', 'PUSSY', 'SLUT', 'WHORE', 'BITCH',
        'ADMIN', 'STAFF', 'POLICE',
    },
}

-- Tebex. Off until set up - see server/sv_tebex.lua and docs/VIP.md.
Vip.Tebex = {
    enabled = false,
    command = 'tebex_grant',        -- server console only
    -- Optional: map Tebex package ids to tiers if you call the stub with a package id instead of a tier.
    packages = {
        -- ['1234567'] = { tier = 'supporter', days = 30 },
    },
}

function Vip.Get(id)
    if id == nil then return nil end
    local n = tonumber(id)
    if n then
        for _, t in pairs(Vip.Tiers) do if t.level == n then return t end end
        return nil
    end
    return Vip.Tiers[tostring(id):lower()]
end

function Vip.IsValid(id) return Vip.Get(id) ~= nil end

function Vip.LevelOf(id)
    local t = Vip.Get(id)
    return t and t.level or 0
end

function Vip.PerkAllowed(level, perk)
    local p = Vip.Perks[perk]
    return p ~= nil and (tonumber(level) or 0) >= p.minTier
end

-- Palette + tier colors up to `level`, as { [hex] = true }.
function Vip.AllowedColours(level)
    local out = {}
    for _, c in ipairs(Vip.Palette) do out[c.hex:lower()] = true end
    for _, t in pairs(Vip.Tiers) do
        if t.level <= (tonumber(level) or 0) then out[t.colour:lower()] = true end
    end
    return out
end

function Vip.FindById(list, id)
    for _, v in ipairs(list or {}) do if v.id == id then return v end end
    return nil
end

-- True while the server owner has switched the VIP system off (everyone counts as top tier).
function Vip.Disabled() return Vip.Settings.enabled == false end
