-- bs_fighting - shared maths so client and server agree on damage and costs.

Fighting.Math = {}

function Fighting.StyleIds()
    local out = {}
    for id in pairs(Fighting.Styles) do out[#out + 1] = id end
    table.sort(out, function(a, b) return (Fighting.Styles[a].order or 99) < (Fighting.Styles[b].order or 99) end)
    return out
end

function Fighting.IsAdvanced(styleId)
    local s = Fighting.Styles[styleId]
    return s and not s.basic and not s.free
end

-- Weapon class from a weapon name hash table built once.
local classByHash
function Fighting.ClassOfHash(hash)
    if not classByHash then
        classByHash = {}
        for name, c in pairs(Fighting.WeaponClassOf) do classByHash[GetHashKey(name)] = c end
    end
    return classByHash[hash]
end

-- The move a style throws for a slot ('light' n, 'heavy', 'kick', 'stomp', 'takedown') with a weapon class.
function Fighting.MoveFor(styleId, class, slot, n)
    local st = Fighting.Styles[styleId] or Fighting.Styles.untrained
    local wc = Fighting.WeaponClasses[class or 'fists']
    if class and class ~= 'fists' and wc and wc[slot] then
        -- the Grappler keeps his shove as a kick even with a weapon in hand
        if slot == 'kick' and st.kick == 'shove' then return 'shove' end
        return wc[slot]
    end
    if slot == 'light' then return st.chain[((n or 1) - 1) % #st.chain + 1] end
    if slot == 'heavy' then return st.heavy end
    if slot == 'kick' then return st.kick end
    if slot == 'stomp' then return 'stomp' end
    if slot == 'takedown' then return 'takedown' end
    return nil
end

-- has(flag) -> bool, injected so client (HasFlag) and server (HasPerk) share this.
function Fighting.Math.Damage(moveId, styleId, level, has, combo, counter, charge, tired)
    local S = Fighting.Settings
    local move = Fighting.Moves[moveId]
    local style = Fighting.Styles[styleId] or Fighting.Styles.untrained
    if not move then return 0 end
    local dmg = (move.dmg or 0) * (style.dmg or 1.0)
    dmg = dmg * (1.0 + math.max(0, level or 0) * (S.damagePerLevel or 0))
    if moveId:sub(1, 3) == 'kn_' and style.knife then dmg = dmg * style.knife end
    if charge then dmg = dmg * (0.6 + 0.4 * math.max(0, math.min(1, charge))) end
    if counter then
        dmg = dmg * (S.counterBonus or 1.5)
        if has and has('box_counter') then dmg = dmg * 1.5 end
    end
    if tired then dmg = dmg * (S.tiredDamage or 0.55) end
    dmg = dmg * (1.0 + math.min(4, math.max(0, (combo or 1) - 1)) * 0.05)
    return math.floor(dmg + 0.5)
end

function Fighting.Math.Stamina(kind, styleId, level, has, charge)
    local S = Fighting.Settings
    local style = Fighting.Styles[styleId] or Fighting.Styles.untrained
    local base = S.staminaLight
    if kind == 'heavy' then base = S.staminaHeavy * (0.5 + 0.5 * math.max(0, math.min(1, charge or 1)))
    elseif kind == 'kick' then base = S.staminaKick
    elseif kind == 'stomp' then base = S.staminaStomp end
    return base * (style.stamina or 1.0) * math.max(0.5, 1.0 - math.max(0, level or 0) * (S.staminaPerLevel or 0))
end
