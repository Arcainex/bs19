-- bs_zombies - small hooks for bs_fighting freeflow combat (Zombies.Combat in config_zombies.lua).
-- Victim control for paired clips, attack tokens, stagger state. The wind-up event is raised in cl_attack.

local C = Zombies.Combat or {}

local function entryOf(id)
    id = tonumber(id)
    local e = id and Zed and Zed.live and Zed.live[id]
    if e and e.ped and DoesEntityExist(e.ped) and not e.dying then return e end
    return nil
end

-- Attack tokens: at most maxAttackers different walkers take turns on this player, the rest keep coming.
-- Attacks are decided on the victim's own client, so the tokens live here too.
local tokens = {}   -- [id] = held until (ms)

function Zombies.CombatTokenFull(id, now)
    if not C.enabled or (C.maxAttackers or 0) <= 0 then return false end
    if tokens[id] and tokens[id] > now then return false end
    local n = 0
    for wid, untilAt in pairs(tokens) do
        if untilAt <= now or not entryOf(wid) then tokens[wid] = nil
        elseif wid ~= id then n = n + 1 end
    end
    return n >= C.maxAttackers
end

function Zombies.CombatTakeToken(id, untilAt)
    if not C.enabled then return end
    tokens[id] = math.max(tokens[id] or 0, untilAt + (C.tokenHoldMs or 900))
end

-- Stagger: no attacks until it ends, and finishers are allowed (server window from bs:z:staggered).
local lastReport = {}

function Zombies.IsStaggered(id)
    local e = entryOf(id)
    return e ~= nil and (e.staggerUntil or 0) > GetGameTimer()
end

local function stumble(e)
    local a = C.staggerAnim
    local ped = e.ped
    if not a or IsPedRagdoll(ped) or IsEntityDead(ped) then return end
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then return end
    if not HasAnimDictLoaded(a.dict) then
        RequestAnimDict(a.dict)
        return   -- next stagger gets it; never wait inside an export
    end
    TaskPlayAnim(ped, a.dict, a.clip, 8.0, -4.0, a.ms or 900, 0, 0.0, false, false, false)
end

local function setStaggered(id, ms, noAnim)
    if not C.enabled or C.stagger == false then return false end
    local e = entryOf(id)
    if not e then return false end
    local now = GetGameTimer()
    ms = math.max(100, math.min(5000, tonumber(ms) or 900))
    e.staggerUntil = math.max(e.staggerUntil or 0, now + ms)
    e.recoverUntil = math.max(e.recoverUntil or 0, now + ms)
    if not noAnim then stumble(e) end
    if now - (lastReport[e.id] or 0) > 500 then
        lastReport[e.id] = now
        TriggerServerEvent('bs:z:staggered', e.id)
    end
    return true
end
Zombies.SetStaggered = setStaggered

-- Victim control: call each frame until it returns the ped (or give up). Never waits.
-- While held the AI leaves the walker alone (takedownUntil), at most victimHoldMs.
local function requestVictim(id, holdMs)
    if not C.enabled or C.victimControl == false then return nil end
    local e = entryOf(id)
    if not e or IsEntityDead(e.ped) then return nil end
    local ped = e.ped
    if NetworkGetEntityIsNetworked(ped) and not NetworkHasControlOfEntity(ped) then
        NetworkRequestControlOfEntity(ped)
        return nil
    end
    holdMs = math.max(100, math.min(C.victimHoldMs or 3000, tonumber(holdMs) or (C.victimHoldMs or 3000)))
    e.takedownUntil = math.max(e.takedownUntil or 0, GetGameTimer() + holdMs)
    return ped
end

local function releaseVictim(id)
    local e = entryOf(id)
    if e then e.takedownUntil = nil end
end

exports('RequestVictim', function(id, holdMs) return requestVictim(id, holdMs) end)
exports('ReleaseVictim', function(id) releaseVictim(id) end)
exports('SetStaggered', function(id, ms, noAnim) return setStaggered(id, ms, noAnim == true) end)
exports('IsStaggered', function(id) return Zombies.IsStaggered(id) end)

AddEventHandler('bs:hook:player:unloaded', function() tokens = {} end)

CreateThread(function()
    if C.staggerAnim and C.staggerAnim.dict then RequestAnimDict(C.staggerAnim.dict) end
end)
