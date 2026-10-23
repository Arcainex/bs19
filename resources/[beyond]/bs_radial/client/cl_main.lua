-- bs_radial - Lua side of the wheel.
-- `Open` blocks the calling thread until the player picks or cancels, and returns the slice id. Only plain data crosses the resource boundary. Only one wheel exists at a time; opening a second closes the first.

local S = Radial.Settings

local State = {
    open     = false,
    token    = 0,
    result   = nil,
    answered = false,
    owner    = nil,
}

-- One waiter per call, keyed by token, so one wheel closing can only answer itself. A shared State.answered let a second Open (e.g. a mashed keybind) wake the first caller's cleanup while the second wheel was still up.
local Waiters = {}

local function send(payload) SendNUIMessage(payload) end

-- Wheel position and background blur are per-caller. The weapon wheel uses the right half of the screen and needs the left half unblurred, so a spec can set `blur = false`.
local ANCHORS = { centre = true, right = true, left = true }

local function anchorFor(spec)
    local want = spec and spec.anchor or S.anchor or 'centre'
    return ANCHORS[want] and want or 'centre'
end

local function blurFor(spec)
    if spec and spec.blur ~= nil then return spec.blur and true or false end
    return S.blurWorld and true or false
end

local function setFocus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

-- Sanitising what a caller sends: everything that reaches the NUI is rebuilt here, so no markup, functions or deep nesting get through.

local function sanitise(items, depth)
    depth = depth or 1
    local out = {}

    for _, item in ipairs(items or {}) do
        if type(item) == 'table' and item.id then
            local entry = {
                id       = tostring(item.id),
                label    = tostring(item.label or item.id),
                icon     = Radial.Icons[item.icon] and item.icon or 'dot',
                note     = item.note and tostring(item.note) or nil,
                disabled = item.disabled and true or false,
                danger   = item.danger and true or false,
                active   = item.active and true or false,
            }

            -- One level of nesting is enough.
            if item.submenu and depth < 3 then
                entry.submenu = sanitise(item.submenu, depth + 1)
                entry.title   = item.title and tostring(item.title) or entry.label
            end

            out[#out + 1] = entry
            if #out >= 12 then break end    -- more slices than this is unreadable
        end
    end

    return out
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

-- @param result string|nil the slice that was picked, or nil
-- @param token number|nil which wheel this answer belongs to. nil means whatever is open now (internal pre-empt); the NUI passes its own token so answers from a replaced wheel are dropped.
local function close(result, token)
    if not State.open then return end

    -- NUI callbacks are asynchronous, so a late 'pick' from a replaced wheel could resolve the new wheel with the old slice. Drop answers whose token does not match.
    if token ~= nil and token ~= State.token then return end

    local waiter = Waiters[State.token]
    if waiter then
        waiter.result = result
        waiter.answered = true
    end

    State.open = false
    State.result = result      -- kept for anything still reading it
    State.answered = true

    send({ action = 'close' })
    setFocus(false)

    -- Only undo the blur this wheel applied, so a wheel opened with blur = false does not clear a blur from the hub or inventory.
    if State.blurred then
        TriggerScreenblurFadeOut(S.fadeOut or 90)
        State.blurred = false
    end
    TriggerEvent('bs:ui:closed', 'radial')
end

Radial.Close = close

--- @param spec table { title, items = { {id, label, icon, note, disabled, submenu} } }
--- @return string|nil id of the slice the player chose
function Radial.Open(spec)
    if type(spec) ~= 'table' then return nil end

    local items = sanitise(spec.items)
    if #items == 0 then return nil end

    -- Never two at once, and never on top of another menu.
    if State.open then close(nil) Wait(60) end

    if S.exclusive then TriggerEvent('bs:ui:requestClose', 'radial') end

    State.token = State.token + 1
    State.open = true
    State.answered = false
    State.result = nil
    State.openedAt = GetGameTimer()

    -- This call's own answer slot.
    local myToken = State.token
    local waiter = { answered = false, result = nil }
    Waiters[myToken] = waiter

    send({
        action = 'open',
        token  = State.token,
        title  = spec.title and tostring(spec.title) or nil,
        items  = items,
        icons  = Radial.Icons,
        geometry = {
            outer = S.outerRadius, inner = S.innerRadius, dead = S.deadZone,
        },
        hold = (spec.hold ~= nil) and spec.hold or S.holdToPick,
        anchor = anchorFor(spec),
    })

    setFocus(true)
    if blurFor(spec) then
        TriggerScreenblurFadeIn(S.fadeIn or 120)
        State.blurred = true
    end
    TriggerEvent('bs:ui:opened', 'radial')

    -- Hold to pick. If opened from a held key, the wheel stays up while the key is down and the slice under the cursor is taken on release. NUI focus swallows the keyboard, so the key is read here. Without a control id it is click-to-pick.
    if spec.holdControl then
        CreateThread(function()
            local held = false
            local since = GetGameTimer()

            while State.open do
                Wait(0)

                -- Keep the key alive under NUI focus.
                DisableControlAction(0, spec.holdControl, true)
                local down = IsDisabledControlPressed(0, spec.holdControl)

                if down then held = true end

                -- Released after actually being held: resolve.
                if held and not down then
                    send({ action = 'release' })
                    return
                end

                -- Tapped rather than held: leave it open to be clicked.
                if not held and GetGameTimer() - since > 400 then return end
            end
        end)
    end

    -- Block until our wheel answers.
    local waited = 0
    while not waiter.answered and waited < (S.timeout or 30000) do
        Wait(10)
        waited = waited + 10
    end

    if not waiter.answered then
        -- Timed out. Only close if we are still the wheel on screen, otherwise we would close someone else's.
        if State.token == myToken then close(nil, myToken) end
        waiter.answered = true
    end

    Waiters[myToken] = nil
    return waiter.result
end

--------------------------------------------------------------------------------
-- From the wheel
--------------------------------------------------------------------------------

RegisterNUICallback('pick', function(data, cb)
    close(data and data.id or nil, data and tonumber(data.token) or nil)
    cb({ ok = true })
end)

RegisterNUICallback('cancel', function(data, cb)
    close(nil, data and tonumber(data.token) or nil)
    cb({ ok = true })
end)

--------------------------------------------------------------------------------
-- Safety
--------------------------------------------------------------------------------

-- Anything else opening a menu closes this one, so no wheel is left holding NUI focus.
AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'radial' and State.open then close(nil) end
end)

AddEventHandler('bs:hook:player:unloaded', function() close(nil) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(0)
    -- close() will not run now, so tell the listeners ourselves.
    if State.open then TriggerEvent('bs:ui:closed', 'radial') end
end)

-- Dying with a wheel open must not strand you either.
CreateThread(function()
    while true do
        Wait(500)
        if State.open and IsPedDeadOrDying(PlayerPedId(), true) then close(nil) end
    end
end)

-- Exports. Use Begin/Poll, not Open: an export called from another resource cannot yield across the resource boundary, so Open's Wait would throw and leave the wheel up with NUI focus and blur.
-- `Begin` returns a token immediately, `Poll` returns plain data, and the waiting happens in the caller's resource (see BSB.Radial in sh_bridge.lua).

-- Opens the wheel and returns at once.
-- @return number|nil token  pass to Poll; nil if the spec had nothing in it
exports('Begin', function(spec)
    if type(spec) ~= 'table' then return nil end

    local items = sanitise(spec.items)
    if #items == 0 then return nil end

    if State.open then close(nil) end

    if S.exclusive then TriggerEvent('bs:ui:requestClose', 'radial') end

    State.token = State.token + 1
    State.open = true
    State.answered = false
    State.result = nil
    State.openedAt = GetGameTimer()

    local token = State.token

    send({
        action = 'open',
        token  = token,
        title  = spec.title and tostring(spec.title) or nil,
        items  = items,
        icons  = Radial.Icons,
        geometry = {
            outer = S.outerRadius, inner = S.innerRadius, dead = S.deadZone,
        },
        hold = (spec.hold ~= nil) and spec.hold or S.holdToPick,
        anchor = anchorFor(spec),
    })

    setFocus(true)
    if blurFor(spec) then
        TriggerScreenblurFadeIn(S.fadeIn or 120)
        State.blurred = true
    end
    TriggerEvent('bs:ui:opened', 'radial')

    -- Hold to pick, same as Open. It lives here because the key can only be read from a thread that disables and re-reads the control every frame under NUI focus.
    if spec.holdControl then
        CreateThread(function()
            local held = false
            local since = GetGameTimer()

            while State.open and State.token == token do
                Wait(0)

                DisableControlAction(0, spec.holdControl, true)
                local down = IsDisabledControlPressed(0, spec.holdControl)

                if down then held = true end

                if held and not down then
                    send({ action = 'release' })
                    return
                end

                -- Tapped rather than held: leave it open to be clicked.
                if not held and GetGameTimer() - since > 400 then return end
            end
        end)
    end

    return token
end)

--- @return table { done = boolean, id = string|nil }
exports('Poll', function(token)
    -- A token that is not the current one belongs to a superseded wheel. Answer done with no pick so the old caller stops waiting.
    if token ~= State.token then return { done = true, id = nil } end
    if State.answered then return { done = true, id = State.result } end
    return { done = false, id = nil }
end)

-- The caller gave up (its own timeout). Take the wheel down.
exports('Abandon', function(token)
    if token == State.token and State.open then close(nil) end
    return true
end)

exports('Open', function(spec) return Radial.Open(spec) end)
exports('Close', function() close(nil) end)
exports('IsOpen', function() return State.open end)

-- Nothing is left on screen: whatever happens to the caller (error, resource restart), the wheel must not stay up holding NUI focus.

CreateThread(function()
    while true do
        Wait(1000)

        if State.open and State.openedAt
           and GetGameTimer() - State.openedAt > (S.timeout or 30000) then
            print('^3[BeyondSurvival]^7 (radial) wheel timed out with nobody listening - closing')
            close(nil)
        end

        -- Do not clear NUI focus here when the wheel is shut. IsNuiFocused is client-wide and the inventory or hub may hold it; the wheel only releases focus it took itself, in close().
    end
end)

-- ESC always closes it.
CreateThread(function()
    while true do
        Wait(0)
        if State.open then
            if IsControlJustPressed(0, 200) or IsControlJustPressed(0, 202) then
                close(nil)
            end
        else
            Wait(250)
        end
    end
end)
