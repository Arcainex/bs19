-- BeyondSurvival - bs_factions client. A local mirror of the last 'bs:factions:sync' payload so exports.bs_factions:Current() is instant. Nothing is computed here; actions go through BSB.Await to the server.

local current = { factionId = nil, reputation = 0, unlocks = {} }

RegisterNetEvent('bs:factions:sync', function(payload)
    if type(payload) ~= 'table' then return end
    current = payload
    LocalPlayer.state:set('bsFactionCanInvite', current.canInvite == true or current.rank == 'owner', false)
end)

AddEventHandler('bs:hook:player:loaded', function()
    -- The server pushes 'bs:factions:sync' itself once it has resolved state
    -- for this connection; nothing to request here.
end)

--------------------------------------------------------------------------------
-- Exports - plain data only, read by bs_ui (nameplate/title), bs_emotes and
-- bs_inventory (cosmetic gating) once they choose to wire into it.
--------------------------------------------------------------------------------

exports('Current', function() return current end)
exports('IsMember', function(factionId) return current.factionId == factionId end)
exports('GetTitle', function()
    -- Highest unlocked title for the CURRENT faction only; matches the
    -- server's GetTitle export.
    local faction = current.factionId and Factions.Get(current.factionId)
    if not faction then return nil end
    local best = nil
    for _, unlock in ipairs(faction.unlocks) do
        if unlock.type == 'title' and current.unlocks and current.unlocks[unlock.id] then
            best = unlock.label
        end
    end
    return best
end)

--------------------------------------------------------------------------------
-- Convenience wrappers other client scripts can call instead of hand-rolling
-- BSB.Await every time.
--------------------------------------------------------------------------------

exports('Join', function(factionId)
    return BSB.Await('factions:join', 6000, factionId)
end)

exports('Leave', function()
    return BSB.Await('factions:leave', 6000)
end)

exports('Status', function()
    return BSB.Await('factions:status', 6000)
end)

--------------------------------------------------------------------------------
-- ALT recruiting
--
-- Officers and owners get an interaction option on nearby players while holding
-- ALT. The client only presents the option; the server still checks faction,
-- rank, target membership, and range before an invitation is created.
--------------------------------------------------------------------------------

local inviteOptionRegistered = false
local function registerInviteOption()
    if inviteOptionRegistered or GetResourceState('bs_interactions') ~= 'started' then return end
    exports.bs_interactions:AddType('ped', {{
        label = L('fac.invite_option'),
        labelKey = 'fac.invite_option',
        icon = 'faction',
        distance = 2.5,
        event = 'bs:factions:targetInvite',
        filters = { playerPed = true, onFoot = true, maxDistance = 2.5,
            playerStateTrue = 'bsFactionCanInvite' },
    }})
    inviteOptionRegistered = true
end

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(500) end
    registerInviteOption()
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'bs_interactions' then registerInviteOption() end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'bs_interactions' then inviteOptionRegistered = false end
end)

AddEventHandler('bs:hook:player:unloaded', function()
    current = { factionId = nil, reputation = 0, unlocks = {} }
    LocalPlayer.state:set('bsFactionCanInvite', false, false)
end)

AddEventHandler('bs:factions:targetInvite', function(payload)
    local entity = payload and payload.entity
    if not entity or not DoesEntityExist(entity) or not IsPedAPlayer(entity) then return end
    local player = NetworkGetPlayerIndexFromPed(entity)
    if not player or player == -1 or player == PlayerId() then return end
    local target = GetPlayerServerId(player)
    if not target or target <= 0 then return end

    CreateThread(function()
        local result = BSB.Await('factions:invite', 8000, target)
        TriggerEvent('bs:ui:notify', {
            type = result and result.ok and 'success' or 'warn',
            message = result and (result.ok and L('fac.invite_sent') or result.error)
                or L('fac.no_answer'),
            duration = 3500,
        })
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        LocalPlayer.state:set('bsFactionCanInvite', false, false)
    end
end)

-- GTA can suppress hits between player peds even without a faction rule.
-- Keep that engine switch on; the server protects only the actual safe zones.
CreateThread(function()
    local previousPed = 0
    while true do
        local ped = PlayerPedId()
        if ped ~= previousPed and ped ~= 0 then
            SetCanAttackFriendly(ped, true, false)
            previousPed = ped
        end
        NetworkSetFriendlyFireOption(true)
        Wait(1000)
    end
end)

