-- bs_mining - the swinging. Registers every node model with the interaction dot, plays the animation, makes noise and asks the server whether the swing counted. It decides nothing: yield, node state and tool wear come from the server.
-- Options use `event` strings, not functions: a closure does not survive the export boundary into bs_interactions, so the option shows but pressing E does nothing.

local busy = false

local function notify(kind, message)
    TriggerEvent('bs:ui:notify', { type = kind, message = message })
end

-- Animation
-- A dict can load and still not contain the clip, in which case TaskPlayAnim silently does nothing. GetAnimDuration returning 0 is the only reliable test, so candidates are tried in order and the first playable one is kept.

local resolved = {}      -- [typeId] = anim | false

local function resolveAnim(typeId, candidates)
    if resolved[typeId] ~= nil then return resolved[typeId] or nil end

    for _, c in ipairs(candidates or {}) do
        if c.dict and DoesAnimDictExist(c.dict) then
            if not HasAnimDictLoaded(c.dict) then RequestAnimDict(c.dict) end

            local waited = 0
            while not HasAnimDictLoaded(c.dict) and waited < 1200 do
                Wait(10); waited = waited + 10
            end

            if HasAnimDictLoaded(c.dict) then
                local ok, duration = pcall(GetAnimDuration, c.dict, c.clip)
                if ok and type(duration) == 'number' and duration > 0.0 then
                    resolved[typeId] = c
                    print(('^2[BeyondSurvival]^7 (mining) %s animation: %s / %s')
                        :format(typeId, c.dict, c.clip))
                    return c
                end
            end
        end
    end

    resolved[typeId] = false
    print(('^3[BeyondSurvival]^7 (mining) no animation resolved for %s - working will be still')
        :format(typeId))
    return nil
end

-- One swing

-- A node is named by where it is, not by entity handle: props are not networked, so the same rock has a different handle per client.
local function nodeKey(coords)
    return ('%.1f:%.1f:%.1f'):format(coords.x, coords.y, coords.z)
end

local function swing(typeId, def, key, coords)
    local ped = PlayerPedId()
    local anim = resolveAnim(typeId, def.anim)

    if anim then
        TaskPlayAnim(ped, anim.dict, anim.clip, 4.0, -4.0,
            Mining.Settings.swingMs, anim.flag or 49, 0.0, false, false, false)
    end

    exports.bs_interactions:Progress(def.label, Mining.Settings.swingMs)

    -- The noise is the point: every other way to get materials rewards moving, this asks you to stand still making a racket. bs_emotes owns the radius; this only reports what happened and where.
    if GetResourceState('bs_emotes') == 'started' and def.noise then
        pcall(function() exports.bs_emotes:MakeNoise(def.noise, coords) end)
    end

    local waited = 0
    local start = GetEntityCoords(ped)
    local cancelled = false

    while waited < Mining.Settings.swingMs do
        Wait(100)
        waited = waited + 100

        if #(GetEntityCoords(ped) - start) > 2.0 then cancelled = true break end
        if IsEntityDead(ped) then cancelled = true break end
        if IsControlJustPressed(0, 202) then cancelled = true break end   -- backspace
    end

    ClearPedTasks(ped)
    exports.bs_interactions:CancelProgress()

    return not cancelled
end

RegisterNetEvent('bs:mining:work', function(payload)
    local typeId = payload and payload.args and payload.args.type
    local def = typeId and Mining.Types[typeId]
    if not def or busy then return end

    local coords = payload.coords
    if not coords then return end

    CreateThread(function()
        busy = true

        local key = nodeKey(coords)
        local keepGoing = true

        -- Swing until the node is empty, the tool breaks, or you stop. The loop lives here so working a rock is one decision followed by a commitment. Each swing is still validated on its own, both ends.
        while keepGoing do
            local started = BSB.Await('mining:start', 8000, typeId, key)
            if not started or not started.ok then
                busy = false
                return notify('warn', (started and started.error) or L('mn.cant_work'))
            end

            if not swing(typeId, def, key, coords) then
                BSB.Await('mining:abort', 5000, key)
                busy = false
                return
            end

            local result = BSB.Await('mining:swing', 8000, typeId, key)
            if not result or not result.ok then
                busy = false
                return notify('warn', (result and result.error) or L('mn.swing'))
            end

            for _, entry in ipairs(result.given or {}) do
                notify(entry.spilled and 'warn' or 'success',
                    entry.spilled
                        and ('%s x%d - no room in your bag'):format(entry.label, entry.amount)
                        or  ('+%d %s'):format(entry.amount, entry.label))
                Wait(80)
            end

            if result.broke then
                notify('error', L('mn.broke', { tool = def.toolLabel or def.tool }))
                keepGoing = false
            elseif result.exhausted then
                notify('info', L('mn.worked_out'))
                keepGoing = false
            end
        end

        busy = false
    end)
end)

-- Registration

CreateThread(function()
    if not Mining.Settings.enabled then return end

    local excluded = {}
    for _, model in ipairs(Mining.ExcludeModels or {}) do
        excluded[GetHashKey(model)] = true
    end

    for typeId, def in pairs(Mining.Types) do
        local models = {}
        for _, model in ipairs(def.models or {}) do
            if not excluded[GetHashKey(model)] then models[#models + 1] = model end
        end

        if #models > 0 then
            exports.bs_interactions:AddModel(models, { {
                label    = def.label,
                icon     = def.icon or 'tool',
                distance = Mining.Settings.proximity,
                event    = 'bs:mining:work',
                args     = { type = typeId },
            } })
        end
    end
end)
