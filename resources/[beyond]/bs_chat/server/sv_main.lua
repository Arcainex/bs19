-- BeyondSurvival - bs_chat server: sends player speech to the right players. Commands never reach this file (the client splits them off), so the server only handles what a client must not be trusted with.

local S = (Chat and Chat.Settings) or {}

--- [src] = { window = os.time(), n = 0 }
local rate = {}

-- The name comes from the character, not the client. Falls back to the connection name when no character is loaded, so messages stay readable.
local function speakerName(src)
    if GetResourceState('bs_core') == 'started' then
        local ok, player = pcall(function() return exports.bs_core:GetPlayer(src) end)
        if ok and player and player.name and player.name ~= '' then return player.name end
    end
    return GetPlayerName(src) or ('player ' .. tostring(src))
end

local function allowed(src)
    local now = os.time()
    local bucket = rate[src]

    if not bucket or (now - bucket.window) >= 10 then
        rate[src] = { window = now, n = 1 }
        return true
    end

    bucket.n = bucket.n + 1
    return bucket.n <= (S.rateLimit or 12)
end

-- Chat is global by default. Proximity is implemented but off (see config_chat.lua). It measures ped to ped and always includes the speaker.
local function audienceFor(src)
    local prox = S.proximity
    if not prox or not prox.enabled then return -1 end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { src } end

    local at = GetEntityCoords(ped)
    local range2 = (prox.range or 40.0) ^ 2
    local out = { src }

    for _, sid in ipairs(GetPlayers()) do
        local other = tonumber(sid)
        if other and other ~= src then
            local otherPed = GetPlayerPed(other)
            if otherPed and otherPed ~= 0 then
                local d = GetEntityCoords(otherPed) - at
                if (d.x * d.x + d.y * d.y + d.z * d.z) <= range2 then
                    out[#out + 1] = other
                end
            end
        end
    end

    return out
end

RegisterNetEvent('bs:chat:say', function(text)
    local src = source

    if type(text) ~= 'string' then return end
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return end

    -- Strip ^1..^9 colour codes from player speech so players cannot paint text or imitate system and staff lines. Server messages keep their codes.
    text = text:gsub('%^[0-9r]', '')
    text = text:sub(1, S.maxLength or 220)
    if text == '' then return end

    if not allowed(src) then return end

    local payload = {
        args   = { speakerName(src), text },
        color  = { 240, 235, 221 },
    }

    -- VIP badge / name colour (cosmetic; each viewer can hide these).
    if GetResourceState('bs_vip') == 'started' then
        local ok, style = pcall(function() return exports.bs_vip:ChatStyle(src) end)
        if ok and type(style) == 'table' then payload.vip = style end
    end

    local audience = audienceFor(src)

    if audience == -1 then
        TriggerClientEvent('chat:addMessage', -1, payload)
    else
        for _, target in ipairs(audience) do
            TriggerClientEvent('chat:addMessage', target, payload)
        end
    end
end)

AddEventHandler('playerDropped', function()
    rate[source] = nil
end)

-- Server-side way for other resources to post a chat message without hand-writing the TriggerClientEvent payload.
exports('Send', function(target, tag, message, colour)
    TriggerClientEvent('chat:addMessage', target or -1, {
        args  = tag and { tag, message } or { message },
        color = colour or { 224, 140, 70 },
    })
end)
