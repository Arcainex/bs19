-- Companion weapon on the ped, ammo reports back to the server, and the ammo use order.
BSLinkGear={}
local companion,lastReport,lastRev,applied
-- Firing pattern per ammo order: single shots, short bursts, full auto.
local PATTERN={conserve=0x5D60E4E0,normal=0xD6FF6D61,free=0xC6EE6B4C}
local RANGE={conserve=0,normal=1,free=2}
local SHOOT={conserve=40,normal=100,free=160}
-- How far he looks for a fight, relative to the stance range.
local REACH={conserve=.6,normal=1.0,free=1.5}

local function entity(net)
    if not net then return end
    local p=NetworkGetEntityFromNetworkId(net)
    if p~=0 and DoesEntityExist(p)then return p end
end
local function control(ped,ms)
    local untilAt=GetGameTimer()+(ms or 1000)
    while DoesEntityExist(ped)and not NetworkHasControlOfEntity(ped)and GetGameTimer()<untilAt do NetworkRequestControlOfEntity(ped);Wait(25)end
    return DoesEntityExist(ped)and NetworkHasControlOfEntity(ped)
end
local function mode()return companion and companion.ammoMode or 'normal'end
function BSLinkGear.Reach()return REACH[mode()]or 1.0 end

local function applyMode(ped)
    local m=mode()
    SetPedFiringPattern(ped,PATTERN[m]or PATTERN.normal)
    SetPedCombatRange(ped,RANGE[m]or 1)
    SetPedShootRate(ped,SHOOT[m]or 100)
end
local function equip(ped,w)
    RemoveAllPedWeapons(ped,true)
    if w then
        local hash=joaat(w.weapon)
        GiveWeaponToPed(ped,hash,math.max(0,w.ammo or 0),false,true)
        SetPedAmmo(ped,hash,math.max(0,w.ammo or 0))
        SetCurrentPedWeapon(ped,hash,true)
    end
    applyMode(ped)
    lastRev,lastReport=w and w.rev,w and w.ammo
end

RegisterNetEvent('bs:link:weapon',function(net,token,w)
    CreateThread(function()
        local ped=entity(net)
        if not ped or not control(ped,1500)then return end
        local status=companion and companion.life and companion.life.status
        if status and status~='alive'then RemoveAllPedWeapons(ped,true);return end
        equip(ped,w)
        applied=net
    end)
end)
RegisterNetEvent('bs:link:state',function(data)
    companion=data or nil
    if not companion then applied,lastRev,lastReport=nil,nil,nil end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local w=companion and companion.weapon
        if companion and companion.life and companion.life.status=='alive'then
            local ped=entity(companion.net)
            if ped and NetworkHasControlOfEntity(ped)then
                -- First time this body is ours (after a spawn or switch) the mode still needs setting.
                if applied~=companion.net then applyMode(ped);applied=companion.net end
                if w and not w.melee then
                    local hash=joaat(w.weapon)
                    if HasPedGotWeapon(ped,hash,false)then
                        local left=GetAmmoInPedWeapon(ped,hash)
                        if lastRev~=w.rev then lastRev,lastReport=w.rev,w.ammo end
                        if left<(lastReport or w.ammo)then
                            lastReport=left
                            TriggerServerEvent('bs:link:ammo',left,w.rev)
                        end
                    end
                end
            end
        end
    end
end)
