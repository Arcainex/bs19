local function notify(payload)
    if GetResourceState('bs_ui') == 'started' then
        exports.bs_ui:Notify(payload)
    end
end

RegisterNetEvent('bs:bodily:notify', function(payload)
    notify(payload)
end)

local function urgencyNote(value)
    if value >= 80 then return L('bd.critical') end
    if value >= 45 then return L('bd.urgent') end
    if value > 0 then return L('bd.building') end
    return L('bd.comfortable')
end

local function openNeeds()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if not Bodily.enabled or GetResourceState('bs_radial') ~= 'started' then return end
    CreateThread(function()
        local status = BSB.Await('bodily:status', 5000) or {}
        if not status.ok then
            return notify({ type = 'warn', title = L('bd.title'), message = status.message or L('bd.not_ready') })
        end

        local coreNeeds = exports.bs_core:GetNeeds() or {}
        local items = {
            { id = 'status', label = L('bd.status', { food = math.floor(coreNeeds.hunger or 0), water = math.floor(coreNeeds.thirst or 0) }), icon = 'needs', disabled = true, note = L('bd.keep_eating') },
            { id = 'pee', label = L('bd.pee'), icon = 'pee', note = L('bd.bladder', { s = urgencyNote(status.pee) }), disabled = status.pee < 1 },
            { id = 'poop', label = L('bd.poop'), icon = 'poop', note = L('bd.bowel', { s = urgencyNote(status.poop) }), disabled = status.poop < 1 },
        }
        if status.soiled then
            items[#items + 1] = { id = 'soiled', label = L('bd.soiled'), icon = 'warn', danger = true, disabled = true, note = L('bd.smell') }
        end

        local choice = exports.bs_radial:Open({ title = L('bd.title'):upper(), items = items, blur = false })
        if choice ~= 'pee' and choice ~= 'poop' then return end
        local result = BSB.Await('bodily:relieve', 5000, choice) or {}
        notify({ type = result.ok and 'success' or 'warn', title = L('bd.title'), message = result.message or L('bd.nothing') })
    end)
end

RegisterCommand('needswheel', openNeeds, false)
RegisterKeyMapping('needswheel', L('bodily.key_wheel'), 'keyboard', 'N')
