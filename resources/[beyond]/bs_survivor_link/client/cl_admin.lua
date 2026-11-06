-- F10 > Survivor Link helpers on the owner's client: god mode on the body, AI reset, state dump and a debug overlay.
local companion,overlay,invincible

local function entity(net)
    if not net then return end
    local p=NetworkGetEntityFromNetworkId(net)
    if p~=0 and DoesEntityExist(p)then return p end
end
RegisterNetEvent('bs:link:state',function(data)companion=data or nil end)
RegisterNetEvent('bs:link:adminDump',function(text)
    print('[Survivor Link] server state: '..tostring(text))
    local ped=companion and entity(companion.net)
    if ped then
        local hash=GetSelectedPedWeapon(ped)
        print(('[Survivor Link] client: health %d/%d owner %s control %s combat %s ragdoll %s weapon %s ammo %d'):format(
            GetEntityHealth(ped),GetEntityMaxHealth(ped),tostring(NetworkGetEntityOwner(ped)),tostring(NetworkHasControlOfEntity(ped)),
            tostring(IsPedInCombat(ped,0)),tostring(IsPedRagdoll(ped)),tostring(hash),GetAmmoInPedWeapon(ped,hash)))
    else print('[Survivor Link] client: companion body not streamed here') end
end)
RegisterNetEvent('bs:link:adminReset',function(net)
    local ped=entity(net)
    if ped and NetworkHasControlOfEntity(ped)then
        ClearPedTasksImmediately(ped);FreezeEntityPosition(ped,false)
        if BSLinkStealth and BSLinkStealth.Reset then BSLinkStealth.Reset()end
    end
end)
RegisterNetEvent('bs:link:adminOverlay',function()overlay=not overlay end)

local function text(s,x,y)
    SetTextFont(0);SetTextScale(0.0,0.30);SetTextColour(255,255,255,230);SetTextOutline()
    SetTextEntry('STRING');AddTextComponentString(s);DrawText(x,y)
end
CreateThread(function()
    while true do
        local delay=1000
        local ped=companion and entity(companion.net)
        if ped and NetworkHasControlOfEntity(ped)then
            -- God mode follows the server flag; only undo what we set.
            local want=companion.god==true
            if want~=(invincible==ped)then SetEntityInvincible(ped,want);invincible=want and ped or nil end
        end
        if overlay and companion then
            delay=0
            local l=companion.life or {}
            local w=companion.weapon
            local lines={
                ('SURVIVOR LINK  %s  #%s'):format(companion.name or '?',tostring(companion.id)),
                ('life %s  hp %s  order %s  stance %s'):format(tostring(l.status),ped and GetEntityHealth(ped)or '-',tostring(companion.command),tostring(companion.stance)),
                ('ammo use %s  weapon %s  rounds %s  rev %s'):format(tostring(companion.ammoMode),w and w.weapon or 'none',w and tostring(w.ammo)or '-',w and tostring(w.rev)or '-'),
                ('god %s  ignored %s  grab %s  owner %s  control %s'):format(tostring(companion.god==true),tostring(companion.zIgnore==true),
                    tostring(l.grabLeft or '-'),ped and tostring(NetworkGetEntityOwner(ped))or '-',ped and tostring(NetworkHasControlOfEntity(ped))or '-'),
                ('distance %s m  combat %s'):format(ped and ('%.1f'):format(#(GetEntityCoords(ped)-GetEntityCoords(PlayerPedId())))or '-',ped and tostring(IsPedInCombat(ped,0))or '-'),
            }
            DrawRect(0.135,0.335,0.25,0.115,0,0,0,150)
            for i,s in ipairs(lines)do text(s,0.015,0.282+(i-1)*0.021)end
        end
        Wait(delay)
    end
end)
