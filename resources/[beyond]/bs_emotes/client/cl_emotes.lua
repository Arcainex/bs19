-- bs_emotes - the emote layer.
-- An animation is loaded, played and cleaned up here. A scenario is handed to the engine (loops properly, brings its own props), which is why resting/working emotes are scenarios.
-- Everything cancels the same way: move (unless upper body), cancel key, damage, or death.

local Playing = nil     -- { id, upper, dict }
local cancelHeld = false

--------------------------------------------------------------------------------
-- Lookup
--------------------------------------------------------------------------------

local index = {}

CreateThread(function()
    for _, category in ipairs(Emotes.List or {}) do
        for _, item in ipairs(category.items or {}) do
            index[item.id] = item
        end
    end
end)

--------------------------------------------------------------------------------
-- Playing
--------------------------------------------------------------------------------

local function dropProps()
    if not Playing or not Playing.props then return end
    for _, obj in ipairs(Playing.props) do
        if DoesEntityExist(obj) then
            DetachEntity(obj, true, false)
            DeleteEntity(obj)
        end
    end
    Playing.props = nil
end

--- Spawns a prop and glues it to a bone. Returns the entity or nil.
local function attachProp(ped, model, bone, place)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local waited = 0
    while not HasModelLoaded(hash) and waited < 2000 do Wait(10); waited = waited + 10 end
    if not HasModelLoaded(hash) then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z + 0.2, true, true, true)
    SetModelAsNoLongerNeeded(hash)
    if obj == 0 then return nil end
    local p = place or {}
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, bone or 60309),
        p[1] or 0.0, p[2] or 0.0, p[3] or 0.0, p[4] or 0.0, p[5] or 0.0, p[6] or 0.0,
        true, true, false, true, 1, true)
    return obj
end

local function stop()
    if not Playing then return end
    local ped = PlayerPedId()

    dropProps()
    ClearPedTasks(ped)
    if Playing.dict then RemoveAnimDict(Playing.dict) end

    Playing = nil
    TriggerEvent('bs:emotes:stopped')
end

--- VIP emotes: pcall so a stopped bs_vip just means locked.
function EmoteVipOk()
    if GetResourceState('bs_vip') ~= 'started' then return false end
    local ok, yes = pcall(function() return exports.bs_vip:HasPerk(Emotes.VipEmotePerk or 'exclusiveEmotes') end)
    return ok and yes == true
end

local function play(id)
    local item = index[id]
    if not item then return false, L('emo.unknown') end
    if item.vip and not EmoteVipOk() then return false, L('emo.vip_emote') end

    local ped = PlayerPedId()
    if IsPedDeadOrDying(ped, true) then return false, L('emo.not_now2') end
    if IsPedInAnyVehicle(ped, false) then return false, L('emo.not_vehicle') end

    -- Playing something already? The second press stops it.
    if Playing and Playing.id == id then
        stop()
        return true
    end
    stop()

    if item.scenario then
        TaskStartScenarioInPlace(ped, item.scenario, 0, true)
        Playing = { id = id, upper = false }
        TriggerEvent('bs:emotes:started', id)
        return true
    end

    RequestAnimDict(item.dict)
    local waited = 0
    while not HasAnimDictLoaded(item.dict) and waited < 3000 do
        Wait(10); waited = waited + 10
    end
    if not HasAnimDictLoaded(item.dict) then
        return false, 'that animation is not on this build'
    end

    -- Flags: 1 = loop, 16 = upper body only, 32 = player can still turn, 2 = hold the last frame. Entries with no loop/duration keep looping.
    local loops = item.loop or (item.duration == nil and not item.stuck and not item.once)
    local flag
    if item.stuck then flag = 50
    elseif item.upper then flag = loops and 49 or 48
    else flag = loops and 1 or 0 end
    TaskPlayAnim(ped, item.dict, item.clip, 4.0, -4.0, item.duration or -1, flag, 0.0, false, false, false)

    Playing = { id = id, upper = item.upper, dict = item.dict, clip = item.clip, loops = loops or item.stuck, started = GetGameTimer() }
    if item.prop or item.prop2 then
        Playing.props = {}
        if item.prop then Playing.props[#Playing.props + 1] = attachProp(ped, item.prop, item.bone, item.place) end
        if item.prop2 then Playing.props[#Playing.props + 1] = attachProp(ped, item.prop2, item.bone2, item.place2) end
    end
    if item.duration then
        local mine = Playing
        SetTimeout(item.duration, function() if Playing == mine then stop() end end)
    end
    TriggerEvent('bs:emotes:started', id)
    return true
end

-- Shared with cl_emotemenu.lua (same resource, same Lua state): the menu and
-- the favourites wheel play through exactly this code, so every rule above -
-- vehicle, dead, second press stops - applies to them too.
EmoteCore = {
    play    = play,
    stop    = stop,
    index   = index,
    current = function() return Playing and Playing.id or nil end,
}

--------------------------------------------------------------------------------
-- Cancelling
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        if Playing then
            Wait(120)
            -- stop() may have run during the Wait
            if not Playing then goto continue end
            local ped = PlayerPedId()

            if IsPedDeadOrDying(ped, true) or IsPedInAnyVehicle(ped, false) then
                stop()
            elseif Playing.dict and not Playing.loops and GetGameTimer() - Playing.started > 600
                and not IsEntityPlayingAnim(ped, Playing.dict, Playing.clip, 3) then
                stop()
            elseif not Playing then
                -- ended by stop() elsewhere during the Wait above
            elseif Emotes.Settings.cancelOnMove and not Playing.upper then
                -- Check actual movement, not just the keys: cars, walkers and ragdolls can move the ped, and a held key the engine ignores should not cancel.
                -- A key press is intent (honour it at once) and real speed is fact; either ends a full-body emote.
                local moved = GetEntitySpeed(ped) > 0.4
                    or IsPedRagdoll(ped)
                    or IsControlPressed(0, 32) or IsControlPressed(0, 33)
                    or IsControlPressed(0, 34) or IsControlPressed(0, 35)
                    or IsControlJustPressed(0, 22)   -- jump

                if moved then stop() end
            end
        else
            Wait(400)
        end
        ::continue::
    end
end)

-- Chat commands: /e sit, /e stop, /emotes for the list. Names match loosely by id, label, then prefix (/e bin finds binoculars).

--- Best match for what somebody typed, or nil.
local function findEmote(query)
    query = (query or ''):lower():gsub('%s+', '')
    if query == '' then return nil end

    -- Exact id first, then exact label, then prefix, then anywhere.
    if index[query] then return index[query] end

    local prefix, contains
    for id, item in pairs(index) do
        local label = (item.label or ''):lower():gsub('%s+', '')
        if label == query then return item end
        if not prefix and (id:sub(1, #query) == query or label:sub(1, #query) == query) then
            prefix = item
        end
        if not contains and (id:find(query, 1, true) or label:find(query, 1, true)) then
            contains = item
        end
    end

    return prefix or contains
end

local function notify(kind, message)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = 3000 })
end

local function listEmotes()
    for _, category in ipairs(Emotes.List or {}) do
        local names = {}
        for _, item in ipairs(category.items or {}) do
            names[#names + 1] = item.id .. (item.upper and '*' or '')
        end
        print(('^3[%s]^7 %s'):format((category.label or ''):upper(), table.concat(names, ', ')))
    end
    print('^7( * = you can keep walking )')
    notify('info', L('emote.list_printed'))
end

local function emoteCommand(_, args)
    local query = args and args[1]

    if not query or query == '' then
        return notify('info', L('emo.try'))
    end

    local lowered = query:lower()
    if lowered == 'stop' or lowered == 'c' or lowered == 'cancel' then
        stop()
        return
    end
    if lowered == 'list' or lowered == 'help' then return listEmotes() end

    local item = findEmote(query)
    if not item then
        return notify('warn', L('emo.no_such', { name = query }))
    end

    CreateThread(function()
        local ok, err = play(item.id)
        if not ok then notify('warn', err or L('emo.not_now')) end
    end)
end

RegisterCommand('e', emoteCommand, false)
RegisterCommand('emote', emoteCommand, false)
RegisterCommand('emotes', function() listEmotes() end, false)
RegisterCommand('emotestop', function() stop() end, false)

RegisterCommand('bs_cancelemote', function()
    stop()
end, false)
RegisterKeyMapping('bs_cancelemote', L('emote.key_cancel'), 'keyboard', 'DELETE')

AddEventHandler('bs:hook:player:unloaded', stop)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then stop() end
end)

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

--- Returns ONE table, never two values: multiple return values do not survive
--- an export call reliably, and a silently dropped error message is worse than
--- a slightly wordier signature.
exports('PlayEmote', function(id)
    local ok, err = play(id)
    return { ok = ok and true or false, error = err }
end)
exports('StopEmote', stop)
exports('IsEmoting', function() return Playing ~= nil end)
exports('CurrentEmote', function() return Playing and Playing.id or nil end)

--- The menu asks for this: plain data, safe to send straight into a NUI.
exports('EmoteList', function()
    local out = {}
    for _, category in ipairs(Emotes.List or {}) do
        local items = {}
        for _, item in ipairs(category.items or {}) do
            items[#items + 1] = { id = item.id, label = item.label,
                                  upper = item.upper and true or false,
                                  scenario = (item.scenario or item.prop) and true or false,
                                  vip = item.vip and true or false }
        end
        out[#out + 1] = { id = category.id, label = category.label,
                          group = category.group or 'emotes', items = items }
    end
    return out
end)
