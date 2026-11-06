-- Apply a saved survivor only after its network entity and ownership are available.
local pending,applied={},{}
local function owned(net,charId)
    local ped=NetworkGetEntityFromNetworkId(net)
    if ped==0 or not DoesEntityExist(ped)then return nil end
    local state=Entity(ped).state.bsSurvivorLink
    if not state or state.owner~=GetPlayerServerId(PlayerId())or (charId and state.charId~=charId)then return nil end
    return ped
end
local function takeControl(ped,untilAt)
    while DoesEntityExist(ped)and not NetworkHasControlOfEntity(ped)and GetGameTimer()<untilAt do
        NetworkRequestControlOfEntity(ped);Wait(25)
    end
    return DoesEntityExist(ped)and NetworkHasControlOfEntity(ped)
end
RegisterNetEvent('bs:link:appearance',function(data)
    if type(data)~='table'or type(data.net)~='number'or type(data.token)~='number'then return end
    if applied[data.net]==data.token then TriggerServerEvent('bs:link:appearanceReady',data.net,data.token,true);return end
    if pending[data.net]==data.token then return end
    pending[data.net]=data.token
    CreateThread(function()
        local ok,reason=pcall(function()
            local deadline=GetGameTimer()+6000
            local ped=owned(data.net,data.charId)
            while not ped and GetGameTimer()<deadline do Wait(50);ped=owned(data.net,data.charId)end
            if not ped then error('The companion has not streamed in yet.')end
            if not takeControl(ped,GetGameTimer()+2500)then error('Could not obtain companion control.')end
            SetEntityVisible(ped,false,false)
            SetPedDefaultComponentVariation(ped)
            local appearanceOk=exports.bs_core:ApplyAppearanceTo(ped,data.appearance or {})
            if appearanceOk==false then error('Saved face could not be applied.')end
            if data.outfit then exports.bs_core:ApplyOutfit(ped,data.outfit)end
            local life=data.life or {}
            SetEntityMaxHealth(ped,math.max(200,life.health or 200))
            SetEntityHealth(ped,life.status=='alive'and math.max(101,life.health or 200)or 105)
            SetPedArmour(ped,life.armour or 0)
            SetPedDropsWeaponsWhenDead(ped,false);SetPedCanRagdoll(ped,true)
            SetPedCombatAbility(ped,1);SetPedAccuracy(ped,data.accuracy or 30)
            -- Stance logic decides when to fight, so the ped itself never panics or flees.
            SetPedCombatAttributes(ped,5,true);SetPedCombatAttributes(ped,46,true);SetPedCombatAttributes(ped,58,true)
            SetPedFleeAttributes(ped,0,false)
            SetPedRelationshipGroupHash(ped,GetPedRelationshipGroupHash(PlayerPedId()))
            SetBlockingOfNonTemporaryEvents(ped,true)
            RemoveAllPedWeapons(ped,true)
            if data.weapon then GiveWeaponToPed(ped,joaat(data.weapon.weapon),data.weapon.ammo or 0,false,true)end
            SetEntityVisible(ped,true,false)
            applied[data.net]=data.token
            if life.status~='alive'then TriggerEvent('bs:link:fallen',data.net,life)end
        end)
        pending[data.net]=nil
        TriggerServerEvent('bs:link:appearanceReady',data.net,data.token,ok,ok and nil or tostring(reason))
    end)
end)
RegisterNetEvent('bs:link:health',function(net,token,health)
    if applied[net]~=token or type(health)~='number'or health~=health then return end
    CreateThread(function()
        local ped=owned(net)
        if ped and takeControl(ped,GetGameTimer()+1000)then SetEntityHealth(ped,math.max(0,math.min(GetEntityMaxHealth(ped),health)))end
    end)
end)
RegisterNetEvent('bs:link:damage',function(net,damage)
    if type(damage)~='number'or damage~=damage or damage<=0 then return end
    CreateThread(function()
        local ped=owned(net)
        if ped and takeControl(ped,GetGameTimer()+1000)then ApplyDamageToPed(ped,math.min(250,damage),false)end
    end)
end)
RegisterNetEvent('bs:link:state',function(data)
    if data==false then pending,applied={},{}end
end)
