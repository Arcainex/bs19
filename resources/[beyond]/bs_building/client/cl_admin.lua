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
    if open then
        open = false
        SetNuiFocus(false, false)
        TriggerEvent('bs:ui:closed', 'building')
    end
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
            if open then
                open = false
                SetNuiFocus(false, false)
                TriggerEvent('bs:ui:closed', 'building')
            end
            SendNUIMessage({ action = 'adminHide' })
        end
        cb(res or { ok = false })
    end)
end)

-- /buildmodels: prints which model each piece and tier really uses here and its size, to check props in game (F8)
RegisterCommand('buildmodels', function() CreateThread(function()
    local ids = {}
    for id in pairs(Building.Pieces) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local d = Building.Pieces[id]
        local tiers = Building.TierList(d)
        if #tiers == 0 then tiers = { false } end
        for _, t in ipairs(tiers) do
            local sp = Building.Spec(d, t or nil) or d
            local picked
            for _, m in ipairs(sp.models or {}) do
                local ok = IsModelInCdimage(GetHashKey(m))
                print(('[bs_building] %-16s %-9s %-26s %s'):format(id, t or '-', m, ok and 'OK' or 'MISSING'))
                if ok and not picked then picked = m end
            end
            if picked then
                local mn, mx = Building.Dims(GetHashKey(picked))
                print(('[bs_building] %-16s %-9s -> %s  %.2f x %.2f x %.2f m'):format(id, t or '-', picked, mx.x - mn.x, mx.y - mn.y, mx.z - mn.z))
            end
        end
    end
end) end, false)
