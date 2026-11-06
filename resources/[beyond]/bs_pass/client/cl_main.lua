-- Wasteland Pass client: opens the NUI and forwards button presses to the server. No game logic here.
local open = false

local function call(name, ...)
    return BSB.Await(name, 8000, ...)
end

-- F1 switch: Pass.Settings.menuEnabled = false hides the whole menu
local function menuOn() return Pass.Settings.menuEnabled ~= false end

local function show()
    if open or not menuOn() then return end
    local res = call('bs_pass:get')
    if not res or not res.ok then return end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = res.data, strings = BSLocale.Dict() })
end

local function hide()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterCommand(Pass.Settings.command or 'pass', function() if open then hide() else show() end end, false)

-- F11 by default, unless vMenu runs (it owns F11). Then /pass and the pause menu tab only.
-- Key mapping can't be removed once made, so it is only registered while the menu is on.
local keyDone = false
local function bindKey()
    if keyDone or not menuOn() or GetResourceState('vMenu') == 'started' then return end
    keyDone = true
    RegisterKeyMapping(Pass.Settings.command or 'pass', L('pass.key'), 'keyboard', Pass.Settings.key or 'F11')
end
CreateThread(function() Wait(2000); bindKey() end)

-- Pause menu tab, only when bs_pause offers it.
local function addTab()
    if GetResourceState('bs_pause') ~= 'started' then return end
    if not menuOn() then pcall(function() exports.bs_pause:RemovePauseTab('bs_pass') end) return end
    pcall(function()
        exports.bs_pause:AddPauseTab({ id = 'bs_pass', label = L('pass.title'), icon = 'ticket', resource = GetCurrentResourceName(),
            event = 'bs_pass:open', command = Pass.Settings.command or 'pass' })
    end)
end
CreateThread(function() Wait(3000); addTab() end)
AddEventHandler('onClientResourceStart', function(res) if res == 'bs_pause' then Wait(1000); addTab() end end)
AddEventHandler('bs_pass:open', show)

-- F1 change: drop or restore the tab and key, close the menu if it was open
AddEventHandler('bs_config:changed:' .. GetCurrentResourceName(), function()
    if not menuOn() then hide() end
    addTab(); bindKey()
end)

RegisterNUICallback('close', function(_, cb) hide(); cb({}) end)
RegisterNUICallback('claim', function(d, cb) cb(call('bs_pass:claim', d and d.tier) or { ok = false }) end)
RegisterNUICallback('spin', function(_, cb) cb(call('bs_pass:spin') or { ok = false }) end)
RegisterNUICallback('reroll', function(d, cb) cb(call('bs_pass:reroll', d and d.idx) or { ok = false }) end)
RegisterNUICallback('car', function(d, cb) cb(call('bs_pass:car', d and d.id) or { ok = false }) end)
RegisterNUICallback('leaderboard', function(_, cb) cb(call('bs_pass:leaderboard') or { ok = false }) end)
RegisterNUICallback('mailbox', function(_, cb)
    hide()
    cb(call('bs_pass:mailbox') or { ok = false })
end)

RegisterNetEvent('bs_pass:progress', function(p) if open then SendNUIMessage({ action = 'progress', data = p }) end end)
RegisterNetEvent('bs_pass:tierUp', function(t) PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true) end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() and open then SetNuiFocus(false, false) end end)

RegisterNUICallback('acceptChallenge', function(d, cb) cb(call('bs_pass:accept', d and d.id) or { ok = false }) end)
