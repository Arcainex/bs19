local bookProp, opened = nil, false
local function closeBook()
    if not opened then return end
    opened = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    ClearPedSecondaryTask(PlayerPedId())
    if bookProp and DoesEntityExist(bookProp) then
        DetachEntity(bookProp, true, true)
        DeleteEntity(bookProp)
    end
    bookProp = nil
end
RegisterNUICallback('closeBook', function(_, cb)
    closeBook()
    cb({ ok = true })
end)
RegisterNetEvent('bs_books:client:open', function(bookName, dynamicDef)
    local def = dynamicDef or Config.Books[bookName]
    if not def then return end
    closeBook()
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    local model = GetHashKey(def.prop == 'map' and 'prop_tourist_map_01' or 'prop_novel_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if HasModelLoaded(model) then
        local pos = GetEntityCoords(ped)
        bookProp = CreateObject(model, pos.x, pos.y, pos.z, false, false, false)
        if bookProp and DoesEntityExist(bookProp) then
            if def.prop == 'map' then
                AttachEntityToEntity(bookProp, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
            else
                AttachEntityToEntity(bookProp, ped, GetPedBoneIndex(ped, 6286), 0.15, 0.03, -0.065, 0.0, 180.0, 90.0, true, true, false, true, 1, true)
            end
        end
        SetModelAsNoLongerNeeded(model)
    end
    RequestAnimDict('cellphone@')
    deadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded('cellphone@') and GetGameTimer() < deadline do Wait(0) end
    if HasAnimDictLoaded('cellphone@') then
        TaskPlayAnim(ped, 'cellphone@', 'cellphone_text_read_base', 2.0, -2.0, -1, 49, 0, false, false, false)
        RemoveAnimDict('cellphone@')
    end
    opened = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', book = bookName, title = def.title, pages = def.pages, size = def.size })
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeBook() end
end)
