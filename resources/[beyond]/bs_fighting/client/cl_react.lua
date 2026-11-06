-- bs_fighting - hit reactions. Walkers react on whichever client owns them (the server forwards the request),
-- players react on their own client. Nothing here holds a ped: every pose has a timed end.

FightReact = {}

local function owned(ped)
    if not DoesEntityExist(ped) then return false end
    return not NetworkGetEntityIsNetworked(ped) or NetworkHasControlOfEntity(ped)
end

local function push(ped, dx, dy, force, up)
    if force <= 0 then return end
    ApplyForceToEntity(ped, 1, dx * force, dy * force, up or 0.6, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
end

local function impactSide(ped,dx,dy)
    local forward=GetEntityForwardVector(ped)
    local dot=forward.x*(dx or 0)+forward.y*(dy or 0)
    if dot<-.5 then return 'hit_front'end
    if dot>.5 then return 'hit_back'end
    return forward.x*(dy or 0)-forward.y*(dx or 0)<0 and 'hit_left'or 'hit_right'
end

local function flinch(ped, pose, portion)
    local a = FightAnim.Play(ped, pose, { flag = 0, portion = portion or 0.6, blendIn = 8.0, blendOut = 4.0 })
    FightAnim.Guard(a, 200)
    if a then
        CreateThread(function()
            Wait(40)
            if DoesEntityExist(ped) and not IsEntityDead(ped)
                and not IsPedRagdoll(ped) and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) then
                -- Walker movement can replace the first reaction task in the same frame.
                FightAnim.Play(ped, pose, { flag = 0, portion = portion or 0.6, blendIn = 8.0, blendOut = 4.0 })
            end
        end)
    end
    return a
end

-- Walker (or trainer) reaction. Only on a ped we control.
function FightReact.Ped(ped, kind, force, dx, dy)
    if not owned(ped) or IsEntityDead(ped) then return false end
    force = tonumber(force) or 0.0
    -- bs_zombies: opens a takedown and holds the walker's swings until it is back up
    TriggerEvent('bs:zombies:fightReact', ped, kind)
    CreateThread(function()
        Wait(0)
        if not owned(ped) or IsEntityDead(ped) then return end
        if kind == 'stumble' then
            flinch(ped,impactSide(ped,dx,dy),0.45)
            push(ped, dx, dy, 1.2, 0.0)
        elseif kind == 'stagger' then
            local pose=impactSide(ped,dx,dy)
            flinch(ped,pose=='hit_front'and 'hit_heavy'or pose,0.7)
            push(ped, dx, dy, math.max(2.0, force), 0.0)
        elseif kind == 'down' or kind == 'throw' then
            if IsPedRagdoll(ped) or not CanPedRagdoll(ped) then return end
            local ms = kind == 'throw' and 2600 or 1900
            pcall(SetPedToRagdoll, ped, ms, ms + 400, 0, false, false, false)
            Wait(0)
            push(ped, dx, dy, math.max(3.0, force), kind == 'throw' and 2.2 or 0.8)
        end
    end)
    return true
end

-- Forwarded by the server to the owner of a walker someone else hit.
RegisterNetEvent('bs:fighting:reactOwned', function(netId, kind, force, dx, dy)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local ped = NetToPed(netId)
    if ped and ped ~= 0 then FightReact.Ped(ped, kind, force, tonumber(dx) or 0.0, tonumber(dy) or 0.0) end
end)

-- Asks for a reaction: applied here if we own the walker, otherwise sent to its owner.
function FightReact.Request(ped, kind, force, dx, dy)
    if kind == 'none' or not kind then return end
    if owned(ped) then FightReact.Ped(ped, kind, force, dx, dy) return end
    TriggerEvent('bs:zombies:fightReact', ped, kind)
    if NetworkGetEntityIsNetworked(ped) then
        TriggerServerEvent('bs:fighting:react', PedToNet(ped), kind, force, dx, dy)
    end
end

-- Our own ped getting hit by a player.
local choke = nil
local function releaseChoke(token)
    if choke ~= token then return end
    choke = nil
    if DoesEntityExist(token.ped) then
        DetachEntity(token.ped, true, false)
        FightAnim.Stop(token.anim, 4.0)
        ClearPedSecondaryTask(token.ped)
    end
end

local function side(me, fromPed)
    if not fromPed or fromPed == 0 then return 'hit_front' end
    local f = GetEntityForwardVector(me)
    local d = GetEntityCoords(fromPed) - GetEntityCoords(me)
    local len = math.max(0.01, #(vector2(d.x, d.y)))
    local fx, fy = d.x / len, d.y / len
    local dot = f.x * fx + f.y * fy
    if dot > 0.5 then return 'hit_front' end
    if dot < -0.5 then return 'hit_back' end
    local cross = f.x * fy - f.y * fx
    return cross > 0 and 'hit_left' or 'hit_right'
end

function FightReact.Self(kind, force, fromPed)
    local me = PlayerPedId()
    if IsPedDeadOrDying(me, true) then return end
    local dx, dy = 0.0, 0.0
    if fromPed and fromPed ~= 0 then
        local f = GetEntityForwardVector(fromPed)
        dx, dy = f.x, f.y
    end
    if kind == 'stumble' then
        flinch(me, side(me, fromPed), 0.5)
    elseif kind == 'stagger' then
        flinch(me, 'hit_heavy', 0.75)
        Fight.staggerUntil = GetGameTimer() + 650
    elseif kind == 'down' or kind == 'throw' then
        CreateThread(function()
            Wait(40)
            local ms = kind == 'throw' and 2400 or 1700
            SetPedToRagdoll(me, ms, ms + 300, 0, false, false, false)
            Wait(0)
            push(me, dx, dy, math.max(3.0, force or 0), kind == 'throw' and 2.0 or 0.6)
        end)
    elseif kind == 'choke' then
        FightReact.Choke(fromPed)
    end
end

-- Choke: we get attached in front of the attacker for a few seconds. Always lets go.
function FightReact.Choke(fromPed)
    if choke or not fromPed or fromPed == 0 then return end
    local me = PlayerPedId()
    local token = { ped = me }
    choke = token
    AttachEntityToEntity(me, fromPed, 11816, 0.0, 0.55, 0.0, 0.0, 0.0, 0.0, false, false, false, true, 2, true)
    local a = FightAnim.Play(me, 'choked', { flag = 1, loop = true })
    token.anim = a
    local untilAt = GetGameTimer() + (Fighting.PvP.chokeMs or 4200)
    CreateThread(function()
        while choke == token and GetGameTimer() < untilAt do
            if not DoesEntityExist(fromPed) or IsPedDeadOrDying(fromPed, true) or IsPedRagdoll(fromPed)
                or IsPedDeadOrDying(me, true) then break end
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
            Wait(0)
        end
        releaseChoke(token)
    end)
end

function FightReact.ReleaseChoke() if choke then releaseChoke(choke) end end

AddEventHandler('bs:hook:player:spawned', function() FightReact.ReleaseChoke() end)
