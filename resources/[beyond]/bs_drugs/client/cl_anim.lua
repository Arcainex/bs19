-- Use animations + props.

DrugAnim = {}

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function attachProp(ped, a)
    if not a.prop then return nil end
    local model = joaat(a.prop)
    RequestModel(model)
    local t = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(model) then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(model, c.x, c.y, c.z + 0.2, false, true, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, a.bone), a.pos.x, a.pos.y, a.pos.z,
        a.rot.x, a.rot.y, a.rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

local function dropProp(obj)
    if obj and DoesEntityExist(obj) then DetachEntity(obj, true, true); DeleteEntity(obj) end
end
DrugAnim.DropProp = dropProp

-- One-shot use anim (snort/inject/pill/joint).
function DrugAnim.Play(key)
    local a = Drugs.Anims[key]
    if not a or not a.dict then return end
    CreateThread(function()
        local ped = PlayerPedId()
        if not loadDict(a.dict) then return end
        local obj = attachProp(ped, a)
        TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, a.time, a.flag or 49, 0.0, false, false, false)
        Wait(a.time)
        StopAnimTask(ped, a.dict, a.clip, 2.0)
        dropProp(obj)
        RemoveAnimDict(a.dict)
    end)
end

-- Cigarette: enter -> looping base -> exit. shouldStop() returns true to end early.
function DrugAnim.Smoke(duration, shouldStop, onEnd)
    local a = Drugs.Anims.smoke
    CreateThread(function()
        local ped = PlayerPedId()
        for _, part in ipairs({ a.enter, a.base, a.exit }) do loadDict(part.dict) end
        local obj = attachProp(ped, a)
        local stopped = false
        TaskPlayAnim(ped, a.enter.dict, a.enter.clip, 3.0, 3.0, a.enter.time, a.flag, 0.0, false, false, false)
        local untilAt = GetGameTimer() + duration * 1000
        local enterEnd = GetGameTimer() + a.enter.time
        local looping = false
        while GetGameTimer() < untilAt do
            Wait(100)
            ped = PlayerPedId()
            if shouldStop() then stopped = true; break end
            if not looping and GetGameTimer() >= enterEnd then
                TaskPlayAnim(ped, a.base.dict, a.base.clip, 3.0, 3.0, -1, a.flag, 0.0, false, false, false)
                looping = true
            elseif looping and not IsEntityPlayingAnim(ped, a.base.dict, a.base.clip, 3) then
                TaskPlayAnim(ped, a.base.dict, a.base.clip, 3.0, 3.0, -1, a.flag, 0.0, false, false, false)
            end
        end
        StopAnimTask(ped, a.base.dict, a.base.clip, 2.0)
        if not stopped and not IsEntityDead(ped) then
            TaskPlayAnim(ped, a.exit.dict, a.exit.clip, 3.0, 3.0, a.exit.time, a.flag, 0.0, false, false, false)
            Wait(a.exit.time)
        end
        dropProp(obj)
        onEnd(stopped)
    end)
end
