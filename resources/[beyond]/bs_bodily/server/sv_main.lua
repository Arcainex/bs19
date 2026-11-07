local states = {}

local function notify(src, kind, message)
    TriggerClientEvent('bs:bodily:notify', src, { type = kind, title = Lp(src, 'bd.notif_title'), message = message })
end

local function newDue(spec)
    return os.time() + math.random(spec.minSeconds, spec.maxSeconds)
end

local function publish(src, state)
    local bag = Player(src).state
    bag:set('bsSoiled', state and state.soiledUntil and state.soiledUntil > os.time() or false, true)
end

local function ensure(src)
    if not Bodily.enabled then return nil end
    local player = exports.bs_core:GetPlayer(src)
    if not player then return nil end
    local state = states[src]
    if not state or state.charId ~= player.charId then
        state = {
            charId = player.charId,
            peeAt = newDue(Bodily.pee),
            poopAt = newDue(Bodily.poop),
            peeWarned = false,
            poopWarned = false,
            soiledUntil = 0,
        }
        states[src] = state
        publish(src, state)
    end
    return state
end

local function urgency(now, dueAt, spec)
    local start = dueAt - spec.warningSeconds
    if now <= start then return 0 end
    return math.min(100, math.floor(((now - start) / (spec.warningSeconds + spec.graceSeconds)) * 100))
end

local function statusFor(src)
    local state = ensure(src)
    if not state then return { ok = false, message = Lp(src, 'bd.char') } end
    local now = os.time()
    return {
        ok = true,
        pee = urgency(now, state.peeAt, Bodily.pee),
        poop = urgency(now, state.poopAt, Bodily.poop),
        soiled = state.soiledUntil > now,
        soiledRemaining = math.max(0, state.soiledUntil - now),
    }
end

local function soil(src, state, reason)
    state.soiledUntil = os.time() + Bodily.soiledSeconds
    publish(src, state)
    notify(src, 'warn', reason .. ' ' .. Lp(src, 'bd.smell_long'))
end

BSB.RegisterCallback('bodily:status', function(src)
    return statusFor(src)
end)

BSB.RegisterCallback('bodily:relieve', function(src, kind)
    local state = ensure(src)
    local spec = kind == 'pee' and Bodily.pee or (kind == 'poop' and Bodily.poop or nil)
    if not state or not spec then return { ok = false, message = Lp(src, 'bd.unavail') } end

    local field = kind == 'pee' and 'peeAt' or 'poopAt'
    local now = os.time()
    if now < state[field] - spec.warningSeconds then
        return { ok = false, message = Lp(src, 'bd.not_yet') }
    end

    state[field] = newDue(spec)
    if kind == 'pee' then state.peeWarned = false else state.poopWarned = false end
    return { ok = true, message = kind == 'pee' and Lp(src, 'bd.peed') or Lp(src, 'bd.pooped') }
end)

AddEventHandler('bs:hook:player:loaded', function(player)
    if player and player.source then ensure(player.source) end
end)

AddEventHandler('playerDropped', function()
    states[source] = nil
end)

CreateThread(function()
    while true do
        Wait(30000)
        if Bodily.enabled then
            local now = os.time()
            for src, state in pairs(states) do
                local player = exports.bs_core:GetPlayer(src)
                if not player then
                    states[src] = nil
                else
                    for kind, spec in pairs({ pee = Bodily.pee, poop = Bodily.poop }) do
                        local field = kind == 'pee' and 'peeAt' or 'poopAt'
                        local warned = kind == 'pee' and 'peeWarned' or 'poopWarned'
                        if now >= state[field] - spec.warningSeconds and not state[warned] then
                            state[warned] = true
                            notify(src, 'warn', kind == 'pee' and Lp(src, 'bd.bladder_urgent') or Lp(src, 'bd.stomach_urgent'))
                        end
                        if now >= state[field] + spec.graceSeconds then
                            soil(src, state, kind == 'pee' and Lp(src, 'bd.accident') or Lp(src, 'bd.soiled_self'))
                            state[field] = newDue(spec)
                            state[warned] = false
                        end
                    end
                    if state.soiledUntil > 0 and state.soiledUntil <= now then
                        state.soiledUntil = 0
                        publish(src, state)
                        notify(src, 'info', Lp(src, 'bd.faded'))
                    end
                end
            end
        end
    end
end)
