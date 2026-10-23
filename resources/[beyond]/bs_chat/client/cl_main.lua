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

local function send(payload)
    SendNUIMessage(payload)
end

-- Opening and closing

local function setOpen(state)
    if Box.open == state then return end
    Box.open = state

    SetNuiFocus(state, state)
    send({ action = state and 'open' or 'close' })

    -- No screen blur on purpose: you type in chat while something may be walking toward you.
end

RegisterNUICallback('close', function(_, cb)
    setOpen(false)
    cb({ ok = true })
end)

-- Typed input: a slash goes to the engine's command dispatcher, anything else goes to the server as speech. Never both.
RegisterNUICallback('send', function(data, cb)
    cb({ ok = true })

    local text = tostring(data and data.text or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if text == '' then return end

    if text:sub(1, 1) == '/' then
        local command = text:sub(2)
        if command ~= '' then ExecuteCommand(command) end
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
local function syncSuppressed()
    local blocked = next(blockingPanels) ~= nil
    if Box.suppressed == blocked then return end
    Box.suppressed = blocked
    if blocked and Box.open then setOpen(false) end
    send({ action = 'visible', visible = not blocked })
end

AddEventHandler('bs:ui:opened', function(panel)
    if panel and panel ~= 'chat' then
        blockingPanels[panel] = true
        syncSuppressed()
    end
end)

AddEventHandler('bs:ui:closed', function(panel)
    if panel then blockingPanels[panel] = nil else blockingPanels = {} end
    syncSuppressed()
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

local function addMessage(payload)
    if type(payload) == 'string' then payload = { args = { payload } } end
    if type(payload) ~= 'table' then return end

    local args = payload.args
    if type(args) ~= 'table' then args = { tostring(args or '') } end

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
AddEventHandler('chat:addMessage', addMessage)

RegisterNetEvent('chat:clear')
AddEventHandler('chat:clear', function() send({ action = 'clear' }) end)

-- Suggestion list events; resources register commands with these at start, so existing /commands keep showing up.
local function pushSuggestions()
    local list = {}
    for name, entry in pairs(Box.suggestions) do
        list[#list + 1] = { name = name, help = entry.help, params = entry.params }
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
AddEventHandler('chat:addSuggestion', addSuggestion)

local function removeSuggestion(name)
    if type(name) ~= 'string' then return end
    if name:sub(1, 1) ~= '/' then name = '/' .. name end
    Box.suggestions[name] = nil
    pushSuggestions()
end

RegisterNetEvent('chat:removeSuggestion')
AddEventHandler('chat:removeSuggestion', removeSuggestion)

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

AddEventHandler('bs:hook:player:unloaded', function()
    setOpen(false)
    send({ action = 'clear' })
end)

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
    pushConfig()
    pushStyle()

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
