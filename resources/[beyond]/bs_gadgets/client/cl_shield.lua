-- Riot shield gadget. Idea and model choice from "Shield Mod" by winject (gta5-mods.com/scripts/shield-mod); this is a Lua rewrite of the behaviour, not the mod.
-- Networked prop with collision on the left forearm: bullets stop on it, bites from the front are soaked (bs_zombies asks via bs_boosters).

local G = GadgetCl
local S = { prop = nil, hp = 0, cfg = nil, slot = nil, item = nil }

-- Shield parked: Gadgets.Types.booster_shield.enabled = false
local function shieldEnabled()
    local t = Gadgets and Gadgets.Types and Gadgets.Types.booster_shield
    return not (t and t.enabled == false)
end

-- PERF: hashed once at load; friendly() and the hold loop run every frame.
local H_UNARMED, H_PISTOL, H_MELEE = joaat('WEAPON_UNARMED'), joaat('GROUP_PISTOL'), joaat('GROUP_MELEE')
local H_STUNGUN, H_THROWN = joaat('GROUP_STUNGUN'), joaat('GROUP_THROWN')

local function friendly(ped)
    local w = GetSelectedPedWeapon(ped)
    if w == H_UNARMED then return true end
    local g = GetWeapontypeGroup(w)
    return g == H_PISTOL or g == H_MELEE or g == H_STUNGUN or g == H_THROWN
end

local function clear()
    local prop, cfg = S.prop, S.cfg
    S.prop, S.cfg, S.slot = nil, nil, nil
    if cfg and cfg.pose then StopAnimTask(PlayerPedId(), cfg.pose.dict, cfg.pose.name, 2.0) end
    if prop and DoesEntityExist(prop) then DetachEntity(prop, true, false) end
    G.Delete(prop)
end

-- Local teardown + tell the server. why: 'stow' | 'twohand' | 'broke'
local function stow(why)
    if not S.prop then return end
    local hp = S.hp
    clear()
    if why == 'broke' then
        TriggerServerEvent('bs:gadgets:ended', 'shield', 'broke')
    else
        TriggerServerEvent('bs:gadgets:shieldStow', hp, why)
    end
end

-- Key handler hook: the same slot key while the shield is up puts it away.
function G.ShieldToggle(index)
    if not S.prop then return false end
    local e = G.Loadout[tostring(index)]
    -- The slot empties once the shield is out, so any key of an empty or shield slot stows it.
    if e and e.kind ~= 'shield' then return false end
    stow('stow')
    return true
end

local function wear(amount)
    if S.hp <= 0 then return end
    S.hp = S.hp - amount
    if S.hp <= 0 then S.hp = 0; stow('broke') end
end

function G.ShieldStart(t, item, hp)
    if t and t.enabled == false then
        G.Notify(L('gad.not_yet'), 'error')
        TriggerServerEvent('bs:gadgets:cancel')
        return
    end
    clear()
    local ped = PlayerPedId()
    if not friendly(ped) then SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true) end
    local c = GetEntityCoords(ped)
    local obj, netId = G.SpawnNet(t.model, c)
    if not obj and t.fallback then obj, netId = G.SpawnNet(t.fallback, c) end
    if not obj then
        G.Notify(L('gad.shield_fail'), 'error')
        TriggerServerEvent('bs:gadgets:shieldStow', hp or t.durability, 'stow')
        return
    end
    local o, r = t.offset, t.rot
    -- Collision on so bullets stop on the shield; not against our own ped.
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, t.bone or 61163), o.x, o.y, o.z, r.x, r.y, r.z,
        true, false, true, true, 1, true)
    SetEntityCollision(obj, true, true)
    SetEntityNoCollisionEntity(obj, ped, true)
    SetEntityInvincible(obj, true)   -- durability is ours, not the prop's
    S.prop, S.hp, S.cfg, S.item = obj, tonumber(hp) or t.durability, t, item
    G.Stops.shield = function() clear() end   -- the stop handler clears this after each use
    TriggerServerEvent('bs:gadgets:attach', 'shield', { netId })
    G.Notify(L('gad.shield_up', { pct = math.floor(S.hp / t.durability * 100 + 0.5) }))

    local pose = t.pose
    if pose and not G.LoadDict(pose.dict) then pose = nil end

    CreateThread(function()
        while S.prop == obj do
            local p = PlayerPedId()
            if IsEntityDead(p) or G.Downed() then clear(); break end
            if IsPedInAnyVehicle(p, true) then stow('stow'); break end
            if not friendly(p) then stow('twohand'); break end
            if not DoesEntityExist(obj) or not IsEntityAttachedToEntity(obj, p) then stow('stow'); break end
            if pose and GetSelectedPedWeapon(p) == H_UNARMED or pose and GetWeapontypeGroup(GetSelectedPedWeapon(p)) == H_MELEE then
                if not IsEntityPlayingAnim(p, pose.dict, pose.name, 3) then
                    TaskPlayAnim(p, pose.dict, pose.name, 4.0, -4.0, -1, 49, 0.0, false, false, false)
                end
            end
            SetEntityNoCollisionEntity(obj, p, false)
            -- No climbing or vaulting with a shield on your arm.
            DisableControlAction(0, 22, true)
            Wait(0)
        end
    end)
end

-- Bullets that hit the prop wear it down.
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not S.prop then return end
    if args[1] == S.prop then wear(S.cfg.bulletHp or 4) end
end)

-- Who is biting: the nearest live non-player ped.
local function biteFromFront()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local best, bestD = nil, 3.0
    for _, p in ipairs(GetGamePool('CPed')) do
        if p ~= ped and not IsPedAPlayer(p) and not IsEntityDead(p) then
            local d = #(GetEntityCoords(p) - pos)
            if d < bestD then best, bestD = p, d end
        end
    end
    if not best then return false end
    local dir = GetEntityCoords(best) - pos
    local fwd = GetEntityForwardVector(ped)
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    if len < 0.01 then return true end
    local dot = (fwd.x * dir.x + fwd.y * dir.y) / len
    return dot >= math.cos(math.rad((S.cfg.arc or 120) / 2))
end

-- Returns what gets through.
exports('ShieldAbsorb', function(amount)
    amount = tonumber(amount) or 0
    if not shieldEnabled() then return amount end  -- Parked: absorbs 0, everything gets through.
    if not S.prop or S.hp <= 0 or amount <= 0 or not biteFromFront() then return amount end
    local soaked = math.min(S.hp, amount)
    wear(soaked)
    return amount - soaked
end)
exports('HasShield', function() return S.prop ~= nil and S.hp > 0 end)
exports('StowShield', function() stow('stow') end)

RegisterNetEvent('bs:medical:died', function() clear() end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clear() end
end)
