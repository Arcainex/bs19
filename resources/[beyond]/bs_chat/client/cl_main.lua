-- bs_chat - replacement for the stock chat resource. Stock chat lives in the FiveM artifacts, which are replaced on every artifact update, so restyling it would silently revert. Use this instead (remove `ensure chat` from server.cfg).
-- It owns command routing, the suggestion list, and the chat:addMessage event used by other resources.

-- Named `Box`, not `Chat`: `Chat` is the global from config/config_chat.lua, and a local of that name would shadow it and make every Chat.Settings read nil.
local Box = {
    open = false,
    -- Commands offered while the line starts with a slash. Populated by chat:addSuggestion like the stock resource.
    suggestions = {},
    suppressed = false, -- another full interface owns the screen
}

local function settings()
    return (Chat and Chat.Settings) or {}
end

-- One visible line in F8 when something goes wrong, at most one per cause every 5 s so a loop cannot flood the console.
local lastLogged = {}
local function chatLog(key, text)
    local now = GetGameTimer()
    if lastLogged[key] and now - lastLogged[key] < 5000 then return end
    lastLogged[key] = now
    print(('^1[bs_chat] %s^7'):format(text))
end

-- Sends to the page; a bad payload is logged instead of killing the calling handler.
local function send(payload)
    local ok, err = pcall(SendNUIMessage, payload)
    if not ok then chatLog('send', 'SendNUIMessage failed (' .. tostring(payload and payload.action) .. '): ' .. tostring(err)) end
end

-- Runs a handler so an error is logged with its name and never leaves the chat half-updated.
local function safe(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then chatLog('handler:' .. name, name .. ' failed: ' .. tostring(err)) end
    end
end

-- Opening and closing

-- keepFocus: another panel just opened and owns the focus now, so do not take it away from it.
local function setOpen(state, keepFocus)
    if Box.open == state then return end
    Box.open = state
    Box.openedAt = GetGameTimer()

    if state or not keepFocus then SetNuiFocus(state, state) end
    send({ action = state and 'open' or 'close' })

    -- No screen blur on purpose: you type in chat while something may be walking toward you.
end

RegisterNUICallback('close', function(_, cb)
    -- A page that thinks it is closed but Lua still open (or the reverse) must end up shut and unfocused either way.
    if Box.open then setOpen(false) else SetNuiFocus(false, false) end
    cb({ ok = true })
end)

-- The page reports its own script errors so F8 shows why a chat line or the box misbehaved.
RegisterNUICallback('error', function(data, cb)
    cb({ ok = true })
    chatLog('js', 'page error: ' .. tostring(data and data.msg or '?'))
end)

-- Page heartbeat, see the watchdog below.
local lastBeat = 0
RegisterNUICallback('alive', function(_, cb)
    lastBeat = GetGameTimer()
    cb({ ok = true })
end)

-- Typed input: a slash goes to the engine's command dispatcher, anything else goes to the server as speech. Never both.
RegisterNUICallback('send', function(data, cb)
    cb({ ok = true })

    local text = tostring(data and data.text or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return end

    if text:sub(1, 1) == '/' then
        local command = text:sub(2)
        -- A failing command must not take the chat callback down with it.
        if command ~= '' then
            local ok, err = pcall(ExecuteCommand, command)
            if not ok then chatLog('cmd', 'command failed: ' .. tostring(err)) end
        end
        return
    end

    TriggerServerEvent('bs:chat:say', text:sub(1, settings().maxLength or 220))
end)

-- The key

-- T via RegisterKeyMapping, rebindable in the pause menu.
-- Do not rename the command later: FiveM applies a key mapping default once per command name and stores the binding in the player's profile, so changing the default does nothing for existing players.
RegisterCommand('bs_chat_open', function()
    if Box.open or Box.suppressed then return end
    if IsPauseMenuActive() then return end
    setOpen(true)
end, false)

RegisterKeyMapping('bs_chat_open', L('chat.key_open'), 'keyboard', 'T')

-- Chat must not sit on top of a full interface. Menus publish bs:ui:opened / bs:ui:closed, so no per-menu list is needed.
local blockingPanels = {}

-- Full-screen states that never take NUI focus. Everything else that blocks chat is a menu and holds focus while open.
local focusless = { drone = true, cinecam = true }
local function allFocusless()
    for panel in pairs(blockingPanels) do
        if not focusless[panel] then return false end
    end
    return true
end

local function syncSuppressed()
    local blocked = next(blockingPanels) ~= nil
    if Box.suppressed == blocked then return end
    Box.suppressed = blocked
    -- The panel that just opened owns NUI focus, so chat only lets go of it when that panel takes none (drone, camera).
    if blocked and Box.open then setOpen(false, not allFocusless()) end
    send({ action = 'visible', visible = not blocked })
end

AddEventHandler('bs:ui:opened', safe('ui:opened', function(panel)
    if panel and panel ~= 'chat' then
        blockingPanels[panel] = true
        syncSuppressed()
    end
end))

AddEventHandler('bs:ui:closed', safe('ui:closed', function(panel)
    if panel then blockingPanels[panel] = nil else blockingPanels = {} end
    syncSuppressed()
end))

-- A resource that stops or crashes never sends its bs:ui:closed, which left the chat hidden for good. Forget its panel.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then return end
    local stale = false
    for panel in pairs(blockingPanels) do
        if resource == panel or resource == 'bs_' .. panel then
            blockingPanels[panel] = nil
            stale = true
        end
    end
    if stale then
        chatLog('stop:' .. resource, resource .. ' stopped while its panel was open, chat restored')
        syncSuppressed()
    end
end)

-- Events other resources already use

-- chat:addMessage, same name and shape as stock:
--   { args = { 'tag', 'body' }, color = { r, g, b } }, { args = { 'line' } }, or a bare string.
-- `templateId` and `multiline` are accepted and ignored so third-party callers do not error.
-- Viewer choice: show other players' VIP chat badges/colours. KVP 0/1 = on, 2 = off.
local showVip = GetResourceKvpInt('bs_chat:vipStyles') ~= 2
exports('GetVipStyles', function() return showVip end)
exports('SetVipStyles', function(on)
    showVip = on and true or false
    SetResourceKvpInt('bs_chat:vipStyles', showVip and 1 or 2)
    return showVip
end)
RegisterCommand('vipchat', function()
    showVip = not showVip
    SetResourceKvpInt('bs_chat:vipStyles', showVip and 1 or 2)
    TriggerEvent('bs:ui:notify', { type = 'info', message = showVip and L('chat.vip_shown') or L('chat.vip_hidden'), duration = 2400 })
end, false)

local function hexOk(v) return type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') ~= nil end

-- Flood guard: a runaway loop elsewhere spamming chat:addMessage would jam the page. Past 40 lines in one second the rest are dropped.
local floodAt, floodN = 0, 0

local MAX_ARGS, MAX_ARG_LEN = 8, 600

local function addMessage(payload)
    if type(payload) == 'string' then payload = { args = { payload } } end
    if type(payload) ~= 'table' then return end

    local now = GetGameTimer()
    if now - floodAt > 1000 then floodAt, floodN = now, 0 end
    floodN = floodN + 1
    if floodN > 40 then
        chatLog('flood', 'more than 40 chat messages in one second, dropping the extra ones')
        return
    end

    local args = payload.args
    if type(args) ~= 'table' then args = { tostring(args or '') } end

    -- Plain short strings only: a function or huge value in args would make the NUI message fail or stall.
    local clean = {}
    for i = 1, math.min(#args, MAX_ARGS) do
        clean[i] = tostring(args[i]):sub(1, MAX_ARG_LEN)
    end
    if #clean == 0 then return end
    args = clean

    local colour = payload.color or payload.colour
    if type(colour) ~= 'table' or #colour < 3 then colour = nil end

    send({
        action  = 'message',
        args    = args,
        colour  = colour,
        channel = payload.channel,
        vip     = (showVip and type(payload.vip) == 'table') and {
            badge    = type(payload.vip.badge) == 'string' and payload.vip.badge:sub(1, 16) or nil,
            badgeHex = hexOk(payload.vip.badgeHex) and payload.vip.badgeHex or nil,
            nameHex  = hexOk(payload.vip.nameHex) and payload.vip.nameHex or nil,
        } or nil,
    })
end

-- RegisterNetEvent(name, handler) already registers the handler, so adding AddEventHandler(name, handler) runs it twice (duplicate messages). Use the declaration form plus a single AddEventHandler.
RegisterNetEvent('chat:addMessage')
AddEventHandler('chat:addMessage', safe('chat:addMessage', addMessage))

RegisterNetEvent('chat:clear')
AddEventHandler('chat:clear', safe('chat:clear', function() send({ action = 'clear' }) end))

-- Suggestion list events; resources register commands with these at start, so existing /commands keep showing up.
local function pushSuggestions()
    local list = {}
    for name, entry in pairs(Box.suggestions) do
        list[#list + 1] = { name = name, help = type(entry.help) == 'string' and entry.help or nil, params = entry.params }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    send({ action = 'suggestions', list = list })
end

local function addSuggestion(name, help, params)
    if type(name) ~= 'string' or name == '' then return end
    if name:sub(1, 1) ~= '/' then name = '/' .. name end

    -- `params` is a list of { name, help }; flattened to a string here so the page does not need to know the shape.
    local rendered = ''
    if type(params) == 'table' then
        for _, p in ipairs(params) do
            rendered = rendered .. (' [%s]'):format(tostring(p.name or '?'))
        end
    end

    Box.suggestions[name] = { help = help, params = rendered }
    pushSuggestions()
end

RegisterNetEvent('chat:addSuggestion')
AddEventHandler('chat:addSuggestion', safe('chat:addSuggestion', addSuggestion))

local function removeSuggestion(name)
    if type(name) ~= 'string' then return end
    if name:sub(1, 1) ~= '/' then name = '/' .. name end
    Box.suggestions[name] = nil
    pushSuggestions()
end

RegisterNetEvent('chat:removeSuggestion')
AddEventHandler('chat:removeSuggestion', safe('chat:removeSuggestion', removeSuggestion))

-- Accepted and ignored (see addMessage).
RegisterNetEvent('chat:addTemplate')
AddEventHandler('chat:addTemplate', function() end)

-- Startup and teardown

-- The page asks for its settings when ready, instead of a fixed Wait(500) that raced the page reload (see post('ready') in html/index.html).
-- pushReady is called from the NUI callback at the bottom of this file, below pushStyle: pushStyle is a file-local and a call above its declaration is a nil global at runtime.
local function pushConfig()
    send({ action = 'config', fadeAfter = settings().fadeAfter or 12000 })
end

-- Always release NUI focus on resource stop; a stuck focus leaves the player unable to move or look.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)

AddEventHandler('bs:hook:player:unloaded', safe('player:unloaded', function()
    setOpen(false)
    send({ action = 'clear' })
end))

-- Readability and visibility

-- Two separate settings: the backdrop (legibility over bright scenes) and the mode (whether chat shows when nobody is talking). Per client, persisted through KVP.
local KVP_MODE = 'bs_chat_mode'
local KVP_BACKDROP = 'bs_chat_backdrop'

-- 'fade' (default), 'always' or 'hidden'
local mode = GetResourceKvpString(KVP_MODE) or 'fade'
-- 1 = on, 2 = off. GetResourceKvpInt returns 0 for a missing key, so 0 means never set = on.
local backdrop = GetResourceKvpInt(KVP_BACKDROP) ~= 2

-- Background opacity in percent, 0-100 in steps of 5. Stored as a string so a missing key reads as nil, not 0.
local KVP_BG_OPACITY = 'bs_chat_bg_opacity'
local DEFAULT_BG_OPACITY = 20
local function clampOpacity(v)
    v = tonumber(v)
    if not v then return nil end
    return math.floor(math.max(0, math.min(100, v)) / 5 + 0.5) * 5
end
local bgOpacity = clampOpacity(GetResourceKvpString(KVP_BG_OPACITY)) or DEFAULT_BG_OPACITY

local function pushStyle()
    send({ action = 'style', mode = mode, backdrop = backdrop, opacity = bgOpacity })
end

-- Pushed from here, below pushStyle's definition: pushStyle is a file-local and a call above it is a nil global at runtime.
-- Both halves of the page setup are sent in answer to its own ready signal rather than on a timer.
RegisterNUICallback('ready', function(_, cb)
    lastBeat = GetGameTimer()
    pushConfig()
    pushStyle()
    pushSuggestions() -- a reloaded page starts with an empty command list

    -- A fresh page means a shut box, whatever Lua thinks: the page can reload on its own while Box.open is still true, which would make T a no-op. Trust the page and drop focus too.
    if Box.open then
        Box.open = false
        SetNuiFocus(false, false)
    end

    -- Suppression is live state; re-send it so a page that reloaded behind an open panel stays hidden.
    send({ action = 'visible', visible = not Box.suppressed })

    cb({ ok = true })
end)

RegisterCommand('chat', function(_, args)
    local what = tostring(args and args[1] or ''):lower()

    if what == 'backdrop' then
        backdrop = not backdrop
        SetResourceKvpInt(KVP_BACKDROP, backdrop and 1 or 2)
        pushStyle()
        TriggerEvent('bs:ui:notify', { type = 'info', duration = 3000,
            message = backdrop and L('chat.bd_on') or L('chat.bd_off') })
        return
    end

    if what == 'fade' or what == 'always' or what == 'hidden' then
        mode = what
        -- Use SetResourceKvp to write a string; SetResourceKvpString does not exist (nil global, errors only when the setting is first changed).
        SetResourceKvp(KVP_MODE, mode)
        pushStyle()
        TriggerEvent('bs:ui:notify', { type = 'info', duration = 3500,
            message = L('chat.mode_' .. mode) })
        return
    end

    TriggerEvent('bs:ui:notify', { type = 'info', duration = 7000,
        message = 'chat fade | chat always | chat hidden | chat backdrop\n'
               .. L('chat.now', { mode = mode, bd = backdrop and L('chat.on') or L('chat.off') }) })
end, false)

-- Published for the U-menu Settings page. Local KVP preferences only, not server-owned data.
exports('GetDisplaySettings', function()
    return { chatMode = mode, chatBackdrop = backdrop, chatBgOpacity = bgOpacity }
end)

exports('ApplyDisplaySettings', function(patch)
    if type(patch) ~= 'table' then return false end
    local changed = false
    local requested = tostring(patch.chatMode or ''):lower()
    if requested == 'fade' or requested == 'always' or requested == 'hidden' then
        mode = requested
        SetResourceKvp(KVP_MODE, mode)
        changed = true
    end
    if type(patch.chatBackdrop) == 'boolean' then
        backdrop = patch.chatBackdrop
        SetResourceKvpInt(KVP_BACKDROP, backdrop and 1 or 2)
        changed = true
    end
    local op = clampOpacity(patch.chatBgOpacity)
    if op then
        bgOpacity = op
        SetResourceKvp(KVP_BG_OPACITY, tostring(op))
        changed = true
    end
    if changed then pushStyle() end
    return changed
end)

exports('IsOpen', function() return Box.open end)

-- Watchdog
-- Two things go wrong silently: Lua thinks the box is open but NUI focus is gone (another resource took it), and the page stops answering. Both are repaired here and logged.
CreateThread(function()
    local noFocusSince, noBeatLogged = nil, 0
    while true do
        Wait(500)
        local now = GetGameTimer()

        -- Box open but nobody holds focus: close it so T works again. Grace period covers the frame between SetNuiFocus and the engine reporting it.
        if Box.open and not IsNuiFocused() and now - (Box.openedAt or 0) > 1500 then
            chatLog('focus', 'NUI focus was lost while the chat was open (another resource took it), closing the box')
            setOpen(false)
        end

        -- Suppressed by a panel that is no longer there: menus hold focus, so ten seconds with no focus and no focus-less panel means the bookkeeping drifted.
        if Box.suppressed and not IsNuiFocused() and not Box.open and not allFocusless() then
            noFocusSince = noFocusSince or now
            if now - noFocusSince > 10000 then
                chatLog('stale', 'chat was hidden by a panel that never closed, restoring it')
                blockingPanels = {}
                syncSuppressed()
                noFocusSince = nil
            end
        else
            noFocusSince = nil
        end

        -- Page silent for 12 s (it beats every 3 s): reload it. The page answers with `ready`, which restores settings and suggestions.
        if lastBeat > 0 and now - lastBeat > 12000 and now - noBeatLogged > 12000 then
            noBeatLogged = now
            chatLog('beat', 'chat page stopped responding, reloading it')
            if Box.open then setOpen(false) end
            send({ action = 'reload' })
        end
    end
end)
