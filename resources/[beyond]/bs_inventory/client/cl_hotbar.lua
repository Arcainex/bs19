-- bs_inventory - hotbar. Five slots on keys 1-5 with a take-out animation. The slot is resolved server-side and the item goes through the normal use path, so the same checks apply as from the bag.

-- `visible` = may the bar be on screen at all (false while a menu is up). `peek` = player is holding ALT. They are ANDed in push(); keep them separate flags.
local Bar = { slots = {}, busy = false, visible = true, peek = false }

-- Bar shows only while ALT (control 19) is held; the `alwaysOn` setting pins it. ALT is shared with the bs_interactions look-at menu and is only read here, never disabled. The setting is stored per client in KVP, not in the database.

local PEEK_CONTROL = 19          -- INPUT_CHARACTER_WHEEL, i.e. left ALT
local KVP_ALWAYS = 'bs_hotbar_always'

--- Read once at start; the setter below keeps it in step.
local alwaysOn = (GetResourceKvpInt(KVP_ALWAYS) or 0) == 1

local DRAW = {
    -- Reaching into a pocket. Upper body only, so it works while walking.
    dict = 'anim@heists@humane_labs@finale@keycards',
    clip = 'ped_a_enter_loop',
    time = 700,
    flag = 49,
}

local function send(payload)
    if GetResourceState('bs_ui') ~= 'started' then return end
    pcall(function() exports.bs_ui:Send(payload) end)
end

--------------------------------------------------------------------------------
-- Drawing it
--------------------------------------------------------------------------------

local function push()
    -- Drawn while playing if allowed on screen and either alwaysOn is set or ALT is held.
    local onScreen = Bar.visible and (alwaysOn or Bar.peek)

    send({ action = 'hotbar', slots = Bar.slots, visible = onScreen })

    -- The bag draws the same five slots while open so you can drag items onto them. SendNUIMessage reaches this resource's own page.
    SendNUIMessage({ action = 'hotbar', slots = Bar.slots })
end

RegisterNetEvent('bs:hotbar:state', function(slots)
    Bar.slots = slots or {}
    push()
end)

--------------------------------------------------------------------------------
-- Using a slot
--------------------------------------------------------------------------------

local function playDraw()
    local ped = PlayerPedId()
    if not DoesAnimDictExist(DRAW.dict) then return end

    if not HasAnimDictLoaded(DRAW.dict) then RequestAnimDict(DRAW.dict) end
    local waited = 0
    while not HasAnimDictLoaded(DRAW.dict) and waited < 900 do Wait(10); waited = waited + 10 end
    if not HasAnimDictLoaded(DRAW.dict) then return end

    TaskPlayAnim(ped, DRAW.dict, DRAW.clip, 4.0, -4.0, DRAW.time, DRAW.flag, 0.0, false, false, false)
end

local function cinematicCameraActive()
    if GetResourceState('bs_cinecam') ~= 'started' then return false end
    local ok, active = pcall(function() return exports.bs_cinecam:IsActive() end)
    return ok and active == true
end

-- Key a mapping command is bound to right now ("t_5" -> "5").
local function boundKey(cmd)
    local raw = GetControlInstructionalButton(0, joaat(cmd) | 0x80000000, true) or ''
    return (raw:gsub('^t_', ''):upper())
end

-- If a booster/gadget slot is bound to the same key, that system owns it.
local function keyOwnedElsewhere(index)
    local mine = boundKey(('bs_hotbar%d'):format(index))
    if mine == '' then return false end
    for _, res in ipairs({ 'bs_boosters', 'bs_gadgets' }) do
        if GetResourceState(res) == 'started' then
            local ok, keys = pcall(function() return exports[res]:KeyLabels() end)
            if ok and type(keys) == 'table' then
                for _, k in ipairs(keys) do if tostring(k):upper() == mine then return true end end
            end
        end
    end
    return false
end

local function useSlot(index)
    -- Hotbar commands are key mappings, so control disabling does not stop them. The camera owns 1-9 while active.
    if cinematicCameraActive() then return end
    if keyOwnedElsewhere(index) then return end
    if Bar.busy then return end

    local ped = PlayerPedId()
    if IsPedDeadOrDying(ped, true) then return end
    if not exports.bs_core:IsLoaded() then return end

    Bar.busy = true

    -- What is in this slot, and is any left?
    local found = BSB.Await('hotbar:use', 6000, index)

    if not found or not found.ok then
        Bar.busy = false
        -- Empty slot: say nothing.
        if found and found.error and found.error ~= 'nothing there' then
            TriggerEvent('bs:ui:notify', { type = 'warn', message = found.error, duration = 2000 })
        end
        return
    end

    send({ action = 'hotbarFire', index = index })

    -- A weapon slot is a toggle: pressing the slot of the gun in your hands holsters it, pressing again draws it. bs_weapons owns holstering; this only says which weapon the slot is.
    if found.weapon and GetResourceState('bs_weapons') == 'started' then
        local ped = PlayerPedId()
        local _, current = GetCurrentPedWeapon(ped, true)

        if current == GetHashKey(found.weapon) then
            TriggerEvent('bs:weapons:hotbarWeapon', found.weapon)
            Wait(400)
            Bar.busy = false
            return
        end
    end

    -- Take it out, then use it.
    playDraw()
    Wait(math.floor(DRAW.time * 0.6))

    local result = BSB.Await('inventory:use', 8000, found.slot)

    if result and result.ok then
        -- Freshly in hand: nothing is stowed any more.
        if found.weapon then TriggerEvent('bs:weapons:hotbarWeapon', nil) end

        TriggerEvent('bs:ui:notify', {
            type = 'success', message = result.label or found.item, duration = 1800,
        })
    elseif result and result.error then
        TriggerEvent('bs:ui:notify', { type = 'warn', message = result.error, duration = 2000 })
    end

    Wait(200)
    Bar.busy = false
end

-- Keys use RegisterKeyMapping so they show in the FiveM key bindings and can be rebound.

for index = 1, 5 do
    RegisterCommand(('bs_hotbar%d'):format(index), function()
        if LocalPlayer.state.bsDrone then return end -- flying the drone
        CreateThread(function() useSlot(index) end)
    end, false)

    RegisterKeyMapping(('bs_hotbar%d'):format(index),
        L('hotbar.keymap', { n = index }), 'keyboard', tostring(index))
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

-- Hidden while any menu is up. A set of open panels (like bs_chat's blockingPanels) is used instead of one boolean, so the bar only returns when the last one closes.
local openPanels = {}

AddEventHandler('bs:ui:opened', function(name)
    openPanels[name or '?'] = true
    Bar.visible = false
    push()
end)

AddEventHandler('bs:ui:closed', function(name)
    if name == nil then
        openPanels = {}           -- a nameless close means "everything is shut"
    else
        openPanels[name] = nil
    end
    Bar.visible = next(openPanels) == nil
    push()
end)

AddEventHandler('bs:hook:player:unloaded', function()
    Bar.slots = {}
    Bar.visible = false
    push()
end)

-- Safety net: bs:ui:opened/closed can get out of step if a menu closes another way, leaving the bar hidden. If nothing holds NUI focus, the bar is shown again.
CreateThread(function()
    while true do
        Wait(1500)
        if not Bar.visible and not IsNuiFocused() and exports.bs_core:IsLoaded() then
            openPanels = {}       -- the bookkeeping drifted; nothing is holding focus
            Bar.visible = true
            push()
        end
    end
end)

CreateThread(function()
    while not exports.bs_core:IsLoaded() do Wait(500) end
    Wait(2000)

    local result = BSB.Await('hotbar:get', 8000)
    if result and result.ok then
        Bar.slots = result.slots or {}
        push()
    end
end)

-- Binding from the inventory context menu

-- The bar holds real items (slots 41-45 of the same inventory), so set/swap/split are the normal inventory MOVE. No separate hotbar set/swap events, two ways to move an item would duplicate things.

exports('UseSlot', function(index) CreateThread(function() useSlot(index) end) end)
exports('Slots', function() return Bar.slots end)


-- Hold ALT to see it

-- Polled instead of key-mapped: a missed key release (alt-tab while held) would leave the bar stuck on. Reads the current control state and only pushes on a change.
CreateThread(function()
    while true do
        Wait(0)

        if alwaysOn then
            -- Nothing to poll; the setting decides and push() already knows.
            if Bar.peek then Bar.peek = false end
            Wait(500)
        else
            -- Check both forms: cl_target.lua disables control 19 every frame (ALT is its look-at key), and a disabled control reads as not pressed in IsControlPressed. IsDisabledControlPressed covers it.
            local held = (IsDisabledControlPressed(0, PEEK_CONTROL)
                      or IsControlPressed(0, PEEK_CONTROL))
                      and not LocalPlayer.state.bsDrone
            if held ~= Bar.peek then
                Bar.peek = held
                push()
            end
        end
    end
end)

-- /hotbar toggles hold-ALT and always-on. Also an export, so a settings menu uses the same implementation.
local function setAlwaysOn(value)
    alwaysOn = value and true or false
    SetResourceKvpInt(KVP_ALWAYS, alwaysOn and 1 or 0)

    -- Clear the peek state when pinned, so releasing ALT after a mode switch cannot hide a pinned bar.
    Bar.peek = false
    push()
    return alwaysOn
end

RegisterCommand('hotbar', function()
    local now = setAlwaysOn(not alwaysOn)
    TriggerEvent('bs:ui:notify', { type = 'info', duration = 3500,
        message = now and L('hotbar.always')
                       or L('hotbar.hold_alt') })
end, false)

exports('HotbarAlwaysVisible', function() return alwaysOn end)
exports('SetHotbarAlwaysVisible', function(value) return setAlwaysOn(value) end)
