-- bs_menu - the hub. U opens and closes it. Entries either render a panel inside the hub (stats, skills) or hand off to another resource and close the hub (inventory, settings).

local open = false

-- Opening makes three server round trips (8s each) before `open` is set. `opening` is set on the first frame so pressing U twice cannot open it twice (double blur, double NUI focus).
local opening = false
-- Each async open gets a ticket; closing or panic invalidates it so a late server response cannot reopen a menu the player left.
local openTicket = 0

-- Sanitise the payload before SendNUIMessage. json.encode happily writes `inf` and the NUI parser then rejects it (rapidjson error 3), leaving a blurred screen with no panel.
-- So walk the payload first and drop inf/-inf/NaN, functions, threads, userdata and cycles. Depth-limited, and the dropped paths are printed so the source resource can be fixed.
local MAX_DEPTH = 12

local function scrub(value, seen, depth, path, dropped)
    local t = type(value)

    if t == 'number' then
        -- v ~= v is true only for NaN; the comparisons catch both infinities.
        if value ~= value or value == math.huge or value == -math.huge then
            dropped[#dropped + 1] = path .. ' (' .. tostring(value) .. ')'
            return nil
        end
        return value
    end

    if t == 'string' or t == 'boolean' then return value end

    if t ~= 'table' then
        -- function, thread, userdata: not data, not sendable.
        dropped[#dropped + 1] = path .. ' (' .. t .. ')'
        return nil
    end

    if depth > MAX_DEPTH then
        dropped[#dropped + 1] = path .. ' (too deep)'
        return nil
    end

    if seen[value] then
        dropped[#dropped + 1] = path .. ' (cycle)'
        return nil
    end
    seen[value] = true

    local out = {}
    for k, v in pairs(value) do
        local kt = type(k)
        if kt == 'string' or kt == 'number' then
            local clean = scrub(v, seen, depth + 1, path .. '.' .. tostring(k), dropped)
            if clean ~= nil then out[k] = clean end
        else
            dropped[#dropped + 1] = path .. ' (' .. kt .. ' key)'
        end
    end

    seen[value] = nil
    return out
end

local function send(p)
    if type(p) ~= 'table' then return SendNUIMessage(p) end

    local dropped = {}
    local clean = scrub(p, {}, 0, 'payload', dropped)

    if #dropped > 0 then
        -- Loud, with the exact path: the bad value usually comes from another resource, and the path shows which one.
        print(('^3[BeyondSurvival]^7 (menu) dropped %d unsendable value(s) before '
            .. 'the page: %s. The panel was sent without them.')
            :format(#dropped, table.concat(dropped, ', ')))
    end

    SendNUIMessage(clean)
end

local function setFocus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

local function cancelOpening()
    openTicket = openTicket + 1
    opening = false
    setFocus(false)
    TriggerScreenblurFadeOut(0)
end

local function openMenu(forceTab)
    -- Crafting lives in the inventory's CRAFT tab now (bs_crafting).
    if forceTab == 'craft' and GetResourceState('bs_crafting') == 'started' then
        if pcall(function() exports.bs_crafting:OpenCraft() end) then return end
    end
    if open or opening then return end
    if not exports.bs_core:IsLoaded() then return end
    if IsPedDeadOrDying(PlayerPedId(), true) then return end
    if GetResourceState('bs_inventory') == 'started' and exports.bs_inventory:IsOpen() then return end

    opening = true
    openTicket = openTicket + 1
    local ticket = openTicket
    local function cancelled()
        return ticket ~= openTicket or not opening
    end

    local snapshot = BSB.Await('menu:snapshot', 8000)
    if cancelled() then return end

    -- No server answer: do not open an empty hub with a blur over the world; leave the player where they were.
    if not snapshot then
        opening = false
        return TriggerEvent('bs:ui:notify', {
            type = 'warn',
            message = L('q.no_answer'),
            duration = 3000,
        })
    end

    -- Emotes and clothing are client state, gathered here rather than round-tripped.
    local emotes, clothing = {}, {}
    if GetResourceState('bs_emotes') == 'started' then
        pcall(function()
            emotes   = exports.bs_emotes:EmoteList() or {}
        end)
    end

    -- A focused panel must not wait for unrelated systems; Craft and Build timeouts must never stop the faction panel opening.
    local craft, build, faction
    if forceTab == 'craft' then
        craft = BSB.Await('craft:list', 8000)
        if cancelled() then return end
    elseif forceTab == 'build' and GetResourceState('bs_building') == 'started' then
        build = BSB.Await('build:catalogue', 8000)
        if cancelled() then return end
    elseif forceTab == 'faction' and GetResourceState('bs_factions') == 'started' then
        faction = BSB.Await('factions:panel', 8000)
        if cancelled() then return end
    end

    local tagPrefs = nil
    if GetResourceState('bs_factions') == 'started' then
        pcall(function() tagPrefs = exports.bs_factions:GetTagPrefs() end)
    end

    if cancelled() then return end
    open = true

    if Menu.Settings.dimWorld then
        -- Game-side blur, fades in so it does not snap.
        TriggerScreenblurFadeIn(350)
    end
    local visibleEntries = Menu.Entries
    if forceTab then
        for _, entry in ipairs(Menu.Entries) do
            if entry.id == forceTab then visibleEntries = { entry } break end
        end
    end

    send({
        action   = 'open',
        recipes  = (craft and craft.ok) and craft.recipes or {},
        build    = (build and build.ok) and build or nil,
        entries  = visibleEntries,
        data     = snapshot and snapshot.data or nil,
        emotes   = emotes,
        clothing = clothing,
        faction  = faction or { ok = false, error = L('q.fac_no_answer') },
        -- Tag toggles are a client preference kept by bs_factions (KVP).
        tagPrefs = tagPrefs,
        -- Set only when something other than U opened this (see the N keybind below); picks which rail entry to land on.
        tab      = forceTab,
    })
    setFocus(true)
    opening = false
    TriggerEvent('bs:ui:opened', 'menu')
end

local function closeMenu()
    if not open then
        -- Not open, but something may still be on screen (cancelled open, resource restart). Clear focus and blur.
        cancelOpening()
        return
    end
    open = false
    send({ action = 'close' })
    setFocus(false)
    if Menu.Settings.dimWorld then TriggerScreenblurFadeOut(250) end
    TriggerEvent('bs:ui:closed', 'menu')
end

local function openQuickWheel()
    if open or opening then closeMenu() return end
    CreateThread(function()
        local choice = BSB.Radial({
            title = L('m.survivor'):upper(), blur = false, hold = false,
            items = {
                { id='inventory', label=L('q.inv'), icon='bag', note=L('q.inv_n') },
                { id='craft', label=L('q.craft'), icon='wrench', note=L('q.craft_n') },
                { id='build', label=L('q.build'), icon='scrap', note=L('q.build_n') },
                { id='stats', label=L('m.survivor'), icon='heart', note=L('q.stats_n') },
                { id='skills', label=L('q.skills'), icon='star', note=L('q.skills_n') },
                { id='faction', label=L('q.faction'), icon='key', note=L('q.faction_n') },
                { id='settings', label=L('q.settings'), icon='gear', note=L('q.settings_n') },
            },
        })
        if choice == 'inventory' then exports.bs_inventory:Open()
        elseif choice == 'settings' then exports.bs_inventory:Open('settings')
        elseif choice == 'faction' then openMenu('faction')
        elseif choice then openMenu(choice) end
    end)
end

local function openFactionOperations()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if opening then cancelOpening() return end
    if open then closeMenu() else CreateThread(function() openMenu('faction') end) end
end

RegisterCommand(Menu.Settings.openCommand, function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    -- BSB.Radial waits for the chosen slice and must run in a citizen thread.
    CreateThread(openQuickWheel)
end, false)
-- Old U bindings from the former hub command must open Factions, not F5's wheel.
RegisterCommand('survivormenu', openFactionOperations, false)
RegisterKeyMapping(Menu.Settings.openCommand, L('q.km_quick'), 'keyboard', Menu.Settings.openKey)
RegisterCommand(Menu.Settings.factionCommand, openFactionOperations, false)
RegisterKeyMapping(Menu.Settings.factionCommand, L('q.km_faction'), 'keyboard', Menu.Settings.factionKey)

-- Craft key: lands straight on the Craft panel via forceTab (same hub, same blur and focus handling). Toggles like U.
RegisterCommand(Menu.Settings.craftCommand, function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if opening then
        cancelOpening()
        return
    end
    if open then closeMenu() else CreateThread(function() openMenu('craft') end) end
end, false)
RegisterKeyMapping(Menu.Settings.craftCommand, L('q.km_craft'), 'keyboard', Menu.Settings.craftKey)

RegisterNUICallback('close', function(_, cb) closeMenu(); cb({ ok = true }) end)
-- Squad tab hands off to the standalone squad console (bs_factions).
RegisterNUICallback('openSquadConsole', function(_, cb)
    cb({ ok = true })
    closeMenu()
    if GetResourceState('bs_factions') == 'started' then pcall(function() exports.bs_factions:OpenSquadConsole() end) end
end)

-- Escape hatch: ESC is read from Lua every frame the hub is up, so a broken page can never leave the player stuck with NUI focus.
CreateThread(function()
    while true do
        if open then
            Wait(0)
            -- 322 = ESC, 200 = pause menu.
            if IsControlJustPressed(0, 322) or IsControlJustPressed(0, 200) then
                closeMenu()
            end
        else
            Wait(250)
        end
    end
end)


-- Hand off to another resource: close first so two NUIs never fight for focus, then call the export.
RegisterNUICallback('pick', function(data, cb)
    local entry
    for _, e in ipairs(Menu.Entries) do if e.id == data.id then entry = e end end
    if not entry then return cb({ ok = false }) end

    if entry.kind == 'resource' then
        closeMenu()
        CreateThread(function()
            Wait(80)
            if GetResourceState(entry.resource) ~= 'started' then
                TriggerEvent('bs:ui:notify', { type = 'warn', message = L('m.res_not_running', { name = entry.resource }) })
                return
            end
            local ok, err = pcall(function()
                exports[entry.resource][entry.action](exports[entry.resource], entry.args)
            end)
            if not ok then
                print(('^1[BeyondSurvival]^7 (menu) %s:%s failed: %s'):format(entry.resource, entry.action, err))
            end
        end)
    end

    cb({ ok = true })
end)

-- Building closes the hub: placement happens in the world.
RegisterNUICallback('build', function(data, cb)
    if GetResourceState('bs_building') ~= 'started' then return cb({ ok = false }) end

    closeMenu()
    CreateThread(function()
        Wait(80)
        local result = exports.bs_building:StartPlacing(data.id)
        if not result or not result.ok then
            TriggerEvent('bs:ui:notify', {
                type = 'warn',
                message = (result and result.error) or L('q.cant_build'),
            })
        end
    end)
    cb({ ok = true })
end)

-- Crafting. The bar runs in the hub's NUI so the world stays dimmed.
RegisterNUICallback('craft', function(data, cb)
    CreateThread(function()
        local result = BSB.Await('craft:make', 15000, data.id)

        if not result or not result.ok then
            TriggerEvent('bs:ui:notify', {
                type = 'warn',
                message = (result and result.error) or L('q.cant_make'),
            })
            return cb({ ok = false })
        end

        TriggerEvent('bs:ui:notify', {
            type = 'success',
            title = L('q.made'),
            message = ('%dx %s'):format(result.amount or 1, result.label or L('q.something')),
            duration = 3500,
        })

        if #(result.refunded or {}) > 0 then
            TriggerEvent('bs:ui:notify', {
                type = 'info',
                message = L('q.salvage'),
                duration = 2600,
            })
        end

        -- Materials changed: re-pull the list.
        local craft = BSB.Await('craft:list', 8000)
        cb({ ok = true, recipes = (craft and craft.ok) and craft.recipes or {} })
    end)
end)

-- Playing an emote closes the hub so you can see it.
RegisterNUICallback('emote', function(data, cb)
    if GetResourceState('bs_emotes') ~= 'started' then return cb({ ok = false }) end

    closeMenu()
    CreateThread(function()
        Wait(60)
        local result = exports.bs_emotes:PlayEmote(data.id)
        if not result or not result.ok then
            TriggerEvent('bs:ui:notify', {
                type = 'warn',
                message = (result and result.error) or L('q.cant_here'),
            })
        end
    end)
    cb({ ok = true })
end)

-- Buying a perk. The server decides; the hub only asks.
RegisterNUICallback('skillUnlock', function(data, cb)
    CreateThread(function()
        if GetResourceState('bs_skills') ~= 'started' then
            return cb({ ok = false, error = 'bs_skills is not running' })
        end

        local result = BSB.Await('skills:unlock', 8000, data.tree, data.perk)
        if not result or not result.ok then
            TriggerEvent('bs:ui:notify', {
                type = 'warn',
                message = (result and result.error) or L('q.cant_learn'),
            })
            return cb({ ok = false })
        end

        TriggerEvent('bs:ui:notify', {
            type = 'success',
            title = L('q.learned'),
            message = result.label or data.perk,
            duration = 3500,
        })
        cb({ ok = true })
    end)
end)

-- Spend a point on training a skill directly.
RegisterNUICallback('skillTrain', function(data, cb)
    CreateThread(function()
        local result = BSB.Await('skills:train', 8000, data.tree)
        if not result or not result.ok then
            TriggerEvent('bs:ui:notify', {
                type = 'warn',
                message = (result and result.error) or L('q.cant_train'),
            })
            return cb({ ok = false })
        end

        TriggerEvent('bs:ui:notify', {
            type = 'success',
            title = L('q.trained'),
            message = L('q.now_level', { name = result.label, n = result.level }),
            duration = 3200,
        })
        cb({ ok = true })
    end)
end)

-- Unlearn everything for the points back.
RegisterNUICallback('skillRespec', function(_, cb)
    CreateThread(function()
        local result = BSB.Await('skills:respec', 8000)
        if not result or not result.ok then
            TriggerEvent('bs:ui:notify', {
                type = 'warn',
                message = (result and result.error) or L('q.nothing_unlearn'),
            })
            return cb({ ok = false })
        end

        TriggerEvent('bs:ui:notify', {
            type = 'info',
            message = L('m.sp_returned', { n = result.refunded or 0 }),
        })
        cb({ ok = true })
    end)
end)

-- Faction actions: each is a server round trip followed by a fresh panel, so the menu never disagrees with the server.

local function factionAction(name, cb, ...)
    local args = table.pack(...)

    CreateThread(function()
        local result = BSB.Await(name, 8000, table.unpack(args, 1, args.n))

        if result and result.error then
            TriggerEvent('bs:ui:notify', { type = 'warn', message = result.error, duration = 3200 })
        end

        local panel = BSB.Await('factions:panel', 8000)
        cb({ ok = result and result.ok or false, faction = (panel and panel.ok) and panel or nil })
    end)
end

RegisterNUICallback('factionCreate', function(data, cb)
    factionAction('factions:create', cb, data.name, data.short)
end)

RegisterNUICallback('factionDescription', function(data, cb)
    factionAction('factions:description', cb, data.description)
end)
RegisterNUICallback('factionLogo', function(data, cb)
    factionAction('factions:logo', cb, data.mark, data.color)
end)
RegisterNUICallback('factionAdminUpdate', function(data, cb)
    factionAction('factions:admin:update', cb, data.id, data.description, data.mark, data.color)
end)
RegisterNUICallback('factionAdminAssignVanilla', function(data, cb)
    factionAction('factions:admin:assignVanilla', cb, data.id, tonumber(data.characterId))
end)
RegisterNUICallback('factionBankDeposit', function(data, cb)
    factionAction('factions:bank:deposit', cb, tonumber(data.amount))
end)
RegisterNUICallback('factionBankWithdraw', function(data, cb)
    factionAction('factions:bank:withdraw', cb, tonumber(data.amount))
end)
RegisterNUICallback('factionInvite', function(data, cb)
    factionAction('factions:invite', cb, tonumber(data.target))
end)

RegisterNUICallback('factionJoin', function(data, cb)
    factionAction('factions:join', cb, data.id)
end)

RegisterNUICallback('factionAccept', function(_, cb)
    factionAction('factions:accept', cb)
end)

RegisterNUICallback('factionKick', function(data, cb)
    factionAction('factions:kick', cb, tonumber(data.target))
end)

RegisterNUICallback('factionPromote', function(data, cb)
    factionAction('factions:promote', cb, tonumber(data.target), data.rank)
end)

-- by character id, works for offline members
RegisterNUICallback('factionPromoteChar', function(data, cb)
    factionAction('factions:promoteChar', cb, { charId = tonumber(data.charId), rank = data.rank })
end)

RegisterNUICallback('factionKickChar', function(data, cb)
    factionAction('factions:kickChar', cb, { charId = tonumber(data.charId) })
end)

RegisterNUICallback('factionLeave', function(_, cb)
    factionAction('factions:leave2', cb)
end)

-- Name tags over squad and faction mates. Local preference only; goes to bs_factions' client, not the server.
RegisterNUICallback('factionTagToggle', function(data, cb)
    local prefs = nil
    if GetResourceState('bs_factions') == 'started' then
        pcall(function() prefs = exports.bs_factions:SetTagPref(data and data.kind, data and data.on == true) end)
    end
    cb({ ok = prefs ~= nil, tagPrefs = prefs })
end)

RegisterNUICallback('factionDisband', function(_, cb)
    factionAction('factions:disband', cb)
end)

RegisterNUICallback('refresh', function(_, cb)
    CreateThread(function()
        local snapshot = BSB.Await('menu:snapshot', 8000)
        cb(snapshot or { ok = false })
    end)
end)

-- World behind the hub: a NUI page cannot blur the game, so use GTA's own blur (like the pause menu). The world stays visible and softened.
CreateThread(function()
    while true do
        if open then
            Wait(0)
            -- No DrawRect. The CSS vignette and the game blur do the work.
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 21, true)
        else
            Wait(250)
        end
    end
end)

--- One menu at a time - see the note in bs_inventory.
AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'menu' and open then closeMenu() end
end)

AddEventHandler('bs:ui:requestClose', function(who)
    if who ~= 'menu' and open then closeMenu() end
end)

-- /refreshui hard reset. Also clears `opening` so a panic mid-open does not leave the double-press guard stuck.
AddEventHandler('bs:ui:panic', function()
    open = false
    cancelOpening()
    send({ action = 'close' })
    setFocus(false)
    TriggerScreenblurFadeOut(0)
end)

AddEventHandler('bs:hook:player:unloaded', closeMenu)
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(0)
    -- closeMenu() will never run now; tell the listeners ourselves.
    if open then TriggerEvent('bs:ui:closed', 'menu') end
end)

--- Dying with the hub open must not strand you either.
CreateThread(function()
    while true do
        Wait(500)
        if open and IsPedDeadOrDying(PlayerPedId(), true) then closeMenu() end
    end
end)

--------------------------------------------------------------------------------
-- Faction hub: thin pass-through to the faction/squad/sanction callbacks.
-- Only names in this list get through, so the page can't call anything else.
--------------------------------------------------------------------------------
local HUB_FX = {}
for _, n in ipairs({
    'squad:get', 'squad:create', 'squad:invite', 'squad:accept', 'squad:decline', 'squad:leave',
    'squad:kick', 'squad:setRank', 'squad:saveRanks', 'squad:rename', 'squad:disband', 'squad:transfer',
    'factions:roster', 'factions:bank:info', 'factions:perms:get', 'factions:perms:set', 'factions:bank:setCap',
    'factions:ranks:create', 'factions:ranks:rename', 'factions:ranks:move', 'factions:ranks:delete', 'factions:panel',
    'sanctions:templates', 'sanctions:list', 'sanctions:issue', 'sanctions:lift',
    'jail:get', 'jail:setOrigin', 'jail:setExit', 'jail:addCell', 'jail:removeCell', 'jail:release',
    'factions:progress:get', 'factions:missions:get', 'factions:missions:deliver', 'factions:skills:get',
    'factions:skills:spend', 'factions:cosmetics:set', 'factions:donate', 'factions:rosterAll',
    -- faction jobs (bs_jobs)
    'jobs:overview', 'jobs:apply', 'jobs:withdraw', 'jobs:leave', 'jobs:approve', 'jobs:kick', 'jobs:pick', 'jobs:placeStation',
    'jobs:board', 'jobs:take', 'jobs:abandon', 'jobs:turnin', 'jobs:scores', 'jobs:kid:pay', 'jobs:kid:ransom', 'jobs:kid:release',
    -- declared raids (bs_building sv_raids.lua)
    'raids:get', 'raids:declare',
    -- staff console (server re-checks the ACE on every one)
    'factions:admin:overview', 'factions:admin:detail', 'factions:admin:progress', 'factions:admin:points',
    'factions:admin:skill', 'factions:admin:reputation', 'factions:admin:treasury', 'factions:admin:addMember',
    'factions:admin:removeMember', 'factions:admin:setRank', 'factions:admin:transfer', 'factions:admin:disband',
    'factions:admin:reroll', 'factions:admin:completeMission', 'factions:admin:resetCooldowns',
    'factions:admin:flagTeleport', 'factions:admin:flagRemove', 'factions:admin:identity', 'factions:admin:clearBriefing',
}) do HUB_FX[n] = true end

local function clean(v)
    return scrub(v, {}, 0, 'cb', {}) or { ok = false }
end

RegisterNUICallback('fx', function(data, cb)
    local name = type(data) == 'table' and data.name or nil
    if not HUB_FX[name] then return cb({ ok = false, error = 'Not available.' }) end
    local payload = type(data.args) == 'table' and data.args or {}
    CreateThread(function()
        local r = BSB.Await(name, 8000, payload)
        if type(r) ~= 'table' then r = { ok = false, error = L('q.srv_no_answer') } end
        cb(clean(r))
    end)
end)

-- Settings tab: all local prefs, owned by bs_factions (tags, blips) and bs_ui (party HUD).
local function hubPrefs()
    local out = { ok = true }
    if GetResourceState('bs_factions') == 'started' then
        pcall(function() out.tags = exports.bs_factions:GetTagPrefs() end)
        pcall(function()
            local b = exports.bs_factions:GetSquadBlips()
            out.blips = not (b == false or b == 2)
        end)
    end
    if GetResourceState('bs_ui') == 'started' then
        pcall(function() out.partyhud = exports.bs_ui:GetPartyHudPref() ~= 2 end)
    end
    -- Combat feedback (health bars, hit markers) - everyone, owned by bs_zombies.
    if GetResourceState('bs_zombies') == 'started' then
        pcall(function() out.fx = exports.bs_zombies:GetFxOptions() end)
    end
    return out
end

RegisterNUICallback('hubPrefs', function(_, cb) cb(clean(hubPrefs())) end)

RegisterNUICallback('hubPrefSet', function(data, cb)
    local key = type(data) == 'table' and tostring(data.key or '') or ''
    local value = type(data) == 'table' and data.value or nil
    if key == 'master' or key == 'squad' or key == 'faction' or key == 'self' or key == 'range' then
        pcall(function() exports.bs_factions:SetTagPref(key, value) end)
    elseif key == 'partyhud' then
        pcall(function() exports.bs_ui:SetPartyHudPref(value == true and 1 or 2) end)
    elseif key == 'blips' then
        pcall(function() exports.bs_factions:SetSquadBlips(value == true) end)
    elseif key:sub(1, 3) == 'fx:' then
        pcall(function() exports.bs_zombies:SetFxOption(key:sub(4), value == true) end)
    end
    cb(clean(hubPrefs()))
end)

-- Squad changes push straight into the open page; nothing while closed.
RegisterNetEvent('bs:squad:sync', function(payload)
    if not open then return end
    send({ action = 'squadSync', squad = type(payload) == 'table' and payload.squad or false })
end)

exports('Open', function() CreateThread(openMenu) end)
exports('Close', closeMenu)
exports('IsOpen', function() return open end)


