-- bs_scenes - notes are drawn as 3D text where they were written (no entity, prop or collision).
-- The draw loop only considers notes already filtered to a radius, and draws only those in front of the camera within the fade distance.

local notes = {}        -- [id] = note
local nearby = {}       -- the small list the draw loop walks
local writing = false

--------------------------------------------------------------------------------
-- Getting them
--------------------------------------------------------------------------------

local function refresh()
    if not exports.bs_core:IsLoaded() then return end

    local at = GetEntityCoords(PlayerPedId())
    local answer = BSB.Await('scenes:around', 8000,
        at.x, at.y, at.z, Scenes.Settings.streamRadius or 300.0)

    if not answer or not answer.ok then return end

    notes = {}
    for _, note in ipairs(answer.scenes or {}) do
        notes[note.id] = note
    end
end

RegisterNetEvent('bs:scenes:added', function(note)
    if type(note) ~= 'table' or not note.id then return end
    notes[note.id] = note
end)

RegisterNetEvent('bs:scenes:removed', function(id)
    notes[tonumber(id) or -1] = nil
end)

CreateThread(function()
    while true do
        Wait(Scenes.Settings.refreshMs or 20000)
        refresh()
    end
end)

AddEventHandler('bs:hook:player:spawned', function()
    CreateThread(function() Wait(3000); refresh() end)
end)

--------------------------------------------------------------------------------
-- Which ones are worth drawing
--
-- Rebuilt a few times a second rather than every frame: a note twenty metres
-- away does not become relevant between one frame and the next, and walking the
-- whole set at 60fps for that is waste.
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(400)

        local at = GetEntityCoords(PlayerPedId())
        local range = Scenes.Settings.drawDistance or 24.0
        local r2 = range * range

        local list = {}
        for _, note in pairs(notes) do
            local dx, dy, dz = note.x - at.x, note.y - at.y, note.z - at.z
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 <= r2 then
                note.dist = math.sqrt(d2)
                list[#list + 1] = note
            end
        end

        -- Nearest first, so if there are somehow a lot the important ones win.
        table.sort(list, function(a, b) return a.dist < b.dist end)
        while #list > 12 do table.remove(list) end

        nearby = list
    end
end)

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function draw3d(x, y, z, text, colour, alpha)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end

    SetTextScale(0.0, 0.34)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(colour.r, colour.g, colour.b, math.floor(alpha * 255))
    SetTextCentre(true)

    -- The drop shadow keeps pale text readable against a white sky or fire (SetTextDropShadow).
    SetTextDropShadow()
    SetTextOutline()

    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

CreateThread(function()
    while true do
        if #nearby == 0 then
            Wait(300)
        else
            Wait(0)

            local fade = Scenes.Settings.fadeDistance or 14.0
            local range = Scenes.Settings.drawDistance or 24.0

            for _, note in ipairs(nearby) do
                local kind = Scenes.Kinds[note.kind] or Scenes.Kinds.note
                local colour = kind.colour or { r = 216, g = 210, b = 194 }

                -- Full strength up close, fading to nothing at the edge of
                -- range. A note that pops in at full brightness reads as a UI
                -- element; one that fades up reads as something you noticed.
                local alpha = 1.0
                if note.dist > fade then
                    alpha = 1.0 - ((note.dist - fade) / math.max(0.01, range - fade))
                end
                alpha = math.max(0.0, math.min(1.0, alpha))

                if alpha > 0.02 then
                    draw3d(note.x, note.y, note.z + 0.15,
                        (kind.prefix or '') .. note.text, colour, alpha)

                    -- Author line, smaller and dimmer. Only drawn up close.
                    if note.dist < 6.0 then
                        local onScreen, sx, sy = World3dToScreen2d(note.x, note.y, note.z + 0.02)
                        if onScreen then
                            SetTextScale(0.0, 0.24)
                            SetTextFont(4)
                            SetTextColour(140, 134, 118, math.floor(alpha * 200))
                            SetTextCentre(true)
                            SetTextDropShadow()
                            SetTextEntry('STRING')
                            AddTextComponentString('- ' .. (note.author or L('sc.unknown_author')))
                            DrawText(sx, sy)
                        end
                    end
                end
            end
        end
    end
end)

-- Writing

local function write(kind, text)
    if writing then return end
    writing = true

    local ped = PlayerPedId()
    local anim = Scenes.Anim

    if DoesAnimDictExist(anim.dict) then
        if not HasAnimDictLoaded(anim.dict) then RequestAnimDict(anim.dict) end
        local waited = 0
        while not HasAnimDictLoaded(anim.dict) and waited < 1200 do Wait(10); waited = waited + 10 end
        if HasAnimDictLoaded(anim.dict) then
            TaskPlayAnim(ped, anim.dict, anim.clip, 4.0, -4.0,
                Scenes.Settings.writeTime or 4200, anim.flag or 49, 0.0, false, false, false)
        end
    end

    TriggerEvent('bs:ui:notify', { type = 'info', message = L('sc.writing'), duration = 2200 })

    -- Moving away cancels the write.
    local started = GetGameTimer()
    local from = GetEntityCoords(ped)
    local cancelled = false

    while GetGameTimer() - started < (Scenes.Settings.writeTime or 4200) do
        Wait(100)
        if #(GetEntityCoords(ped) - from) > 1.6 or IsEntityDead(ped) then
            cancelled = true
            break
        end
    end

    ClearPedTasks(ped)

    if cancelled then
        writing = false
        return TriggerEvent('bs:ui:notify', {
            type = 'warn', message = L('sc.stopped'), duration = 2400,
        })
    end

    local result = BSB.Await('scenes:write', 8000, text, kind)
    writing = false

    TriggerEvent('bs:ui:notify', {
        type = (result and result.ok) and 'success' or 'warn',
        message = (result and result.ok) and L('sc.left')
            or ((result and result.error) or L('sc.no_take')),
        duration = 3200,
    })
end

-- Commands

--- /note <text>          leaves a plain note
--- /warn <text>          leaves a warning
--- /safe <text>          marks somewhere cleared
--- /supplies <text>      marks something worth coming back for
local function command(kind)
    return function(_, args, raw)
        -- `raw` keeps the spacing as typed; args would collapse it.
        local text = raw:gsub('^/?%S+%s*', '')

        if text == '' then
            return TriggerEvent('bs:ui:notify', {
                type = 'info',
                message = L('sc.type', { cmd = kind }),
                duration = 3200,
            })
        end

        CreateThread(function() write(kind, text) end)
    end
end

RegisterCommand('note',     command('note'),     false)
RegisterCommand('warn',     command('warning'),  false)
RegisterCommand('safe',     command('safe'),     false)
RegisterCommand('supplies', command('supplies'), false)

-- Erases the nearest note you are allowed to erase.
RegisterCommand('erase', function()
    CreateThread(function()
        local at = GetEntityCoords(PlayerPedId())

        local best, bestDist
        for _, note in pairs(notes) do
            local d = #(vector3(note.x, note.y, note.z) - at)
            if d < 3.0 and (not bestDist or d < bestDist) then
                best, bestDist = note, d
            end
        end

        if not best then
            return TriggerEvent('bs:ui:notify', {
                type = 'info', message = L('sc.none_near'), duration = 2400,
            })
        end

        local result = BSB.Await('scenes:erase', 6000, best.id)

        TriggerEvent('bs:ui:notify', {
            type = (result and result.ok) and 'success' or 'warn',
            message = (result and result.ok) and L('sc.rubbed')
                or ((result and result.error) or 'It will not come off.'),
            duration = 2800,
        })
    end)
end, false)

exports('Nearby', function() return nearby end)
exports('Write', function(kind, text) CreateThread(function() write(kind, text) end) end)
