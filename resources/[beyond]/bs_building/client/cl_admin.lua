-- bs_building staff panel (opened from F10). The server checks the ace on every call.

local open = false

RegisterNetEvent('bs:building:admin:open', function()
    CreateThread(function()
        local res = BSB.Await('build:admin:list', 8000)
        if not res or not res.ok then return end
        open = true
        TriggerEvent('bs:ui:opened', 'building')
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'admin', data = res })
    end)
end)

RegisterNUICallback('adminClose', function(_, cb)
    open = false
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('adminPieces', function(data, cb)
    CreateThread(function() cb(BSB.Await('build:admin:pieces', 8000, data.fac) or { ok = false }) end)
end)

RegisterNUICallback('adminAct', function(data, cb)
    CreateThread(function()
        local res = BSB.Await('build:admin:act', 8000, data.action, data.a, data.b)
        if res and res.ok and data.action ~= 'teleport' then
            res.list = BSB.Await('build:admin:list', 8000)
        end
        if data.action == 'teleport' and res and res.ok then
            open = false
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'adminHide' })
        end
        cb(res or { ok = false })
    end)
end)

-- /buildmodels: prints which model each piece really uses here and its size, to check fallbacks in game (F8)
RegisterCommand('buildmodels', function() CreateThread(function()
    for id, d in pairs(Building.Pieces) do
        local picked
        for _, m in ipairs(d.models or {}) do
            local ok = IsModelInCdimage(GetHashKey(m))
            print(('[bs_building] %-14s %-24s %s'):format(id, m, ok and 'OK' or 'missing'))
            if ok and not picked then picked = m end
        end
        if picked then
            Building.LoadModel(GetHashKey(picked))
            local mn, mx = GetModelDimensions(GetHashKey(picked))
            print(('[bs_building] %-14s -> %s  %.2f x %.2f x %.2f m'):format(id, picked, mx.x - mn.x, mx.y - mn.y, mx.z - mn.z))
        end
    end
end) end, false)
