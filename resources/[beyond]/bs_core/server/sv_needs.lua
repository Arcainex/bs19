-- Needs are simulated client-side and validated/persisted here. A client can only lower its own needs; raising goes through server-side consumables.

local lastPersist = {}

RegisterNetEvent(BS.Events.UpdateNeeds, function(hunger, thirst, infection)
    local src = source
    local player = BS.GetPlayer(src)
    if not player then return end

    hunger = tonumber(hunger)
    thirst = tonumber(thirst)
    infection = tonumber(infection) or player.needs.infection or 0.0
    if not hunger or not thirst then return end

    -- Hunger and thirst may only fall from a client report; infection may only rise. Eating, drinking and curing are server actions.
    if hunger > player.needs.hunger + 0.01 or thirst > player.needs.thirst + 0.01
       or infection < (player.needs.infection or 0.0) - 0.01 then
        BS.Log.warn('needs', ('rejected needs change from %s (%s)'):format(src, player.name))
        return TriggerClientEvent(BS.Events.PlayerNeeds, src, player.needs)
    end

    player.needs.hunger    = BS.Util.Clamp(hunger, 0.0, 100.0)
    player.needs.thirst    = BS.Util.Clamp(thirst, 0.0, 100.0)
    player.needs.infection = BS.Util.Clamp(infection, 0.0, 100.0)

    local now = BS.Util.Now()
    if now - (lastPersist[src] or 0) >= (Config.Needs.persistInterval or 120) then
        lastPersist[src] = now
        player.dirty = true
        player:Save()
    end
end)

--- Server-side restore, used by consumables (bs_inventory) and admin commands.
--- @param src number
--- @param hungerDelta number
--- @param thirstDelta number
function BS.RestoreNeeds(src, hungerDelta, thirstDelta)
    local player = BS.GetPlayer(src)
    if not player then return false end
    player:SetNeeds(
        player.needs.hunger + (tonumber(hungerDelta) or 0),
        player.needs.thirst + (tonumber(thirstDelta) or 0)
    )
    return true
end

exports('RestoreNeeds', BS.RestoreNeeds)

--- Server-authoritative infection change. Positive infects, negative cures.
function BS.ChangeInfection(src, delta)
    local player = BS.GetPlayer(src)
    if not player then return false end
    local value = BS.Util.Clamp((player.needs.infection or 0.0) + (tonumber(delta) or 0), 0.0, 100.0)
    player.needs.infection = value
    player.dirty = true
    TriggerClientEvent('bs:needs:setInfection', src, value)
    TriggerClientEvent(BS.Events.PlayerNeeds, src, player.needs)
    BS.Emit('player:infection', player, value)
    return true
end

exports('ChangeInfection', BS.ChangeInfection)

--- HUD preference storage, so a player's layout follows their character.
BSB.RegisterCallback('core:saveHudSettings', function(src, settings)
    local player = BS.GetPlayer(src)
    if not player then return { ok = false } end
    player:SetHudSettings(settings)
    return { ok = true }
end)

AddEventHandler('playerDropped', function() lastPersist[source] = nil end)
