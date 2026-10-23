-- bs_traders - clothing shop. Appearance only: nothing bought has stats, weight or an inventory row; it is stored in the outfit metadata bs_core already keeps (cl_outfit.lua).
-- The client enumerates drawables (it needs the ped). The server owns price, VIP, level and visibility and re-checks them on every purchase.

Wardrobe = {}

Wardrobe.Settings = {
    -- Default price for everything in the shop. Categories can override it below, and `Rules` can override a specific drawable.
    basePrice = 120,

    -- Charged per garment changed, counted when the player confirms. Browsing is free.
    chargePerChange = true,

    -- Camera distance from the player and look height while the shop is open.
    camDistance = 2.2,
    camHeight   = 0.25,

    -- Camera framing per body part. `dist` is how far back, `z` is how far up the body to look (relative to the feet).
    -- `side` shifts the framing left so the character sits clear of the UI.
    focus = {
        head  = { dist = 1.05, z = 0.62, side = 0.18 },
        torso = { dist = 1.70, z = 0.30, side = 0.22 },
        legs  = { dist = 1.85, z = -0.25, side = 0.22 },
        feet  = { dist = 1.50, z = -0.70, side = 0.20 },
        full  = { dist = 2.45, z = 0.05, side = 0.26 },
    },
}

-- Poses for checking clipping (sleeves only show problems with arms raised). `flag` 49 = looped + upper-body.
-- Each pose is a list of candidates because DoesAnimDictExist can say yes for a dict without the clip; the first clip that resolves wins.
Wardrobe.Poses = {
    {
        id = 'handsup', label = 'Hands up',
        anims = {
            { dict = 'random@mugging3',        clip = 'handsup_standing_base' },
            { dict = 'missminuteman_1ig_2',    clip = 'handsup_base' },
        },
    },
    {
        id = 'aim', label = 'Shoulder',
        -- Rifle-at-shoulder pose: pulls the sleeve across the chest, where bulky jackets bunch.
        anims = {
            { dict = 'rcmjosh4',               clip = 'josh_leadout_cop2' },
            { dict = 'random@mugging3',        clip = 'handsup_standing_base' },
        },
    },
    {
        id = 'reach', label = 'Reach',
        anims = {
            { dict = 'amb@world_human_hang_out_street@male_c@idle_a', clip = 'idle_b' },
            { dict = 'anim@mp_player_intmenu@key_fob@',               clip = 'fob_click' },
        },
    },
}

-- Categories.
-- `kind`  'component' (body mesh) or 'prop' (attached).
-- `index` freemode component/prop id.
-- `arms`  true only for the top, which drags component 3 along so a jacket is never worn over a bare torso.
-- Face, hair and decals are left out on purpose: they are character identity.
Wardrobe.Categories = {
    { id = 'top',        label = 'Jackets & Shirts', kind = 'component', index = 11, arms = true, price = 180, focus = 'torso' },
    -- Arms as a pickable category. Component 3 is a separate mesh from component 11 with no mapping between them, so by default the arms follow the top (AUTO). Picking an arm drawable here switches that category out of AUTO.
    { id = 'arms',       label = 'Arms & Sleeves',   kind = 'component', index = 3,  price = 0, focus = 'torso' },
    { id = 'undershirt', label = 'Undershirts',      kind = 'component', index = 8,  focus = 'torso' },
    { id = 'legs',       label = 'Trousers',         kind = 'component', index = 4,  price = 140, focus = 'legs' },
    { id = 'shoes',      label = 'Boots & Shoes',    kind = 'component', index = 6,  price = 130, focus = 'feet' },
    -- No 'packs' category: component 5 is the parachute slot on freemode models, not a backpack. A real backpack needs a streamed addon prop. See PARACHUTE_COMPONENT in bs_core/client/cl_outfit.lua.
    { id = 'armour',     label = 'Vests',            kind = 'component', index = 9,  price = 260, focus = 'torso' },
    { id = 'accessory',  label = 'Accessories',      kind = 'component', index = 7,  focus = 'torso' },
    { id = 'mask',       label = 'Masks',            kind = 'component', index = 1,  price = 150, focus = 'head' },
    { id = 'hat',        label = 'Hats',             kind = 'prop',      index = 0,  focus = 'head' },
    { id = 'glasses',    label = 'Glasses',          kind = 'prop',      index = 1,  focus = 'head' },
    { id = 'ear',        label = 'Earpieces',        kind = 'prop',      index = 2,  focus = 'head' },
    { id = 'watch',      label = 'Watches',          kind = 'prop',      index = 6,  focus = 'torso' },
    { id = 'bracelet',   label = 'Bracelets',        kind = 'prop',      index = 7,  focus = 'torso' },
}

Wardrobe.ByCategory = {}
for _, c in ipairs(Wardrobe.Categories) do Wardrobe.ByCategory[c.id] = c end

-- What 'nothing' looks like. Props use -1 (ClearPedProp). Components have no empty state, and drawable 0 of component 11 is a T-shirt, so each model needs a drawable that is the bare body: 15 for the top and 15 for the arms on both freemode models.
-- Categories with no entry here get no Remove row (no safe bare value for trousers or shoes).
-- Kept in config so addon bodies can change them.
Wardrobe.Bare = {
    -- component id 11; the arms move with it, see Wardrobe.BareArms below
    top        = { male = 15, female = 15 },
    undershirt = { male = 15, female = 15 },
    accessory  = { male = 0,  female = 0  },
    armour     = { male = 0,  female = 0  },
    mask       = { male = 0,  female = 0  },
    arms       = { male = 15, female = 15 },
}

--- The arms that go with a bare torso. Same numbers as Wardrobe.Bare.arms; kept
--- separate so a server can make "no top" pick different sleeves to "arms set
--- to none" without the two fighting.
Wardrobe.BareArms = { male = 15, female = 15 }

--- The drawable that means "nothing" for this category on this model, or nil
--- when the category has no such state and must not offer a Remove row.
--- Props are not listed: every prop's empty state is -1, universally.
function Wardrobe.BareFor(categoryId, gender)
    local cat = Wardrobe.ByCategory[categoryId]
    if not cat then return nil end
    if cat.kind == 'prop' then return -1 end

    local entry = Wardrobe.Bare[categoryId]
    if not entry then return nil end
    return entry[gender == 'female' and 'female' or 'male']
end

-- Outfits. Buying a garment buys the right to wear it permanently, per character, so wearing a saved outfit later is free.
-- Ownership and saved outfits live in the database (see sv_wardrobe.lua), not in outfit metadata, since they are a growing list.
Wardrobe.Outfits = {
    maxPerCharacter = 12,   -- enough to be useful, few enough to stay a list
    nameMaxLength   = 24,
}

-- The gate. A rule matches a category, and optionally a drawable or inclusive range; the most specific match wins.
--   hidden = true    not listed, and the server refuses it.
--   vip = true       visible but refused unless bs_vip (IsVIP) says so.
--   minLevel = n     visible but refused below that character level.
-- Left nearly empty on purpose, these are examples of the shape.
Wardrobe.Rules = {
    -- { category = 'top',    drawable = 49,          vip = true },
    -- { category = 'armour', from = 0, to = 30,      minLevel = 15 },
    -- { category = 'hat',    drawable = 122,         hidden = true },
}

--- The rule that applies to one drawable, or nil. Most specific wins.
function Wardrobe.RuleFor(categoryId, drawable)
    local best, bestScore = nil, -1

    for _, rule in ipairs(Wardrobe.Rules) do
        if rule.category == categoryId then
            local score = -1

            if rule.drawable and rule.drawable == drawable then
                score = 3
            elseif rule.from and rule.to and drawable >= rule.from and drawable <= rule.to then
                score = 2
            elseif not rule.drawable and not rule.from then
                score = 1
            end

            if score > bestScore then best, bestScore = rule, score end
        end
    end

    return best
end

--- What one garment costs. Category override, then the base price; a rule may
--- override both.
function Wardrobe.PriceFor(categoryId, drawable)
    local rule = Wardrobe.RuleFor(categoryId, drawable)
    if rule and tonumber(rule.price) then return math.floor(tonumber(rule.price)) end

    local cat = Wardrobe.ByCategory[categoryId]
    if cat and tonumber(cat.price) then return math.floor(tonumber(cat.price)) end

    return math.floor(Wardrobe.Settings.basePrice)
end

-- May this player wear this, and if not, why not.
-- Returns true, or false, reason, tag where tag is 'hidden' | 'vip' | 'level'.
-- `info` is { vip = boolean, level = number }, gathered by the caller because only the server can be trusted on VIP.
function Wardrobe.Allowed(categoryId, drawable, info)
    local rule = Wardrobe.RuleFor(categoryId, drawable)
    if not rule then return true end

    if rule.hidden then return false, 'not for sale', 'hidden' end

    if rule.vip and not (info and info.vip) then
        return false, 'VIP only', 'vip'
    end

    if rule.minLevel and (not info or (info.level or 0) < rule.minLevel) then
        return false, ('level %d'):format(rule.minLevel), 'level'
    end

    return true
end
