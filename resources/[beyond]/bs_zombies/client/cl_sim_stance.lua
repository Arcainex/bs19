-- bs_zombies - stance report: sends the player's crouch/prone state to the server

local REPORT_MS = 250          -- how often we LOOK. Cheap; nothing is sent.
local HEARTBEAT_MS = 4000      -- re-send even when unchanged, so a server
                               -- so a server restart re-learns stances without waiting for a change.

local last = { crouched = nil, prone = nil, stealth = nil }
local lastSentAt = 0

local function emotesFlag(name)
    if GetResourceState('bs_emotes') ~= 'started' then return nil end
    local ok, value = pcall(function() return exports.bs_emotes[name](exports.bs_emotes) end)
    if ok and type(value) == 'boolean' then return value end
    return nil
end

-- A probe returning nil means unknown, not false, so it falls through to the next source
local function readStance()
    local ped = PlayerPedId()
    if not ped or ped == 0 then return nil end

    local crouched = emotesFlag('IsCrouched')
    local prone = emotesFlag('IsProne')

    if crouched == nil then
        local ok, ducking = pcall(IsPedDucking, ped)
        crouched = (ok and ducking) and true or false
    end
    if prone == nil then prone = false end

    local stealth = false
    local ok, sm = pcall(GetPedStealthMovement, ped)
    if ok and sm then stealth = true end

    local mult = 1.0
    if Zombies and Zombies.LocalStealthMultiplier then
        local okM, m = pcall(Zombies.LocalStealthMultiplier)
        if okM and type(m) == 'number' then mult = m end
    end

    return { crouched = crouched and true or false,
             prone = prone and true or false,
             stealth = stealth,
             -- skills + gear + soiled, see cl_ai. The server clamps it.
             mult = math.floor(mult * 100 + 0.5) / 100 }
end

CreateThread(function()
    -- Cheap to run at join; the server treats an unknown player as standing anyway.
    Wait(5000)

    while true do
        Wait(REPORT_MS)

        local s = readStance()
        if s then
            local now = GetGameTimer()
            local changed = (s.crouched ~= last.crouched)
                         or (s.prone ~= last.prone)
                         or (s.stealth ~= last.stealth)
                         or (math.abs((s.mult or 1.0) - (last.mult or 1.0)) >= 0.05)

            if changed or (now - lastSentAt) >= HEARTBEAT_MS then
                last.crouched, last.prone, last.stealth, last.mult = s.crouched, s.prone, s.stealth, s.mult
                lastSentAt = now
                TriggerServerEvent('bs:sim:stance', s)
            end
        end
    end
end)

-- /zstance - shows the stance this client reports
RegisterCommand('zstance', function()
    local s = readStance() or {}
    TriggerEvent('chat:addMessage', { args = { ('^5[BS SIM]^7 crouched=%s prone=%s stealth=%s (bs_emotes %s)')
        :format(tostring(s.crouched), tostring(s.prone), tostring(s.stealth),
                GetResourceState('bs_emotes')) } })
end, false)
