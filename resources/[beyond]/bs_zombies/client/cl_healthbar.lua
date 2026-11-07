-- bs_zombies - health bar over the zombie you are aiming at. Off by default;

local H = Zombies.HealthBars or {}

local enabled = false
local privileged = false

-- Palette: everyone gets the server palette;
local classic = false
local linger = (H.linger or 5.0) * 1000.0

-- The switches live in bs_vip, and are PUSHED here

-- Never yields: an export called from another resource runs on the caller's thread
local custom = nil   -- { high, mid, low } rgb, or nil for the house palette

local function rgbOf(hex)
    if type(hex) ~= 'string' then return nil end
    local r, g, b = hex:match('^#(%x%x)(%x%x)(%x%x)$')
    if not r then return nil end
    return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

AddEventHandler('bs:combatfx:options', function(o)
    if type(o) ~= 'table' then return end
    privileged = true
    linger = (tonumber(o.healthBarLinger) or H.linger or 5.0) * 1000.0
    if o.zombieHealthBars ~= nil then enabled = o.zombieHealthBars == true end
    classic = false

    custom = nil
    if o.custom == true then
        local hi, mid, lo = rgbOf(o.hbHigh), rgbOf(o.hbMid), rgbOf(o.hbLow)
        if hi or mid or lo then
            local base = H.vipColours or H.colours or {}
            custom = { high = hi or base.high, mid = mid or base.mid, low = lo or base.low }
        end
    end
end)

-- Health bars are a normal setting for everyone now (no staff-only gate).

-- The toggle

-- Never yields. See the note above.
local function setEnabled(on)
    on = on and true or false

    -- Goes through the settings store so the choice is remembered.
    if Zombies.SetFxOption then Zombies.SetFxOption('zombieHealthBars', on) end
    enabled = on
    TriggerEvent('bs:ui:notify', {
        type = 'info',
        message = enabled and L('zed.hb_on') or L('zed.hb_off'),
        duration = 2200,
    })
    return true
end

-- Any VIP or staff member can toggle this for themselves from chat.
RegisterCommand('bs_zombiehp', function()
    -- Just got VIP and the 60s refresh has not run?
    CreateThread(function()
        setEnabled(not enabled)
    end)
end, false)

exports('SetHealthBarsVisible', function(on) return setEnabled(on) end)
exports('HealthBarsVisible', function() return enabled end)

-- Drawing

-- Target: GetEntityPlayerIsFreeAimingAt only answers
local function aimedAt()
    local ok, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
    if not ok or not entity or entity == 0 then return nil end
    if not DoesEntityExist(entity) then return nil end
    return entity
end

--- Seen-at times, by zombie id. A bar is drawn while now - seen < linger.
local Seen = {}

-- Segmented bar: ten notches filled from the left in the HUD colours
local function drawBar(x, y, w, h, frac, rgb, alpha)
    frac = math.max(0.0, math.min(1.0, frac))

    local segments = math.max(1, math.floor(H.segments or 10))
    local gap = H.segmentGap or 0.0009
    -- The tray matches the bar (see HealthBars.vipBacking).
    local useClassic = classic and privileged
    local back = (not useClassic and H.vipBacking) or H.backing or { 10, 10, 9 }

    -- Dark plate behind the notches, slightly larger.
    DrawRect(x, y, w + gap * 2, h + 0.0022, back[1], back[2], back[3],
        math.floor(170 * alpha))

    local segW = (w - gap * (segments - 1)) / segments
    local left = x - w / 2.0

    -- Partial notches are drawn at their true fraction, so the last sliver of health does not look like a full notch
    local filled = frac * segments

    for i = 0, segments - 1 do
        local fill = math.max(0.0, math.min(1.0, filled - i))
        if fill > 0.0 then
            local drawnW = segW * fill
            local cx = left + i * (segW + gap) + drawnW / 2.0
            DrawRect(cx, y, drawnW, h, rgb[1], rgb[2], rgb[3],
                math.floor(235 * alpha))
        end
    end
end

--- Centred, small, with the same outline every other in-world label uses.
local function drawLabel(text, x, y, scale, alpha, r, g, b)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(r, g, b, math.floor(240 * alpha))
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

--- "Walker", "Brute" - whatever the archetype calls itself, never the model.
local function nameFor(entry)
    local def = entry.def
    if def and def.label then return tostring(def.label):upper() end
    return 'WALKER'
end

CreateThread(function()
    while true do
        if not enabled then
            -- Nothing to draw and nothing to remember.
            if next(Seen) then Seen = {} end
            Wait(400)
            goto continue
        end
        Wait(0)

        local me = PlayerPedId()
        local now = GetGameTimer()
        local range = H.range or 30.0
        local plyCoords = GetEntityCoords(me)

        -- 1. Is a walker in the sights right now? Mark it seen.
        local target = aimedAt()
        if target then
            for id, entry in pairs(Zed.live) do
                if entry.ped == target then
                    Seen[id] = now
                    break
                end
            end
        end

        -- 2. Draw everything still inside its linger.
        for id, seenAt in pairs(Seen) do
            local age = now - seenAt
            local entry = Zed.live[id]

            if age > linger or not entry or not entry.ped
               or not DoesEntityExist(entry.ped) or entry.dying
               or IsEntityDead(entry.ped) then
                Seen[id] = nil
                goto nextBar
            end

            local zCoords = GetEntityCoords(entry.ped)
            local distance = #(plyCoords - zCoords)

            -- Still range and sight gated, so a bar never shows through a wall.
            if distance >= range
               or not HasEntityClearLosToEntity(me, entry.ped, 17) then
                goto nextBar
            end

            do
                local headIdx = GetPedBoneIndex(entry.ped, 31086)
                local headPos = (headIdx and headIdx ~= -1)
                    and GetWorldPositionOfEntityBone(entry.ped, headIdx)
                    or (zCoords + vector3(0.0, 0.0, 0.85))

                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(
                    headPos.x, headPos.y, headPos.z + (H.lift or 0.45))

                if onScreen then
                    -- Server max health (difficulty scales it), then the type default.
                    local max = (entry.rec and tonumber(entry.rec.mhp)) or (entry.def and entry.def.health) or 100
                    local hp = entry.hp or max
                    local frac = max > 0 and (hp / max) or 0.0

                    -- The last second of the linger fades out.
                    local fade = (H.fadeFor or 1.0) * 1000.0
                    local alpha = 1.0
                    if age > linger - fade then
                        alpha = math.max(0.0, (linger - age) / math.max(1.0, fade))
                    end

                    -- Server palette by default; players who chose "classic" in the F7 menu get the neutral one.
                    local useClassic = classic and privileged
                    local c = custom or (not useClassic and H.vipColours) or H.colours or {}
                    local rgb = c.low or { 150, 52, 40 }
                    if frac > 0.6 then rgb = c.high or { 216, 210, 194 }
                    elseif frac > 0.28 then rgb = c.mid or { 200, 118, 58 } end

                    -- Shrinks with distance (screen space draw), down to a third at the far edge of range.
                    local full = H.fullSizeUpTo or 25.0
                    local scale = 1.0
                    if distance > full then
                        local t = 1.0 - ((distance - full) / math.max(1.0, range - full))
                        scale = 0.34 + 0.66 * math.max(0.0, math.min(1.0, t))
                    end

                    drawBar(sx, sy, (H.width or 0.055) * scale,
                        (H.height or 0.0075) * scale, frac, rgb, alpha)

                    if distance <= (H.textUpTo or 70.0) then
                        -- Text scales too and fades over the last stretch.
                        local textRange = H.textUpTo or 70.0
                        local textAlpha = alpha
                        if distance > textRange * 0.6 then
                            textAlpha = alpha * math.max(0.0,
                                1.0 - ((distance - textRange * 0.6) / (textRange * 0.4)))
                        end

                        if textAlpha > 0.02 then
                            if H.showName then
                                drawLabel(nameFor(entry), sx, sy - 0.030 * scale,
                                    0.30 * scale, textAlpha, 216, 210, 194)
                            end
                            if H.showNumbers then
                                drawLabel(('%d / %d'):format(math.max(0, math.floor(hp)), max),
                                    sx, sy + 0.006 * scale, 0.24 * scale, textAlpha,
                                    rgb[1], rgb[2], rgb[3])
                            end
                        end
                    end
                end
            end

            ::nextBar::
        end

        ::continue::
    end
end)
