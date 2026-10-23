-- bs_traders - the changing room: browsing, previewing and the camera.
-- Preview sets components on the real player ped (no doll), so the shop snapshots the outfit on open and must restore it on exit.

local shop = {
    open = false,
    ready = false,      -- set once the panel confirms it is on screen
    focus = 'full',     -- which body part the camera is framing
    npcId = nil,
    snapshot = nil,     -- outfit as it was when the shop opened
    cam = nil,
    gender = 'male',
    who = { vip = false, level = 0 },

    -- Camera orbit vs turning the ped: orbit moves the camera around the character (drag) so you can see the back; turning the ped changes which way the character faces (arrow buttons).
    orbit = 0.0,
    zoom = 1.0,

    -- Auto arms: true until the player picks a sleeve by hand in the Arms category. While true, changing the top also sets component 3 to match. Once the player chooses, it goes false and the shop stops overriding.
    autoArms = true,

    -- Pose being held, or nil for standing. See setPose.
    pose = nil,
}

-- Read by cl_main.lua's pushTracker. Both files share a Lua state, so this is a plain global. Lets the objective tracker hide while this screen is up.
WardrobeIsOpen = false

local function send(payload) SendNUIMessage(payload) end

local function say(text)
    TriggerEvent('chat:addMessage', { args = { '^5[wardrobe]', text } })
end

-- Ask the objective tracker to re-check whether it should be shown. pcall'd because cl_main may not have defined it yet.
local function nudgeTracker()
    if RefreshTracker then pcall(RefreshTracker) end
end

-- Reading and writing the ped

local function ped() return PlayerPedId() end

-- Which freemode model this is; decides the names shown and what "nothing" resolves to. Anything not female is treated as male (safer default for addon bodies).
local function genderOf(p)
    return GetEntityModel(p) == GetHashKey('mp_f_freemode_01') and 'female' or 'male'
end

-- Categories with what this model actually offers. Counts come from the ped; the server sends the rules and the panel combines them.
local function enumerate(categories)
    local p = ped()
    local out = {}

    for _, cat in ipairs(categories or {}) do
        local entry = {
            id = cat.id, label = cat.label, kind = cat.kind,
            index = cat.index, price = cat.price,
            -- The drawable meaning "nothing" for this category on this model, or nil if there is none. The panel only draws a Remove row when this is set.
            bare = Wardrobe.BareFor(cat.id, shop.gender),
        }

        if cat.kind == 'component' then
            entry.count = GetNumberOfPedDrawableVariations(p, cat.index)
            entry.current = GetPedDrawableVariation(p, cat.index)
            entry.texture = GetPedTextureVariation(p, cat.index)
            entry.textures = GetNumberOfPedTextureVariations(p, cat.index, entry.current)
        else
            -- Props can be absent: GetPedPropIndex returns -1 for "nothing", so the range starts at -1 and the panel offers "none" first.
            entry.count = GetNumberOfPedPropDrawableVariations(p, cat.index)
            entry.current = GetPedPropIndex(p, cat.index)
            entry.texture = GetPedPropTextureIndex(p, cat.index)
            entry.textures = entry.current >= 0
                and GetNumberOfPedPropTextureVariations(p, cat.index, entry.current) or 0
        end

        -- Categories the model has nothing for are hidden, since an empty tab looks broken.
        if (entry.count or 0) > 0 then out[#out + 1] = entry end
    end

    return out
end

-- Put one garment on now.
-- Arms: a top also sets component 3 while auto arms is on. There is no native for the correct torso of an arbitrary base-game top, so it uses the same index as the top when that exists (see Clothing.TorsoMap in bs_inventory).
local function wear(cat, drawable, texture, remove)
    local p = ped()
    texture = math.max(0, math.floor(tonumber(texture) or 0))

    if cat.kind == 'prop' then
        drawable = remove and -1 or math.floor(tonumber(drawable) or -1)
        if drawable < 0 then
            ClearPedProp(p, cat.index)
        else
            SetPedPropIndex(p, cat.index, drawable, texture, true)
        end
        return
    end

    if remove then
        local bare = Wardrobe.BareFor(cat.id, shop.gender)
        if not bare then return end       -- no safe empty state; refuse
        drawable, texture = bare, 0
    end

    drawable = math.max(0, math.floor(tonumber(drawable) or 0))
    local count = GetNumberOfPedDrawableVariations(p, cat.index)
    if count <= 0 then return end
    drawable = math.min(drawable, count - 1)

    local texCount = GetNumberOfPedTextureVariations(p, cat.index, drawable)
    texture = math.min(texture, math.max(0, texCount - 1))

    SetPedComponentVariation(p, cat.index, drawable, texture, 2)

    -- Picking sleeves by hand turns automatic pairing off for this fitting. See shop.autoArms.
    if cat.id == 'arms' then shop.autoArms = false end

    if cat.arms and shop.autoArms then
        local armsCount = GetNumberOfPedDrawableVariations(p, 3)
        if armsCount > 0 then
            -- Removing the top also bares the arms. Wardrobe.BareArms holds the pair.
            local target = remove
                and (Wardrobe.BareArms[shop.gender] or 15)
                or drawable
            SetPedComponentVariation(p, 3, math.min(target, armsCount - 1), 0, 2)
        end
    end
end

-- Poses
-- See Wardrobe.Poses in config_wardrobe.lua. Sleeve clipping shows when the arms are raised, so a static pose would hide the fault the Arms category fixes.

-- Resolve a pose's clip once. DoesAnimDictExist can be true for a dict without the named clip, and TaskPlayAnim on a missing clip fails silently. GetAnimDuration returns 0 for a missing clip, so use that. Same pattern as resolveWorkAnim in cl_main.lua.
local poseCache = {}

local function resolvePose(pose)
    if poseCache[pose.id] ~= nil then
        return poseCache[pose.id] or nil
    end

    for _, c in ipairs(pose.anims or {}) do
        if c.dict and DoesAnimDictExist(c.dict) then
            if not HasAnimDictLoaded(c.dict) then RequestAnimDict(c.dict) end
            local waited = 0
            while not HasAnimDictLoaded(c.dict) and waited < 1200 do
                Wait(10); waited = waited + 10
            end

            if HasAnimDictLoaded(c.dict) then
                local ok, duration = pcall(GetAnimDuration, c.dict, c.clip)
                if ok and type(duration) == 'number' and duration > 0.0 then
                    poseCache[pose.id] = c
                    return c
                end
            end
        end
    end

    poseCache[pose.id] = false
    return nil
end

-- Hold a pose, or drop back to standing (nil clears).
-- Flag 49 = looped + upper body: looped so the pose stays visible, upper body so it does not fight the frozen legs. ClearPedTasks is used since the ped is frozen and doing nothing else.
local function setPose(poseId)
    local p = ped()

    if not poseId then
        shop.pose = nil
        ClearPedTasks(p)
        return true
    end

    local pose
    for _, entry in ipairs(Wardrobe.Poses or {}) do
        if entry.id == poseId then pose = entry break end
    end
    if not pose then return false end

    local anim = resolvePose(pose)
    if not anim then
        shop.pose = nil
        return false
    end

    shop.pose = poseId
    TaskPlayAnim(p, anim.dict, anim.clip, 4.0, -4.0, -1, 49, 0.0, false, false, false)
    return true
end

-- The camera

local function focusPoint(focusId)
    local f = (Wardrobe.Settings.focus or {})[focusId or 'full']
        or (Wardrobe.Settings.focus or {}).full
        or { dist = 2.2, z = 0.05, side = 0.2 }
    return f
end

-- Place the camera for a body part at the current orbit and zoom.
-- Everything is computed from the ped's position and heading, so it works anywhere. Orbit rotates the camera offset around the ped; the ped itself is never touched.
local function aimCamera(focusId, instant)
    if not shop.cam then return end

    local p = ped()
    local coords = GetEntityCoords(p)
    local f = focusPoint(focusId)
    local dist = (f.dist or 2.2) * (shop.zoom or 1.0)

    -- The camera sits at (ped heading + 180 + orbit): in front of the face at orbit 0, directly behind at 180.
    local ang = math.rad((GetEntityHeading(p) + 180.0 + (shop.orbit or 0.0)) % 360.0)
    local ox, oy = -math.sin(ang), math.cos(ang)
    local sx, sy = math.cos(ang), math.sin(ang)

    local target = vector3(coords.x, coords.y, coords.z + (f.z or 0.0))
    local camX = coords.x + ox * dist + sx * (f.side or 0.0)
    local camY = coords.y + oy * dist + sy * (f.side or 0.0)
    local camZ = coords.z + (f.z or 0.0) + 0.05

    if instant then
        SetCamCoord(shop.cam, camX, camY, camZ)
        PointCamAtCoord(shop.cam, target.x, target.y, target.z)
        return
    end

    -- Interpolated (450ms) rather than cut, since a hard cut between close-ups looks like a glitch. Dragging uses the instant path.
    local temp = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        camX, camY, camZ, 0.0, 0.0, 0.0, 50.0, false, 0)
    PointCamAtCoord(temp, target.x, target.y, target.z)
    SetCamActiveWithInterp(temp, shop.cam, 450, 1, 1)
    DestroyCam(shop.cam, false)
    shop.cam = temp
end

local function startCamera()
    local p = ped()
    local coords = GetEntityCoords(p)

    shop.orbit, shop.zoom = 0.0, 1.0

    shop.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        coords.x, coords.y, coords.z + 0.2, 0.0, 0.0, 0.0, 50.0, false, 0)

    SetCamActive(shop.cam, true)
    RenderScriptCams(true, true, 400, true, true)
    aimCamera('full', true)

    -- Idle camera: the engine starts a slow camera drift after a few seconds of standing still and overrides scripted cams. InvalidateIdleCam must be called every frame to hold it off.
    CreateThread(function()
        while shop.cam do
            Wait(0)
            InvalidateIdleCam()
            InvalidateVehicleIdleCam()
        end
    end)
end

local function stopCamera()
    if not shop.cam then return end
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(shop.cam, true)
    shop.cam = nil
end

-- Opening and closing

-- Restore the original outfit.
-- BS.Outfit.Apply takes (ped, outfit); it needs the ped because bs_multichar also uses it for the preview ped. Always pass both arguments.
local function restore()
    if shop.snapshot then
        pcall(function() exports.bs_core:ApplyOutfit(PlayerPedId(), shop.snapshot) end)
    end
end

local function close(keep)
    if not shop.open then return end
    shop.open = false
    WardrobeIsOpen = false

    if not keep then restore() end

    -- Done before unfreezing: a looped anim left on an unfrozen ped would walk them out of the shop with hands up.
    if shop.pose then ClearPedTasks(ped()); shop.pose = nil end

    stopCamera()
    send({ action = 'wardrobe', state = 'close' })
    SetNuiFocus(false, false)
    FreezeEntityPosition(ped(), false)
    TriggerEvent('bs:ui:closed', 'wardrobe')
    nudgeTracker()

    -- Persist only what was paid for. bs_core's outfit layer saves the ped to character metadata, so pushing after a purchase keeps the clothes across relogs, and skipping it on cancel stops its 60-second autosave from saving a browsing session.
    if keep then TriggerEvent('bs:outfit:push') end

    shop.npcId = nil
    shop.snapshot = nil
end

function OpenWardrobe(npcId)
    if shop.open or not npcId then return end

    local result = BSB.Await('wardrobe:open', 5000, npcId)
    if not result or not result.ok then
        -- Mirror of the hand-off in cl_main.lua. If a stale option sends a non-clothing npc here, the server says so, so fall through to the menu that npc actually has.
        local reason = result and result.reason or ''
        if reason:find('does not sell clothes') and OpenNpcMenu then
            return OpenNpcMenu(npcId)
        end

        say(L('trd.cant_shop', { why = result and result.reason or L('trd.timeout') }))
        return
    end

    shop.open = true
    shop.ready = false
    shop.npcId = npcId
    shop.autoArms = true
    shop.pose = nil
    shop.who = { vip = result.vip, level = result.level }

    -- The server's gender decides what the shop charges and stores; the ped's model decides what is on screen. If they disagree the model wins here so names and bare drawables match the mesh.
    shop.gender = genderOf(ped())

    -- Snapshot before anything is previewed. Everything depends on this.
    local ok, snap = pcall(function() return exports.bs_core:CaptureOutfit() end)
    shop.snapshot = ok and snap or nil

    local cats = enumerate(result.categories)

    send({
        action = 'wardrobe', state = 'open',
        label = result.label,
        cash = result.cash,
        vip = result.vip,
        level = result.level,
        gender = shop.gender,
        owned = result.owned,
        outfits = result.outfits,
        maxOutfits = result.maxOutfits,
        discount = result.discount,
        poses = Wardrobe.Poses,
        rules = result.rules,
        basePrice = result.basePrice,
        categories = cats,
    })

    -- Nothing is taken from the player until the panel confirms it is on screen. Freezing the ped and taking NUI focus first could leave a player stuck if the page failed to load, so wait for the NUI handshake.
    local waited = 0
    while not shop.ready and waited < 2500 do
        Wait(50)
        waited = waited + 50

        -- They walked off, died, or something else took the screen.
        if not shop.open then return end
    end

    if not shop.ready then
        shop.open = false
        shop.npcId = nil
        shop.snapshot = nil
        say('The wardrobe UI did not load. ^7[no answer from the page - '
            .. 'reconnect to refresh the NUI cache, or check F8 for a script error]')
        return
    end

    WardrobeIsOpen = true
    nudgeTracker()

    FreezeEntityPosition(ped(), true)
    startCamera()
    SetNuiFocus(true, true)
    TriggerEvent('bs:ui:opened', 'wardrobe')
end

-- NUI

-- The panel confirms it rendered. This handshake decides whether the player is taken over (see OpenWardrobe).
RegisterNUICallback('wardrobeReady', function(_, cb)
    shop.ready = true
    cb({ ok = true })
end)

-- What the ped is wearing in this category, in the shape the panel keeps.
local function readBack(cat)
    local p = ped()
    if cat.kind == 'prop' then
        local d = GetPedPropIndex(p, cat.index)
        return { ok = true, drawable = d, texture = GetPedPropTextureIndex(p, cat.index),
                 textures = d >= 0 and GetNumberOfPedPropTextureVariations(p, cat.index, d) or 0,
                 autoArms = shop.autoArms }
    end

    local d = GetPedDrawableVariation(p, cat.index)
    return { ok = true, drawable = d, texture = GetPedTextureVariation(p, cat.index),
             textures = GetNumberOfPedTextureVariations(p, cat.index, d),
             autoArms = shop.autoArms }
end

-- Live preview. Free and not reported anywhere; the bill is computed from the diff at confirm time.
RegisterNUICallback('wardrobeWear', function(data, cb)
    local cat = Wardrobe.ByCategory[data and data.category]
    if not cat then return cb({ ok = false }) end

    wear(cat, data.drawable, data.texture, data.remove)

    -- Return what the ped actually has so the panel's counters follow the clamping. If the top moved the arms too, the arms row is updated as well.
    local answer = readBack(cat)
    if cat.arms and shop.autoArms then
        local arms = Wardrobe.ByCategory['arms']
        if arms then answer.also = { arms = readBack(arms) } end
    end
    cb(answer)
end)

-- Give arms back to the shop's control after a manual pick.
RegisterNUICallback('wardrobeAutoArms', function(_, cb)
    shop.autoArms = true

    -- Re-apply the current top so the pairing takes effect right away.
    local top = Wardrobe.ByCategory['top']
    if top then
        local p = ped()
        wear(top, GetPedDrawableVariation(p, top.index), GetPedTextureVariation(p, top.index))
        shop.autoArms = true   -- wear() does not clear it for the top, but be explicit
    end

    local arms = Wardrobe.ByCategory['arms']
    cb({ ok = true, autoArms = true, arms = arms and readBack(arms) or nil })
end)

-- Category changed - move the camera to that body part.
RegisterNUICallback('wardrobeFocus', function(data, cb)
    local cat = Wardrobe.ByCategory[data and data.category]
    shop.focus = cat and cat.focus or 'full'
    aimCamera(shop.focus, false)
    cb({ ok = true })
end)

-- Turning. `mode` is 'orbit' (camera moves around, the drag) or 'ped' (character turns, the arrows). See shop.orbit.
RegisterNUICallback('wardrobeTurn', function(data, cb)
    local by = tonumber(data and data.by) or 0

    if (data and data.mode) == 'ped' then
        SetEntityHeading(ped(), (GetEntityHeading(ped()) + by) % 360.0)
    else
        shop.orbit = (shop.orbit + by) % 360.0
    end

    -- Camera depends on ped facing and orbit, so either change re-places it. Instant, since it runs per mouse-move.
    aimCamera(shop.focus or 'full', true)
    cb({ ok = true })
end)

-- Hold a pose to judge the arms. `pose` nil (or the id already held) stands the ped up again, since the panel buttons act as a toggle group.
RegisterNUICallback('wardrobePose', function(data, cb)
    local wanted = data and data.pose
    if wanted == shop.pose then wanted = nil end

    local ok = setPose(wanted)
    cb({ ok = true, pose = shop.pose, missing = (wanted ~= nil and not ok) })
end)

RegisterNUICallback('wardrobeZoom', function(data, cb)
    local by = tonumber(data and data.by) or 0
    shop.zoom = math.max(0.45, math.min(1.8, (shop.zoom or 1.0) + by))
    aimCamera(shop.focus or 'full', true)
    cb({ ok = true })
end)

RegisterNUICallback('wardrobeCancel', function(_, cb)
    close(false)
    cb({ ok = true })
end)

RegisterNUICallback('wardrobeBuy', function(data, cb)
    if not shop.open then return cb({ ok = false, reason = 'not open' }) end
    if not shop.npcId then
        return cb({ ok = false, reason = 'test fitting - nothing is really for sale' })
    end

    CreateThread(function()
        local result = BSB.Await('wardrobe:buy', 8000, shop.npcId, data and data.changes)

        if result and result.ok then
            say(result.spent > 0 and L('trd.paid', { n = result.spent }) or L('trd.done'))
            close(true)    -- keep what is on the ped, and persist it
        end

        cb(result or { ok = false, reason = 'no response from server (timeout)' })
    end)
end)

-- Outfits

-- Wearing a saved outfit is local and free. The server refuses to save outfits containing unowned items (wardrobe:outfitSave), so every garment is already paid for and the diff is empty; the usual Confirm still happens server-side.
RegisterNUICallback('wardrobeOutfitWear', function(data, cb)
    local parts = data and data.parts
    if type(parts) ~= 'table' then return cb({ ok = false }) end

    local applied = {}
    for categoryId, part in pairs(parts) do
        local cat = Wardrobe.ByCategory[categoryId]
        if cat then
            wear(cat, part.drawable, part.texture, (tonumber(part.drawable) or 0) < 0)
            applied[categoryId] = readBack(cat)
        end
    end

    cb({ ok = true, applied = applied, autoArms = shop.autoArms })
end)

RegisterNUICallback('wardrobeOutfitSave', function(data, cb)
    if not shop.npcId then
        return cb({ ok = false, reason = 'test fitting - nothing is saved' })
    end

    CreateThread(function()
        local r = BSB.Await('wardrobe:outfitSave', 6000,
            shop.npcId, data and data.name, data and data.parts)
        cb(r or { ok = false, reason = 'no response from server (timeout)' })
    end)
end)

RegisterNUICallback('wardrobeOutfitDelete', function(data, cb)
    CreateThread(function()
        local r = BSB.Await('wardrobe:outfitDelete', 6000, data and data.id)
        cb(r or { ok = false, reason = 'no response from server (timeout)' })
    end)
end)

-- Money while the shop is open

-- Cash is read once in wardrobe:open, so a balance change while in the shop left Confirm disabled on a stale value. The panel now gets a refreshed figure while open.
RegisterNetEvent('bs:player:money', function(account, balance)
    if not shop.open then return end
    if account ~= 'cash' then return end
    send({ action = 'wardrobe', state = 'cash', cash = tonumber(balance) or 0 })
end)

-- Raised by the dot option cl_peds registers on clothing peds. bs_interactions wraps option args in one payload table (see Target.Run), so the npc id arrives as payload.args.
RegisterNetEvent('bs:traders:wardrobe', function(payload)
    OpenWardrobe(payload and payload.args)
end)

-- Safety

-- Every way a fitting can end without a decision restores the old clothes, so a player who dies in the shop is not revived in something they never bought.
AddEventHandler('bs:ui:opened', function(what)
    if what ~= 'wardrobe' and shop.open then close(false) end
end)

AddEventHandler('bs:ui:panic', function() close(false) end)
AddEventHandler('bs:hook:player:unloaded', function() close(false) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if shop.open then
        restore()
        stopCamera()
        SetNuiFocus(false, false)
        FreezeEntityPosition(ped(), false)
    end
end)

CreateThread(function()
    while true do
        Wait(250)
        -- Dying with the menu open cannot be caught by the handlers above, since no event is raised for it here.
        if shop.open and IsEntityDead(ped()) then close(false) end
    end
end)

-- Escape hatch that does not depend on the UI: a plain chat command that restores the player from any state this resource can leave them in (no NUI, focus or page needed).
RegisterCommand('unstick', function()
    local p = ped()

    if shop.open or shop.cam then
        restore()
        stopCamera()
        shop.open, shop.ready, shop.npcId, shop.snapshot = false, false, nil, nil
        WardrobeIsOpen = false
        nudgeTracker()
        send({ action = 'wardrobe', state = 'close' })
    end

    SetNuiFocus(false, false)
    FreezeEntityPosition(p, false)
    say('Released.')
end, false)
TriggerEvent('chat:addSuggestion', '/unstick',
    'Release the camera, the freeze and the mouse if a menu leaves you stuck')

-- Panel-only test: opens the wardrobe UI with a small fake payload and no server calls (no npc, nothing can be bought or saved). Separates a broken page from a broken open sequence. Otherwise a real session (snapshot, camera, focus).
RegisterCommand('wardrobetest', function()
    if shop.open then return say('Already open.') end

    shop.open = true
    shop.ready = true
    shop.npcId = nil
    shop.focus = 'full'
    shop.autoArms = true
    shop.gender = genderOf(ped())

    local ok, snap = pcall(function() return exports.bs_core:CaptureOutfit() end)
    shop.snapshot = ok and snap or nil

    send({
        action = 'wardrobe', state = 'open',
        label = 'UI TEST - not a real shop',
        cash = 9999,
        vip = false,
        level = 1,
        gender = shop.gender,
        owned = {},
        outfits = {},
        maxOutfits = 0,
        poses = Wardrobe.Poses,
        rules = {},
        basePrice = 100,
        categories = enumerate(Wardrobe.Categories),
    })

    WardrobeIsOpen = true
    nudgeTracker()

    FreezeEntityPosition(ped(), true)
    startCamera()
    SetNuiFocus(true, true)
    TriggerEvent('bs:ui:opened', 'wardrobe')

    say('Test fitting open. Cancel restores your clothes; Confirm is refused. /unstick if stuck.')
end, false)
TriggerEvent('chat:addSuggestion', '/wardrobetest',
    'Open the clothing panel on its own, without the shop, to test the UI')
