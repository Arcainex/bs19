-- Alpha-Z: 4 simultaneous carried weapon props, synced through bs_inventory.
-- Slot 1: large melee/back; 2: long gun/back; 3: left belt; 4: right belt.
-- Non-networked LOCAL props: every client renders nearby players from state bags.
-- Weapon in hand is not duplicated on the body.
local displays = {} -- [serverId] = {ped = entity, slots = {[index] = {entity=, model=}}}
local UNARMED = GetHashKey('WEAPON_UNARMED')

local anchors = {
    [1] = {bone=24816, x=0.18, y=-0.16, z=0.06, rx=4.0, ry=175.0, rz=2.0}, -- melee across back
    [2] = {bone=24816, x=-0.18, y=-0.17, z=-0.03, rx=0.0, ry=173.0, rz=12.0}, -- rifle across back
    [3] = {bone=58271, x=0.06, y=0.01, z=-0.10, rx=8.0, ry=185.0, rz=92.0}, -- left thigh
    [4] = {bone=51826, x=-0.06, y=0.01, z=-0.10, rx=8.0, ry=175.0, rz=-92.0}, -- right thigh
}

local function release(entry)
    if entry and entry.entity and DoesEntityExist(entry.entity) then
        DetachEntity(entry.entity, true, true)
        DeleteEntity(entry.entity)
    end
end
local function clear(sid)
    local display = displays[sid]
    if not display then return end
    for _, entry in pairs(display.slots) do release(entry) end
    displays[sid] = nil
end
local function modelOf(weaponName)
    if type(weaponName) ~= 'string' or weaponName:sub(1,7) ~= 'WEAPON_' then return nil end
    local hash = GetHashKey(weaponName)
    local model = GetWeapontypeModel(hash)
    if not model or model == 0 or not IsModelInCdimage(model) then return nil end
    return model, hash
end
local function createProp(ped, model, position)
    if not HasModelLoaded(model) then
        RequestModel(model)
        local deadline = GetGameTimer() + 800
        while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    end
    if not HasModelLoaded(model) then return nil end
    local coords = GetEntityCoords(ped)
    local prop = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not prop or prop == 0 then return nil end
    SetEntityCollision(prop, false, false)
    SetEntityCompletelyDisableCollision(prop, false, false)
    FreezeEntityPosition(prop, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, position.bone),
        position.x, position.y, position.z, position.rx, position.ry, position.rz,
        false, false, false, false, 2, true)
    return prop
end

local function updatePlayer(pid)
    local sid = GetPlayerServerId(pid)
    local ped = GetPlayerPed(pid)
    if not sid or sid <= 0 or ped == 0 or not DoesEntityExist(ped) then
        if sid and sid > 0 then clear(sid) end
        return
    end
    local state = Player(sid).state.alphaZCarriedWeapons or {}
    if type(state) ~= 'table' then state = {} end
    local display = displays[sid]
    if display and display.ped ~= ped then clear(sid); display = nil end
    if not display then
        display = {ped=ped, slots={}}
        displays[sid] = display
    end
    local _, held = GetCurrentPedWeapon(ped, true)
    for i=1,4 do
        local weapon = state[tostring(i)]
        local model, hash = modelOf(weapon)
        -- Hide model while drawn, and clear all models if player dies.
        if hash == held or IsEntityDead(ped) then model = nil end
        local entry = display.slots[i]
        if entry and (entry.model ~= model or not DoesEntityExist(entry.entity)) then
            release(entry)
            display.slots[i] = nil
            entry = nil
        end
        if model and not entry then
            local obj = createProp(ped, model, anchors[i])
            if obj then display.slots[i] = {entity=obj, model=model} end
        end
    end
end

CreateThread(function()
    while true do
        Wait(850)
        local seen = {}
        for _, pid in ipairs(GetActivePlayers()) do
            local sid = GetPlayerServerId(pid)
            seen[sid] = true
            updatePlayer(pid)
        end
        for sid in pairs(displays) do
            if not seen[sid] then clear(sid) end
        end
    end
end)

AddEventHandler('bs:hook:player:unloaded', function()
    local sid = GetPlayerServerId(PlayerId())
    if sid then clear(sid) end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for sid in pairs(displays) do clear(sid) end
end)
