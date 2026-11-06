-- Walker grab: when walkers bring the companion down he is pinned instead, and you get a rescue window.
LinkGrab={}
local C=SurvivorLink
local function window()return math.max(5,math.floor(tonumber(C.grabWindow)or 60))end
local function hold(rec,on)
    local net=rec.life.grabNet
    if not net or GetResourceState('bs_zombies')~='started'then return end
    pcall(function()exports.bs_zombies:LinkHold(net,NetworkGetNetworkIdFromEntity(rec.ped),on)end)
end
local function grabber(rec)
    local z=NetworkGetEntityFromNetworkId(tonumber(rec.life.grabNet)or 0)
    if z==0 or not DoesEntityExist(z)then return nil end
    return z
end
-- Freed when the walker is gone, dead or no longer on him.
local function loose(rec)
    local z=grabber(rec)
    if not z or GetEntityHealth(z)<=0 or Entity(z).state.bsZombieDead then return true end
    return #(GetEntityCoords(z)-GetEntityCoords(rec.ped))>2.6
end

function LinkGrab.Start(src,rec,forced)
    if C.grabWindow==0 and not forced then return false end
    local claw=rec.lastClaw
    if not claw or os.time()-claw.at>3 then return false end
    rec.life.grabNet=claw.net
    if not forced and loose(rec)then rec.life.grabNet=nil;return false end
    -- A walker moved next to him by an admin needs a moment before the server sees it there.
    rec.life.grabGrace=forced and os.time()+3 or nil
    rec.life.status='grabbed';rec.life.grabEndsAt=os.time()+window()
    rec.lastClaw=nil
    local net=NetworkGetNetworkIdFromEntity(rec.ped)
    TriggerClientEvent('bs:link:health',src,net,rec.appearanceToken,115)
    TriggerClientEvent('bs:link:grabbed',src,net,rec.life.grabNet,window())
    TriggerClientEvent('bs:ui:notify',src,{type='warn',duration=7000,
        message=Lp(src,'link.grabbed',{name=rec.char.first_name,s=window()})})
    hold(rec,true)
    LinkCore.push(src)
    return true
end

local function free(src,rec)
    hold(rec,false)
    rec.life.status='alive';rec.life.health=140
    rec.life.grabEndsAt,rec.life.grabNet,rec.life.grabLeft,rec.life.grabGrace=nil,nil,nil,nil
    local net=NetworkGetNetworkIdFromEntity(rec.ped)
    TriggerClientEvent('bs:link:health',src,net,rec.appearanceToken,140)
    TriggerClientEvent('bs:link:revived',src,net,140)
    TriggerClientEvent('bs:ui:notify',src,{type='success',duration=4000,message=Lp(src,'link.grab_freed',{name=rec.char.first_name})})
    LinkCore.push(src)
end
LinkGrab.Free=free

function LinkGrab.Tick(src,rec,hp)
    if hp<=0 then hold(rec,false);return LinkCore.fall(src,rec,0)end
    if os.time()>=(rec.life.grabGrace or 0)and loose(rec)then return free(src,rec)end
    if os.time()>=(rec.life.grabEndsAt or 0)then
        hold(rec,false)
        TriggerClientEvent('bs:ui:notify',src,{type='error',duration=5000,message=Lp(src,'link.grab_failed',{name=rec.char.first_name})})
        return LinkCore.fall(src,rec,105)
    end
    -- Keep the walker on him; the hold broadcast only lasts a few seconds on the walker's host.
    hold(rec,true)
end

-- The owner's client saw the walker knocked over (a shove) or killed before the server did.
RegisterNetEvent('bs:link:grabFree',function(znet)
    local src=source;local rec=LinkCore.links[src]
    if not rec or rec.life.status~='grabbed'or tonumber(znet)~=rec.life.grabNet then return end
    if not LinkCore.closeEnough(src,rec,30.0)or os.time()<(rec.life.grabGrace or 0)then return end
    -- A shoved walker is on the ground for a moment; the server cannot see ragdolls, so we trust the owner here.
    free(src,rec)
end)
