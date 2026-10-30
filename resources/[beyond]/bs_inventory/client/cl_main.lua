-- bs_inventory - opens the inventory, relays drag-and-drop moves to the server and hosts the Settings panel. The client holds no authority; it renders what the server last sent.

local open = false
local opening = false
local state = { player = nil, container = nil }
local tradeState = nil
local tradeOnly = false
local openToken = 0
local portraitReady = false
local closeInventory

local function send(p) SendNUIMessage(p) end

-- Item names and descriptions in the player's language: locale keys item.<name> and
-- item.<name>.desc, with the config label as the English fallback.
local function itemText(name, suffix, fallback)
    local key = 'item.' .. tostring(name) .. (suffix or '')
    local text = L(key)
    if text ~= key then return text end
    return fallback
end

function ItemLabel(name)
    local def = Items.Definitions[name]
    return itemText(name, nil, def and def.label or tostring(name))
end

function ItemDescription(name)
    local def = Items.Definitions[name]
    return itemText(name, '.desc', def and (def.description or def.desc) or nil)
end

exports('ItemLabel', ItemLabel)
exports('ItemDescription', ItemDescription)

local function setFocus(on)
    SetNuiFocus(on, on)
    SetNuiFocusKeepInput(false)
end

-- Opening

-- Preferences owned by other resources, shown in the Settings tab next to bs_ui's HUD values.
-- Each one reads and writes through that resource's export, so its chat command stays in sync.
local function started(res) return GetResourceState(res) == 'started' end

-- Container labels sent as 'loc:<key>' are resolved in the player's language here.
local function ctLabel(l)
    if type(l) == 'string' and l:sub(1, 4) == 'loc:' then return L(l:sub(5)) end
    return l
end

local extraSettings = {
    -- Saved per account by bs_core; the change comes back on the bs_lang state bag.
    language = {
        get = function() return BSLocale.Lang() end,
        set = function(v) BSLocale.Set(v) end,
    },
    chatMode = {
        get = function() if started('bs_chat') then return exports.bs_chat:GetDisplaySettings().chatMode end end,
        set = function(v) exports.bs_chat:ApplyDisplaySettings({ chatMode = v }) end,
    },
    chatBackdrop = {
        get = function() if started('bs_chat') then return exports.bs_chat:GetDisplaySettings().chatBackdrop end end,
        set = function(v) exports.bs_chat:ApplyDisplaySettings({ chatBackdrop = v == true }) end,
    },
    chatBgOpacity = {
        get = function() if started('bs_chat') then return exports.bs_chat:GetDisplaySettings().chatBgOpacity end end,
        set = function(v) exports.bs_chat:ApplyDisplaySettings({ chatBgOpacity = tonumber(v) }) end,
    },
    uiScale = {
        get = function() if started('bs_ui') then return exports.bs_ui:GetUiScale() end end,
        set = function(v) exports.bs_ui:SetUiScale(tonumber(v) or 0) end,
    },
    hotbarAlways = {
        get = function() return exports[GetCurrentResourceName()]:HotbarAlwaysVisible() end,
        set = function(v) exports[GetCurrentResourceName()]:SetHotbarAlwaysVisible(v == true) end,
    },
    missionTracker = {
        get = function() if started('bs_traders') then return exports.bs_traders:TrackerShown() end end,
        set = function(v) exports.bs_traders:SetTrackerShown(v == true) end,
    },
    safeZoneMarkers = {
        get = function() if started('bs_zombies') then return exports.bs_zombies:SafeZoneMarkersShown() end end,
        set = function(v) exports.bs_zombies:SetSafeZoneMarkersShown(v == true) end,
    },
    damageNumbers = {
        get = function() if started('bs_zombies') then return exports.bs_zombies:DamageNumbersShown() end end,
        set = function(v) exports.bs_zombies:SetDamageNumbersShown(v == true) end,
    },
    carHud = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetDashHudSettings().on end end,
        set = function(v) exports.bs_vehicles:ApplyDashHudSettings({ on = v == true }) end,
    },
    carHudUnit = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetDashHudSettings().unit end end,
        set = function(v) exports.bs_vehicles:ApplyDashHudSettings({ unit = v }) end,
    },
    carHudScale = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetDashHudSettings().scale end end,
        set = function(v) exports.bs_vehicles:ApplyDashHudSettings({ scale = v }) end,
    },
    carHudSide = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetDashHudSettings().side end end,
        set = function(v) exports.bs_vehicles:ApplyDashHudSettings({ side = v }) end,
    },
    carHudStyle = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetDashHudSettings().style end end,
        set = function(v) exports.bs_vehicles:ApplyDashHudSettings({ style = v }) end,
    },
    carHudOpacity = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetDashHudSettings().opacity end end,
        set = function(v) exports.bs_vehicles:ApplyDashHudSettings({ opacity = tonumber(v) }) end,
    },
    wheelThrottle = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetCruiseSettings().wheelThrottle end end,
        set = function(v) exports.bs_vehicles:ApplyCruiseSettings({ wheelThrottle = v == true }) end,
    },
    throttleUi = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetCruiseSettings().throttleUi end end,
        set = function(v) exports.bs_vehicles:ApplyCruiseSettings({ throttleUi = v == true }) end,
    },
    moveHud = {
        get = function() if started('bs_ui') then return exports.bs_ui:GetMoveHud() end end,
        set = function(v) exports.bs_ui:SetMoveHud(v == true) end,
    },
    radioVolume = {
        get = function() if started('bs_radio') then local ok, r = pcall(function() return exports.bs_radio:GetVolume() end); if ok then return r end end end,
        set = function(v) if started('bs_radio') then pcall(function() exports.bs_radio:SetVolume(tonumber(v)) end) end end,
    },
    camSmooth = {
        get = function() return exports[GetCurrentResourceName()]:GetCameraSettings().camSmooth end,
        set = function(v) exports[GetCurrentResourceName()]:SetCameraSetting('camSmooth', v) end,
    },
    camSmoothAmount = {
        get = function() return exports[GetCurrentResourceName()]:GetCameraSettings().camSmoothAmount end,
        set = function(v) exports[GetCurrentResourceName()]:SetCameraSetting('camSmoothAmount', v) end,
    },
    camSmoothAim = {
        get = function() return exports[GetCurrentResourceName()]:GetCameraSettings().camSmoothAim end,
        set = function(v) exports[GetCurrentResourceName()]:SetCameraSetting('camSmoothAim', v) end,
    },
    camSway = {
        get = function() return exports[GetCurrentResourceName()]:GetCameraSettings().camSway end,
        set = function(v) exports[GetCurrentResourceName()]:SetCameraSetting('camSway', v) end,
    },
    camFov = {
        get = function() return exports[GetCurrentResourceName()]:GetCameraSettings().camFov end,
        set = function(v) exports[GetCurrentResourceName()]:SetCameraSetting('camFov', v) end,
    },
    camChase = {
        get = function() return exports[GetCurrentResourceName()]:GetCameraSettings().camChase end,
        set = function(v) exports[GetCurrentResourceName()]:SetCameraSetting('camChase', v) end,
    },
    -- read only: lets the page lock the VIP HUD styles and palettes (open when the VIP system is off)
    hudVip = {
        get = function() if started('bs_ui') then return exports.bs_ui:UiChoices().vip end end,
        set = function() end,
    },
    -- read only: lets the page lock the VIP dash styles
    carHudVip = {
        get = function() if started('bs_vehicles') then return exports.bs_vehicles:GetDashHudSettings().vip end end,
        set = function() end,
    },
}

-- A stopped resource just leaves its controls unselected.
local function collectSettings()
    local out = {}
    if started('bs_ui') then
        for key, value in pairs(exports.bs_ui:GetHudSettings() or {}) do out[key] = value end
    end
    for key, handler in pairs(extraSettings) do
        local ok, value = pcall(handler.get)
        if ok and value ~= nil then
            out[key] = value
        end
    end
    return out
end

--- @param tab string|nil  'carry' (default) or 'settings'
local function openInventory(tab)
    if open or opening then return end
    if not exports.bs_core:IsLoaded() then return end
    if IsPedDeadOrDying(PlayerPedId(), true) then return end

    opening = true
    local data = BSB.Await('inventory:open', 8000)
    opening = false
    if not data or not data.ok then return end

    open = true
    tradeOnly = tab == 'trade'
    openToken = openToken + 1
    portraitReady = false
    local token = openToken
    state.player = data.player

    -- Game-side blur: a NUI page cannot blur the world behind it. Not GTA's global screen blur, which also blurs the player ped; the portrait camera's depth of field keeps the ped sharp.
    TriggerScreenblurFadeOut(0)

    -- Start the portrait only after the browser confirms it painted, so a failed NUI init cannot strand the player in a blank camera.

    -- The map is its own menu (bs_ui field map, M key), not a tab here - see bs_ui/client/cl_fieldmap.lua.

    send({
        action = 'open',
        tab = tab or 'carry',
        player = data.player,
        trade = tradeState,
        grid = data.grid,
        settings = collectSettings(),
        -- HUD styles and menu palettes (with swatches), owned by bs_ui
        choices = (function()
            if not started('bs_ui') then return nil end
            local ok, v = pcall(function() return exports.bs_ui:UiChoices() end)
            return ok and v or nil
        end)(),

        -- Screen-filter presets, sent as data. bs_ui owns the list (UI.Filters) so a new preset shows up here and in the cinematic camera picker.
        filters = (GetResourceState('bs_ui') == 'started')
            and (function()
                local ok, list = pcall(function() return exports.bs_ui:FilterPresets() end)
                return ok and list or nil
            end)() or nil,
        -- Quick bar is drawn in the bag too and must be right on open. cl_hotbar.lua owns the data; this is a copy.
        hotbar = exports.bs_inventory:Slots(),

        -- Stats panel: a snapshot taken on open, not a live feed. Health and armour come from the ped since the engine owns them.
        stats = (function()
            local ok, d = pcall(function() return exports.bs_core:GetData() end)
            if not ok or type(d) ~= 'table' then return nil end

            local ped = PlayerPedId()
            return {
                name      = d.name,
                classId   = d.classId,
                className = d.class and d.class.label or nil,
                level     = d.level,
                xp        = d.xp,
                xpToNext  = d.xpToNext,
                needs     = d.needs,
                health    = math.max(0, GetEntityHealth(ped) - 100),
                armour    = GetPedArmour(ped),
                bodySex   = GetEntityModel(ped) == GetHashKey('mp_f_freemode_01') and 'female' or 'male',
            }
        end)(),

        -- Character sheet: levels plus the modifiers they give (e.g. "hunger 18% slower").
        -- Carry weight comes from the class, sent as the difference from baseline (+10kg).
        levels = (function()
            if GetResourceState('bs_skills') ~= 'started' then return nil end
            local ok, v = pcall(function() return exports.bs_skills:GetLevels() end)
            return ok and v or nil
        end)(),

        effects = (function()
            local out = {}

            if GetResourceState('bs_skills') == 'started' then
                local ok, v = pcall(function() return exports.bs_skills:GetEffects() end)
                if ok and type(v) == 'table' then out = v end
            end

            local okD, d = pcall(function() return exports.bs_core:GetData() end)
            if okD and type(d) == 'table' and d.class and d.class.stats
               and d.class.stats.carryWeight then
                local diff = d.class.stats.carryWeight - 40.0
                if math.abs(diff) > 0.01 then out.carryWeight = diff end
            end

            return out
        end)(),

        -- Read from bs_skills, not its config file: this resource does not load config_skills.lua (Skills would be nil here).
        trees = (function()
            if GetResourceState('bs_skills') ~= 'started' then return nil end
            local ok, v = pcall(function() return exports.bs_skills:GetTrees() end)
            return ok and v or nil
        end)(),
    })
    setFocus(true)
    TriggerEvent('bs:ui:opened', 'inventory')
    if GetResourceState('bs_boosters') == 'started' then TriggerServerEvent('bs:boosters:request') end
    if GetResourceState('bs_gadgets') == 'started' then TriggerServerEvent('bs:gadgets:request') end
    CreateThread(function()
        Wait(4000)
        if open and openToken == token and not portraitReady then
            print('^1[bs_inventory]^7 NUI did not render; closing inventory safely')
            closeInventory()
        end
    end)
end

closeInventory = function()
    if not open then return end
    if tradeState and tradeState.phase ~= 'closed' then
        CreateThread(function() BSB.Await('inventory:tradeCancel', 5000) end)
        tradeState = nil
    end
    open = false
    openToken = openToken + 1
    portraitReady = false
    tradeOnly = false
    send({ action = 'close' })
    setFocus(false)
    TriggerScreenblurFadeOut(250)

    -- Done before anything that can yield: a scripted camera left running needs a relog to recover.
    if BSInvPedCam then pcall(BSInvPedCam.Destroy) end
    if BSInvBody then pcall(BSInvBody.Stop) end

    if state.container then
        CreateThread(function() BSB.Await('inventory:closeContainer', 5000) end)
        state.container = nil
    end

    if GetResourceState('bs_ui') == 'started' then
        pcall(function() exports.bs_ui:SetMinimap(false) end)
    end
    TriggerEvent('bs:ui:closed', 'inventory')
end

RegisterNUICallback('inventoryReady', function(data, cb)
    if open and not portraitReady then
        portraitReady = true
        if not tradeOnly then
            local token = openToken
            CreateThread(function()
                -- snapshots first (behind the page's cover), then the portrait camera
                local function startCam()
                    if open and openToken == token and BSInvPedCam then pcall(BSInvPedCam.Start) end
                end
                if BSInvBody then
                    pcall(BSInvBody.Snapshot)
                    local ok = pcall(BSInvBody.Prepare, startCam)
                    if not ok then startCam() end
                else
                    startCam()
                end
            end)
        end
    end
    cb({ ok = open })
end)

RegisterCommand(Inventory.Settings.openCommand, function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if open then closeInventory() else CreateThread(function() openInventory('carry') end) end
end, false)

RegisterKeyMapping(Inventory.Settings.openCommand, L('keymap.open'), 'keyboard',
    Inventory.Settings.openKey or 'TAB')

exports('Open', function(tab) CreateThread(function() openInventory(tab) end) end)
exports('Close', closeInventory)
exports('IsOpen', function() return open end)

local function tradeNotify(message, kind)
    TriggerEvent('bs:ui:notify', {
        type = kind or 'info', title = L('trade.title'),
        message = message, duration = 5000,
    })
end

local function openTrade()
    if open or opening or not tradeState then return end
    opening = true
    local data = BSB.Await('inventory:open', 8000)
    opening = false
    if not tradeState then return end
    if not data or not data.ok then
        tradeNotify(L('trade.bag_failed'), 'warn')
        BSB.Await('inventory:tradeCancel', 5000)
        return
    end
    open, tradeOnly = true, true
    openToken = openToken + 1
    portraitReady = false
    local token = openToken
    state.player = data.player
    send({ action = 'tradeOpen', player = data.player, trade = tradeState })
    setFocus(true)
    TriggerEvent('bs:ui:opened', 'inventory')
    CreateThread(function()
        Wait(4000)
        if open and openToken == token and not portraitReady then
            tradeNotify(L('trade.window_failed'), 'warn')
            closeInventory()
        end
    end)
end

RegisterNetEvent('bs:inventory:tradeState', function(payload)
    local previous = tradeState
    tradeState = payload and payload.phase ~= 'closed' and payload or nil
    if payload and payload.phase == 'closed' then
        tradeNotify(payload.reason or L('trade.ended'), payload.complete and 'success' or 'warn')
    elseif tradeState and tradeState.phase == 'invited'
        and (not previous or previous.id ~= tradeState.id) then
        tradeNotify(tradeState.invitedToYou
            and L('trade.request_from', { name = tradeState.peerName })
            or L('trade.request_sent', { name = tradeState.peerName }))
    elseif tradeState and tradeState.phase == 'offering'
        and (not previous or previous.phase ~= 'offering') then
        tradeNotify(L('trade.accepted'), 'success')
    end
    if not open and tradeState then
        CreateThread(function()
            while opening and tradeState do Wait(50) end
            if open then
                send({ action = 'trade', trade = tradeState })
            elseif tradeState then
                openTrade()
            end
        end)
    elseif open then
        send({ action = 'trade', trade = payload })
        if payload and payload.phase == 'closed' and tradeOnly then
            closeInventory()
        end
    end
end)

local tradeOptionRegistered = false
local function registerTradeOption()
    if tradeOptionRegistered or GetResourceState('bs_interactions') ~= 'started' then return end
    exports.bs_interactions:AddType('ped', {{
        label = L('trade.option'),
        labelKey = 'trade.option',
        icon = 'bag',
        distance = Inventory.Settings.tradeDistance or 3.0,
        event = 'bs:inventory:dot:trade',
        filters = { playerPed = true, onFoot = true,
            maxDistance = Inventory.Settings.tradeDistance or 3.0 },
    }})
    tradeOptionRegistered = true
end
CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(500) end
    registerTradeOption()
end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'bs_interactions' then registerTradeOption() end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'bs_interactions' then tradeOptionRegistered = false end
end)
AddEventHandler('bs:inventory:dot:trade', function(payload)
    local ped = payload and payload.entity
    if not ped or not DoesEntityExist(ped) or not IsPedAPlayer(ped)
        or ped == PlayerPedId() then
        tradeNotify(L('trade.aim_at_player'), 'warn')
        return
    end
    local playerIndex = NetworkGetPlayerIndexFromPed(ped)
    if not playerIndex or playerIndex == -1 then
        tradeNotify(L('trade.unavailable_player'), 'warn')
        return
    end
    local target = GetPlayerServerId(playerIndex)
    if not target or target <= 0 then
        tradeNotify(L('trade.unavailable_player'), 'warn')
        return
    end
    CreateThread(function()
        local result = BSB.Await('inventory:tradeRequest', 8000, target)
        if not result or not result.ok then
            tradeNotify((result and result.error) or L('trade.unavailable'), 'warn')
        end
    end)
end)

-- Server state

-- Weapons that come from items. Only these are policed, so weapons handed out by other systems stay.
local ITEM_WEAPONS
local function itemWeapons()
    if ITEM_WEAPONS then return ITEM_WEAPONS end
    ITEM_WEAPONS = {}
    for _, def in pairs(Items.Definitions or {}) do
        local w = def.data and def.data.weapon
        if type(w) == 'string' then ITEM_WEAPONS[GetHashKey(w)] = true end
    end
    return ITEM_WEAPONS
end

-- An item weapon the bag no longer holds (died, traded, dropped, sold) must leave the ped too,
-- otherwise J or the hotbar can still pull it out.
local function dropGhostWeapons(player)
    if type(player) ~= 'table' or type(player.slots) ~= 'table' then return end
    local held = {}
    for _, entry in pairs(player.slots) do
        local def = entry and entry.item and Items.Definitions[entry.item]
        local w = def and def.data and def.data.weapon
        if type(w) == 'string' then held[GetHashKey(w)] = true end
    end
    local ped = PlayerPedId()
    local _, current = GetCurrentPedWeapon(ped, true)

    -- The bar is the slots right after the grid. A weapon in hand that just left the bar goes away too.
    local barFrom = tonumber(player.gridSlots) or 0
    local barTo = barFrom + 5
    local onBar = {}
    for slot, entry in pairs(player.slots) do
        local n = tonumber(slot)
        local def = entry and entry.item and Items.Definitions[entry.item]
        local w = def and def.data and def.data.weapon
        if n and n > barFrom and n <= barTo and type(w) == 'string' then onBar[GetHashKey(w)] = true end
    end
    if LastBar and current and LastBar[current] and not onBar[current] and itemWeapons()[current] then
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        RemoveWeaponFromPed(ped, current)
        TriggerEvent('bs:weapons:forget', current)
    end
    LastBar = onBar

    for hash in pairs(itemWeapons()) do
        if not held[hash] and HasPedGotWeapon(ped, hash, false) then
            if current == hash then SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true) end
            RemoveWeaponFromPed(ped, hash)
            TriggerEvent('bs:weapons:forget', hash)
        end
    end
end

RegisterNetEvent('bs:inventory:state', function(payload)
    state.player = payload.player
    state.container = payload.container
    dropGhostWeapons(payload.player)
    TriggerEvent('bs:weapons:bagChanged')
    if open then
        send({
            action = 'update',
            player = payload.player,
            -- false, not nil: nil is dropped from the message and the panel would keep showing a closed container.
            container = payload.container or false,
            containerLabel = ctLabel(payload.containerLabel),
        })
    end
end)

RegisterNetEvent('bs:inventory:heal', function(amount)
    local ped = PlayerPedId()
    local max = GetEntityMaxHealth(ped)
    -- amount is a percent of max health (pool above the 100 death line), so every origin heals the same share
    local pts = math.floor(math.max(0, max - 100) * (tonumber(amount) or 0) / 100 + 0.5)
    SetEntityHealth(ped, math.min(max, GetEntityHealth(ped) + pts))
end)

-- Use animations. The server only sends which kind (see animKind in sv_main.lua); the client picks and plays it.
-- dict/clip plays an animation; scenario plays a base-game scenario (no dict request, always exists).
-- Bandaging reuses WORLD_HUMAN_CLIPBOARD for now; swap in a closer dict/clip if you want.
local USE_ANIM = {
    eat   = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', time = 2500 },
    drink = { scenario = 'WORLD_HUMAN_DRINKING', time = 2000 },
    heal  = { scenario = 'WORLD_HUMAN_CLIPBOARD', time = 2600 },
}

local usingItem = false

local function playUseAnim(spec)
    if usingItem then return end
    usingItem = true

    local ped = PlayerPedId()

    if spec.scenario then
        pcall(TaskStartScenario, ped, spec.scenario, 0, true, false, false)
        Wait(spec.time)
        if DoesEntityExist(ped) then pcall(ClearPedTasks, ped) end
    elseif spec.dict and spec.clip then
        if not HasAnimDictLoaded(spec.dict) then RequestAnimDict(spec.dict) end
        local waited = 0
        while not HasAnimDictLoaded(spec.dict) and waited < 1500 do
            Wait(10); waited = waited + 10
        end

        -- Dict missing on this build: skip the animation, the item still works.
        if HasAnimDictLoaded(spec.dict) then
            -- flag 48 = upper body only + allow movement, so eating does not root you mid-fight.
            TaskPlayAnim(ped, spec.dict, spec.clip, 4.0, -4.0, spec.time, 48, 0, false, false, false)
            Wait(spec.time)
        end

        RemoveAnimDict(spec.dict)
    end

    usingItem = false
end

RegisterNetEvent('bs:inventory:useAnim', function(kind)
    local spec = USE_ANIM[kind]
    if not spec then return end
    CreateThread(function() playUseAnim(spec) end)
end)

local ThrowSkipUntil = 0

RegisterNetEvent('bs:inventory:equipWeapon', function(weapon, ammo)
    ThrowSkipUntil = GetGameTimer() + 1500
    local ped = PlayerPedId()
    local hash = type(weapon) == 'number' and weapon or GetHashKey(weapon)
    local rounds = math.floor(tonumber(ammo) or 0)

    -- Set, not add: give the weapon with 0 ammo, then SetPedAmmo the exact count. GiveWeaponToPed's ammo argument is unreliable when the ped already has the weapon.
    GiveWeaponToPed(ped, hash, 0, false, true)
    SetPedAmmo(ped, hash, rounds)

    -- Chamber what fits: SetPedAmmo sets the total, not what is in the magazine, so load the clip from that total. No rounds are created; the rest stays as reserve.
    local maxClip = GetMaxAmmoInClip(ped, hash, 0) or 0
    if maxClip > 0 and rounds > 0 then
        SetAmmoInClip(ped, hash, math.min(rounds, maxClip))
    end

    SetCurrentPedWeapon(ped, hash, true)
end)

-- Throwables: a drop in ammo means one left the hand, so the server takes one item from the stack.
local function throwableWeapons()
    local out = {}
    for _, def in pairs(Items.Definitions or {}) do
        local d = def.data
        if d and d.throwable and type(d.weapon) == 'string' then out[GetHashKey(d.weapon)] = d.weapon end
    end
    return out
end

CreateThread(function()
    local list = nil
    local lastHash, lastAmmo = nil, 0
    while true do
        Wait(100)
        list = list or throwableWeapons()
        local ped = PlayerPedId()
        if lastHash then
            local now = HasPedGotWeapon(ped, lastHash, false) and GetAmmoInPedWeapon(ped, lastHash) or 0
            if GetGameTimer() < ThrowSkipUntil then
                lastAmmo = now
            elseif now < lastAmmo then
                for _ = 1, math.min(lastAmmo - now, 3) do TriggerServerEvent('bs:inventory:thrown', list[lastHash]) end
                lastAmmo = now
            end
        end
        local _, cur = GetCurrentPedWeapon(ped, true)
        if cur and list[cur] then
            if cur ~= lastHash then lastHash, lastAmmo = cur, GetAmmoInPedWeapon(ped, cur) end
        elseif lastHash and (not HasPedGotWeapon(ped, lastHash, false) or GetAmmoInPedWeapon(ped, lastHash) >= lastAmmo) then
            lastHash = nil
        end
    end
end)

-- Loading a box of rounds. The server already took the box and issued a token; if the held weapon does not take it, the token goes back and the box is refunded.
RegisterNetEvent('bs:inventory:loadAmmo', function(token, ammoFor, rounds)
    local ped = PlayerPedId()
    local _, held = GetCurrentPedWeapon(ped, true)

    local fits = false
    if held and held ~= GetHashKey('WEAPON_UNARMED') then
        for _, name in ipairs(ammoFor or {}) do
            if GetHashKey(name) == held then fits = true break end
        end
    end

    if not fits then
        TriggerServerEvent('bs:inventory:ammoRefund', token)
        TriggerEvent('bs:ui:notify', {
            type = 'warn',
            message = L('ammo.no_gun'),
            duration = 2400,
        })
        return
    end

    -- A box tops up the gun, it is not a reserve. Once the gun has a full mag, extra boxes stay in the bag (refunded).
    local okMag, mag = pcall(function() return exports.bs_weapons:ClientMagSize(held) end)
    mag = okMag and tonumber(mag) or 0
    if mag <= 0 then mag = GetMaxAmmoInClip(ped, held, true) end
    if GetAmmoInPedWeapon(ped, held) >= mag then
        TriggerServerEvent('bs:inventory:ammoRefund', token)
        TriggerEvent('bs:ui:notify', { type = 'warn', message = L('ammo.mag_full'), duration = 2000 })
        return
    end
    AddAmmoToPed(ped, held, math.floor(tonumber(rounds) or 0))
    TriggerEvent('bs:ui:notify', {
        type = 'success',
        message = L('ammo.added', { n = math.floor(tonumber(rounds) or 0) }),
        duration = 1600,
    })
end)

-- Body armour from a crafted plate carrier.
RegisterNetEvent('bs:inventory:armour', function(amount)
    local ped = PlayerPedId()
    SetPedArmour(ped, math.min(100, GetPedArmour(ped) + (tonumber(amount) or 0)))
end)

-- NUI

RegisterNUICallback('close', function(_, cb) closeInventory(); cb({ ok = true }) end)

-- Booster slots (bs_boosters owns the data, this panel only shows it).
AddEventHandler('bs:boosters:loadoutChanged', function(lo, keys)
    send({ action = 'boosters', loadout = lo, keys = keys })
end)

RegisterNUICallback('boosterSet', function(data, cb)
    if GetResourceState('bs_boosters') == 'started' and type(data) == 'table' then
        TriggerServerEvent('bs:boosters:setSlot', tonumber(data.index), data.item)
    end
    cb({ ok = true })
end)

-- Gadget slots (bs_gadgets owns the data).
AddEventHandler('bs:gadgets:loadoutChanged', function(lo, keys)
    send({ action = 'gadgets', loadout = lo, keys = keys })
end)

RegisterNUICallback('gadgetSet', function(data, cb)
    if GetResourceState('bs_gadgets') == 'started' and type(data) == 'table' then
        TriggerServerEvent('bs:gadgets:setSlot', tonumber(data.index), data.item)
    end
    cb({ ok = true })
end)

RegisterNUICallback('move', function(data, cb)
    CreateThread(function()
        cb(BSB.Await('inventory:move', 8000, data.from, data.to, data.amount) or { ok = false })
    end)
end)

-- Open the pack on your back into the container panel. The slot is not trusted; the server checks it.
RegisterNUICallback('openBag', function(data, cb)
    CreateThread(function()
        cb(BSB.Await('inventory:openBag', 8000, data.slot) or { ok = false })
    end)
end)

-- Medical tab: bs_medical sends its data through here and gets the clicks back.
AddEventHandler('bs:inventory:nui', function(payload)
    if type(payload) == 'table' and payload.action == 'medical' then send(payload) end
end)

RegisterNUICallback('medical', function(data, cb)
    TriggerEvent('bs:medical:nui', data)
    cb({ ok = true })
end)

RegisterNUICallback('use', function(data, cb)
    CreateThread(function()
        cb(BSB.Await('inventory:use', 8000, data.slot) or { ok = false })
    end)
end)

-- Dropping puts the stack on the ground in front of you.
RegisterNUICallback('drop', function(data, cb)
    CreateThread(function()
        local ped = PlayerPedId()
        local ahead = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.8, 0.0)
        local result = BSB.Await('inventory:dropWorld', 8000, data.slot, data.amount,
            { x = ahead.x, y = ahead.y, z = ahead.z })
        cb(result or { ok = false })
    end)
end)

RegisterNUICallback('give', function(data, cb)
    CreateThread(function()
        cb(BSB.Await('inventory:give', 8000, data.slot, data.amount, data.target) or { ok = false })
    end)
end)

RegisterNUICallback('nearbyPlayers', function(_, cb)
    CreateThread(function()
        cb(BSB.Await('inventory:nearbyPlayers', 6000) or { ok = false, players = {} })
    end)
end)

local tradeCallbacks = {
    tradeRequest = 'inventory:tradeRequest',
    tradeRespond = 'inventory:tradeRespond',
    tradeOffer = 'inventory:tradeOffer',
    tradeMoney = 'inventory:tradeMoney',
    tradeConfirm = 'inventory:tradeConfirm',
    tradeCancel = 'inventory:tradeCancel',
}
for nui, callback in pairs(tradeCallbacks) do
    RegisterNUICallback(nui, function(data, cb)
        CreateThread(function()
            local result
            if nui == 'tradeRequest' then
                result = BSB.Await(callback, 8000, data.target)
            elseif nui == 'tradeRespond' then
                result = BSB.Await(callback, 8000, data.accept)
            elseif nui == 'tradeOffer' then
                result = BSB.Await(callback, 8000, data.slot, data.add)
            elseif nui == 'tradeMoney' then
                result = BSB.Await(callback, 8000, data.amount)
            else
                result = BSB.Await(callback, 35000)
            end
            if not result or not result.ok then
                tradeNotify((result and result.error) or L('trade.action_failed'), 'warn')
            end
            cb(result or { ok = false, error = 'trade unavailable' })
        end)
    end)
end

-- Settings live here because this is the screen players open.
local function applySettings(patch)
    patch = type(patch) == 'table' and patch or {}
    local hud = {}
    for key, value in pairs(patch) do
        local handler = extraSettings[key]
        if handler then
            pcall(handler.set, value)
        else
            hud[key] = value
        end
    end
    if next(hud) and GetResourceState('bs_ui') == 'started' then
        exports.bs_ui:ApplyHudSettings(hud, true)
    end
end

RegisterNUICallback('settings', function(data, cb)
    applySettings(type(data) == 'table' and data.patch or nil)
    cb({ ok = true })
end)

-- The pause menu (bs_pause) shows the same settings and writes through the same handlers.
exports('GetPlayerSettings', function() return collectSettings() end)
exports('ApplyPlayerSettings', function(patch) applySettings(patch) return true end)

-- Troubleshooting buttons run the same commands players can type.
local SETTINGS_ACTIONS = { refreshui = true, unblur = true }

RegisterNUICallback('settingsAction', function(data, cb)
    local name = type(data) == 'table' and data.action or nil
    cb({ ok = true })
    if SETTINGS_ACTIONS[name] then ExecuteCommand(name) end
end)
exports('RunSettingsAction', function(name) if SETTINGS_ACTIONS[name] then ExecuteCommand(name) end end)

-- Opening a container from a world interaction

RegisterNetEvent('bs:inventory:openContainer', function(containerId, label, size, weight)
    CreateThread(function()
        local result = BSB.Await('inventory:openContainer', 8000, containerId, label, size, weight)
        if not result or not result.ok then return end
        if not open then openInventory() end
        state.container = result.container
        send({ action = 'update', container = result.container, containerLabel = ctLabel(result.label) })
    end)
end)

-- Backpacks: open a dropped pack where it lies, or a downed / cuffed player's worn pack. The server checks range and state.
local function openPackResult(result)
    if not result or not result.ok then
        if result and result.error then TriggerEvent('bs:ui:notify', { type = 'warn', message = result.error }) end
        return
    end
    if not open then openInventory() end
    state.container = result.container
    send({ action = 'update', container = result.container, containerLabel = ctLabel(result.label) })
end

AddEventHandler('bs:inventory:dot:openPack', function(payload)
    local id = payload and payload.args and payload.args.id
    if not id then return end
    CreateThread(function() openPackResult(BSB.Await('inventory:openDropPack', 8000, id)) end)
end)

AddEventHandler('bs:inventory:openPlayerPack', function(payload)
    local ped = payload and payload.entity
    if not ped or not DoesEntityExist(ped) or not IsPedAPlayer(ped) then return end
    local pid = NetworkGetPlayerIndexFromPed(ped)
    if not pid or pid == -1 then return end
    local target = GetPlayerServerId(pid)
    CreateThread(function() openPackResult(BSB.Await('inventory:openPlayerPack', 8000, target)) end)
end)

-- Pack look picker and hide toggle in the bag screen.
RegisterNUICallback('packLook', function(data, cb)
    CreateThread(function()
        cb(BSB.Await('inventory:packLook', 8000, data.look, data.hidden) or { ok = false })
    end)
end)

CreateThread(function()
    while GetResourceState('bs_interactions') ~= 'started' do Wait(500) end
    Wait(1500)
    exports.bs_interactions:AddType('ped', {
        { labelKey = 'opt.open_pack', label = 'Open backpack', icon = 'bag', distance = 2.5, event = 'bs:inventory:openPlayerPack',
          filters = { playerPed = true, onFoot = true, ownerStateTrue = 'bsDowned' } },
        { labelKey = 'opt.open_pack', label = 'Open backpack', icon = 'bag', distance = 2.5, event = 'bs:inventory:openPlayerPack',
          filters = { playerPed = true, onFoot = true, ownerStateTrue = 'bsCuffed' } },
    })
end)

-- One menu at a time: every menu raises 'bs:ui:opened' with its own name and closes itself when it hears another name, so two NUI pages never hold focus together.
-- CountLocal: how many of an item the last server push says we carry (used by the weapon wheel). A mirror only; the server still checks.
exports('CountLocal', function(item)
    local total = 0
    for _, entry in pairs((state.player and state.player.slots) or {}) do
        if entry.item == item then total = total + (entry.amount or 0) end
    end
    return total
end)

AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'inventory' and open then closeInventory() end
end)

AddEventHandler('bs:ui:requestClose', function(who)
    if who ~= 'inventory' and open then closeInventory() end
end)

-- /refreshui hard reset. closeInventory() bails out if the open flag has drifted from the NUI state, so panic ignores the flag: force the NUI closed, give focus back, clear screen effects and forget the open container.
AddEventHandler('bs:ui:panic', function()
    open = false
    state.container = nil
    send({ action = 'close' })
    setFocus(false)
    TriggerScreenblurFadeOut(0)
    if GetResourceState('bs_ui') == 'started' then
        pcall(function() exports.bs_ui:SetMinimap(false) end)
    end
end)

AddEventHandler('bs:hook:player:unloaded', closeInventory)

-- Dying with the bag open would leave the panel holding focus over the death screen.
CreateThread(function()
    while true do
        Wait(500)
        if open and IsPedDeadOrDying(PlayerPedId(), true) then closeInventory() end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Anything counting open menus (hotbar, chat) must hear we are gone.
    if open then TriggerEvent('bs:ui:closed', 'inventory') end
    SetNuiFocus(false, false)
    -- Make sure the screen blur never outlives the menu.
    TriggerScreenblurFadeOut(0)
    if BSInvPedCam then pcall(BSInvPedCam.Destroy) end
    if BSInvBody then pcall(BSInvBody.Stop) end
end)

-- Ped half of a wipe (see Inv.Wipe in server/sv_main.lua): emptying the rows leaves items already given to the ped, so clear those too. Also tells bs_weapons to drop its fitted-attachment cache.
RegisterNetEvent('bs:inventory:wiped', function()
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        -- Stop any draw/use task first, then force a completely clean hand state.
        ClearPedTasks(ped)
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
        RemoveAllPedWeapons(ped, true)
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    end
    LastBar = {}
    usingItem = false
    TriggerEvent('bs:weapons:forgetAll')
end)

-- /hidehud from bs_ui: hide this page (hotbar, dash, mission tracker) too.
AddEventHandler('bs:inventory:hideAll', function(state) SendNUIMessage({ action = 'bsHideAll', hidden = state == true }) end)

-- Revive hand cleanup: a player who is revived from the downed/bleedout state does
-- not go through the normal death-spawn wipe. GTA can therefore keep the last
-- equipped weapon on the ped even though the revive flow has finished. Watch the
-- replicated downed state and holster/remove ped weapons when it changes true -> false.
-- Inventory rows are NOT touched; the player may equip the weapon again normally.
CreateThread(function()
    local wasDowned = LocalPlayer.state.bsDowned == true
    while true do
        Wait(200)
        local downed = LocalPlayer.state.bsDowned == true
        if wasDowned and not downed then
            -- Give the medical resource a moment to finish resurrecting the ped.
            Wait(300)
            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
                RemoveAllPedWeapons(ped, true)
                SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
            end
            usingItem = false
            TriggerEvent('bs:weapons:forgetAll')
            TriggerServerEvent('bs:inventory:reviveHandCleanup')
        end
        wasDowned = downed
    end
end)
