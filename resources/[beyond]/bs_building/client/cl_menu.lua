-- bs_building build menu (F2). Three styles, picked in the player settings:
-- wheel     = radial wheel, pick a category then a piece (default)
-- bar       = bottom bar like a settlement workshop: arrows pick, the ghost in the world swaps live
-- catalogue = full list with search and a 3D preview of the piece
-- All three show the name, the cost as have/need and the tier.

local S = Building.Settings
local P = Building.Pieces
local K = Building.Keys

local STYLES = { wheel = true, bar = true, catalogue = true }
local KVP = 'bs_build_menu'

local function getStyle()
    local ok, v = pcall(GetResourceKvpString, KVP)
    if ok and STYLES[v] then return v end
    return STYLES[S.menuDefault] and S.menuDefault or 'wheel'
end
local function setStyle(v)
    if not STYLES[v] then return false end
    SetResourceKvp(KVP, v)
    return true
end
exports('GetMenuStyle', getStyle)
exports('SetMenuStyle', function(v) return setStyle(tostring(v or '')) end)

local openBar
local Menu = { open = nil, data = nil, cat = 1, idx = 1 }

local function catalogue()
    local res = BSB.Await('build:catalogue', 8000)
    if not res or not res.ok then return nil end
    if res.mode == 'claim' and not res.faction then Building.Notify('warn', L('build.err.no_faction')) return nil end
    return res
end

-- Categories that have at least one piece, in config order
local function cats(data)
    local out = {}
    for _, c in ipairs(Building.Categories) do
        local list = {}
        for _, p in ipairs(data.pieces) do if p.cat == c.id then list[#list + 1] = p end end
        if #list > 0 then out[#out + 1] = { id = c.id, icon = c.icon, list = list } end
    end
    return out
end

local function close()
    if not Menu.open then return end
    local was = Menu.open
    Menu.open = nil
    if was ~= 'bar' then SetNuiFocus(false, false) end
    TriggerEvent('bs:ui:closed', was == 'bar' and 'building_bar' or 'building')
    SendNUIMessage({ action = 'menuClose' })
    if was == 'catalogue' then Building.PreviewStop() end
    if was == 'bar' and Building.Place.active then Building.StopPlacing() end
end
Building.CloseMenu = close

-- Wheel and catalogue

local function openFocused(style, data)
    Menu.open, Menu.data = style, data
    TriggerEvent('bs:ui:opened', 'building')
    SetNuiFocus(true, true)
    SendNUIMessage({ action = style, data = data, cats = Building.Categories })
end

RegisterNUICallback('wheelPick', function(data, cb)
    cb({ ok = true })
    close()
    if data and P[data.id] then Building.StartPlacing(data.id) end
end)
RegisterNUICallback('wheelClose', function(_, cb) close(); cb({ ok = true }) end)
RegisterNUICallback('menuClose', function(_, cb) close(); cb({ ok = true }) end)
RegisterNUICallback('catHover', function(data, cb)
    cb({ ok = true })
    if Menu.open == 'catalogue' and data and P[data.id] then Building.Preview(data.id) end
end)
RegisterNUICallback('previewReturn', function(_, cb)
    cb({ok=true})
    if Menu.open~='catalogue' then return end
    local data=Menu.data
    close()
    openBar(data)
end)

RegisterNUICallback('catPick', function(data, cb)
    cb({ ok = true })
    close()
    if data and P[data.id] then Building.StartPlacing(data.id) end
end)

-- Bottom bar

local function barSend(full)
    local list = Menu.cats[Menu.cat] and Menu.cats[Menu.cat].list or {}
    SendNUIMessage({ action = full and 'bar' or 'barSel', data = full and Menu.data or nil, cats = full and Building.Categories or nil,
                     cat = Menu.cats[Menu.cat] and Menu.cats[Menu.cat].id, idx = Menu.idx, barScale = tonumber(GetResourceKvpString('bs_build_bar_scale')) or 1 })
    return list[Menu.idx]
end

local function barPick()
    local p = barSend(false)
    if p then Building.StartPlacing(p.id, { bar = true }) end
end

openBar = function(data)
    Menu.open, Menu.data = 'bar', data
    Menu.cats = cats(data)
    if #Menu.cats == 0 then Menu.open = nil return end
    Menu.cat = math.min(Menu.cat, #Menu.cats)
    Menu.idx = math.min(Menu.idx, #Menu.cats[Menu.cat].list)
    TriggerEvent('bs:ui:opened', 'building_bar')
    barSend(true)
    barPick()
    CreateThread(function()
        local lastRefresh = GetGameTimer()
        while Menu.open == 'bar' do
            Wait(0)
            for _, c in ipairs({ K.left, K.right, K.up, K.down }) do DisableControlAction(0, c, true) end
            local moved = false
            local list = Menu.cats[Menu.cat].list
            if IsDisabledControlJustPressed(0, K.right) then Menu.idx = Menu.idx % #list + 1; moved = true end
            if IsDisabledControlJustPressed(0, K.left) then Menu.idx = (Menu.idx - 2) % #list + 1; moved = true end
            if IsDisabledControlJustPressed(0, K.down) then Menu.cat = Menu.cat % #Menu.cats + 1; Menu.idx = 1; moved = true end
            if IsDisabledControlJustPressed(0, K.up) then Menu.cat = (Menu.cat - 2) % #Menu.cats + 1; Menu.idx = 1; moved = true end
            if moved then PlaySoundFrontend(-1, 'NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true); barPick() end
            -- have/need goes stale after every place
            if GetGameTimer() - lastRefresh > 3000 then
                lastRefresh = GetGameTimer()
                CreateThread(function()
                    local fresh = BSB.Await('build:catalogue', 6000)
                    if fresh and fresh.ok and Menu.open == 'bar' then
                        Menu.data = fresh
                        local keepCat = Menu.cats[Menu.cat] and Menu.cats[Menu.cat].id
                        Menu.cats = cats(fresh)
                        for i, c in ipairs(Menu.cats) do if c.id == keepCat then Menu.cat = i end end
                        Menu.cat = math.min(Menu.cat, #Menu.cats)
                        Menu.idx = math.min(Menu.idx, #Menu.cats[Menu.cat].list)
                        SendNUIMessage({ action = 'barData', data = fresh, cat = Menu.cats[Menu.cat].id, idx = Menu.idx })
                    end
                end)
            end
        end
    end)
end

AddEventHandler('bs:building:placeEnded', function() if Menu.open == 'bar' then close() end end)

local function openMenu(requestedStyle)
    if Menu.open then close() return end
    if Building.Place.active then return end
    local data = catalogue()
    if not data then return end
    local style = ({bar=true,wheel=true,catalogue=true})[requestedStyle] and requestedStyle or getStyle()
    if style == 'bar' then openBar(data)
    else openFocused(style, data) end
end

AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'building' and what ~= 'building_bar' and Menu.open then close() end
end)

exports('OpenMenu', function(style) CreateThread(function() openMenu(style) end) end)
AddEventHandler('bs:building:open', function(style) CreateThread(function() openMenu(style) end) end)

-- Same command name as before so old F2 binds still work.
RegisterCommand('+factionbuild', function() CreateThread(function() openMenu('wheel') end) end, false)
RegisterCommand('-factionbuild', function() end, false)
RegisterKeyMapping('+factionbuild', L('keymap.build_wheel'), 'keyboard', 'F2')

-- /buildmenu wheel|bar|catalogue, same as the setting
RegisterCommand('buildmenu', function(_, args)
    local v = tostring(args[1] or ''):lower()
    if setStyle(v) then Building.Notify('success', L('build.menu_set', { style = L('ui.menu_' .. v) }))
    else Building.Notify('info', L('build.menu_usage')) end
end, false)

-- 3D preview for the catalogue: the piece on the ground in front of you, a camera circling it

local Prev = { extra = {}, obj = nil, cam = nil, id = nil, spin = 0.0 }

function Building.PreviewStop()
    Prev.id = nil
    if Prev.obj and DoesEntityExist(Prev.obj) then DeleteEntity(Prev.obj) end
    Prev.obj = nil
    for _,obj in ipairs(Prev.extra) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    Prev.extra={}
    if Prev.cam then
        RenderScriptCams(false, true, 350, true, false)
        DestroyCam(Prev.cam, false)
        Prev.cam = nil
    end
end

function Building.Preview(pieceId)
    if Prev.id == pieceId then return end
    Prev.id = pieceId
    CreateThread(function()
        local d = P[pieceId]
        local tier = Building.BaseTier(d)
        local hash = Building.ModelFor(pieceId, tier)
        if not Building.LoadModel(hash) then return end
        if Prev.id ~= pieceId or Menu.open ~= 'catalogue' then SetModelAsNoLongerNeeded(hash);return end
        if Prev.obj and DoesEntityExist(Prev.obj) then DeleteEntity(Prev.obj) end
        for _,obj in ipairs(Prev.extra) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
        Prev.extra={}
        local w, dp, h = Building.SizeOf(pieceId, tier)
        local size = math.max(w, dp, h, 0.6)
        local dist = math.max(2.2, size * 1.45)
        -- far enough out that the camera stays in front of you
        local ped = PlayerPedId()
        local base = GetOffsetFromEntityInWorldCoords(ped, 0.0, dist + 2.0, 0.0)
        local ok, gz = GetGroundZFor_3dCoord(base.x, base.y, base.z + 2.0, false)
        local z = ok and gz or (base.z - 1.0)
        local obj = CreateObjectNoOffset(hash, base.x, base.y, z, false, false, false)
        if not obj or obj==0 then SetModelAsNoLongerNeeded(hash);return end
        local parts=Building.PartOffsets(pieceId,tier)
        for i=2,math.min(parts and #parts or 1,12) do
            local extra=CreateObjectNoOffset(hash,base.x,base.y,z,false,false,false)
            if extra and extra~=0 then SetEntityCollision(extra,false,false);FreezeEntityPosition(extra,true);Prev.extra[#Prev.extra+1]=extra end
        end
        Prev.parts=parts
        SetModelAsNoLongerNeeded(hash)
        SetEntityCollision(obj, false, false)
        FreezeEntityPosition(obj, true)
        Prev.obj = obj
        Building.Align(obj, base.x, base.y, z, Prev.spin, d.pitch)
        Prev.dist, Prev.bottom, Prev.size = dist, z, size
        Prev.center = vector3(base.x, base.y, z + h / 2)
        if not Prev.cam then
            Prev.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            SetCamFov(Prev.cam, 45.0)
            RenderScriptCams(true, true, 350, true, false)
        end
    end)
end

-- Spin the preview, keep the camera on it (the piece sits right of the menu panel)
CreateThread(function()
    while true do
        if Prev.obj and Prev.cam and DoesEntityExist(Prev.obj) then
            Prev.spin = (Prev.spin + 21.0 * GetFrameTime()) % 360
            local d = P[Prev.id or '']
            if d then
                local function align(obj,part)
                    part=part or {}
                    local x,y=Building.Rotate(part.x or 0,part.y or 0,Prev.spin)
                    Building.Align(obj,Prev.center.x+x,Prev.center.y+y,Prev.bottom+(part.z or 0),Prev.spin,d.pitch)
                end
                align(Prev.obj,Prev.parts and Prev.parts[1])
                for i,obj in ipairs(Prev.extra) do align(obj,Prev.parts and Prev.parts[i+1]) end
            end
            local ped = PlayerPedId()
            local fwd = GetEntityForwardVector(ped)
            local right = vector3(fwd.y, -fwd.x, 0.0)
            local camPos = Prev.center - fwd * Prev.dist + vector3(0.0, 0.0, Prev.size * 0.35)
            SetCamCoord(Prev.cam, camPos.x, camPos.y, camPos.z)
            local look = Prev.center - right * (Prev.size * 0.45)
            PointCamAtCoord(Prev.cam, look.x, look.y, look.z)
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    Building.PreviewStop()
    if Menu.open and Menu.open ~= 'bar' then SetNuiFocus(false, false) end
    TriggerEvent('bs:ui:closed', 'building')
    TriggerEvent('bs:ui:closed', 'building_bar')
end)


RegisterCommand('buildcatalogue', function()
    if Menu.open then close() end
    CreateThread(function() openMenu('catalogue') end)
end, false)
RegisterCommand('buildbarscale', function(_, args)
    local value = tonumber(args[1])
    if not value or value ~= value then return end
    value = math.max(0.75, math.min(1.35, value))
    SetResourceKvp('bs_build_bar_scale', tostring(value))
    SendNUIMessage({action='barScale',value=value})
end, false)

-- Inspect the actual selected model, then return to the same workshop category.
RegisterCommand('buildpreview',function()
    if Menu.open~='bar' then return end
    local category=Menu.cats[Menu.cat]
    local selected=category and category.list[Menu.idx]
    local data=Menu.data
    close()
    openFocused('catalogue',data)
    SendNUIMessage({action='previewSelection',id=selected and selected.id})
    if selected then Building.Preview(selected.id) end
end,false)
RegisterKeyMapping('buildpreview','Inspect selected building piece','keyboard','HOME')
