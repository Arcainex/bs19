local busy={}
local function current(src)
    if not SurvivorLink.enabled or Player(src).state.bsDowned or Player(src).state.bsDead or Player(src).state.bsCuffed then return nil end
    local me=GetPlayerPed(src)
    if me==0 or GetEntityHealth(me)<=125 then return nil end
    local link=exports.bs_survivor_link:GetCompanion(src)
    if not link or not link.life or link.life.status~='alive'then return nil end
    local ped=NetworkGetEntityFromNetworkId(link.net or 0)
    if ped==0 or not DoesEntityExist(ped)or GetEntityRoutingBucket(ped)~=GetPlayerRoutingBucket(src)
        or #(GetEntityCoords(me)-GetEntityCoords(ped))>25.0 then return nil end
    return link
end
local function recruit(src,kind)
    if busy[src]then return {ok=false,error='Please wait for the current recruitment.'}end
    local link=current(src)
    if not link or GetResourceState('bs_factions')~='started'then return {ok=false,error='Move beside your living linked survivor.'}end
    busy[src]=true
    local ok,result=pcall(function()
        if kind=='faction'then return exports.bs_factions:RecruitLinkedCharacter(src,link.id)end
        return exports.bs_factions:RecruitLinkedToSquad(src,link.id)
    end)
    busy[src]=nil
    if not ok then return {ok=false,error='Recruitment is temporarily unavailable.'}end
    -- Recruited to the faction while you lead a squad: he joins your squad too, like a player you invite.
    if kind=='faction'and result and result.ok then
        local okS,joined=pcall(function()return exports.bs_factions:RecruitLinkedToSquad(src,link.id)end)
        if okS and joined and joined.ok then result.squad=joined.label end
    end
    if result and result.ok then TriggerClientEvent('bs:link:membershipChanged',src)end
    return result or {ok=false,error='Recruitment failed.'}
end
BSB.RegisterCallback('link:factionJoin',function(src)return recruit(src,'faction')end)
BSB.RegisterCallback('link:squadJoin',function(src)return recruit(src,'squad')end)
BSB.RegisterCallback('link:membership',function(src)
    local link=current(src)
    if not link or GetResourceState('bs_factions')~='started'then return {ok=false}end
    return {ok=true,faction=exports.bs_factions:GetLinkedFactionSummary(link.id),squad=exports.bs_factions:GetLinkedSquadSummary(link.id)}
end)
AddEventHandler('playerDropped',function()local src=source;busy[src]=nil end)
