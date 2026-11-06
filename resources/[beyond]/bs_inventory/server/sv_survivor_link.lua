local T=Inv.TradeInternals
local function caller()return GetInvokingResource()=='bs_survivor_link'end
exports('LinkBusy',function(src)
    if not caller()then return true end
    local inv,p=T.of(src)
    return not inv or Inv.TradeLock[src] or Inv.TradeLockedOwner[tostring(p.charId)] or Inv.MutationOwners[tostring(p.charId)] or T.pending(inv)>0
end)
exports('LinkBag',function(id,carry)
    if not caller()then return end
    local inv=T.character(id,carry or 40)
    local out={}
    for slot,e in pairs(inv.slots)do
        local def=Items.Get(e.item) or {}
        out[#out+1]={slot=slot,id=e.id,item=e.item,label=def.label or e.item,amount=e.amount,weapon=def.data and def.data.weapon,bar=not T.isBag(inv,slot),metadata=e.metadata,
            value=def.value or 0,category=def.category,throwable=def.data and def.data.throwable==true or nil,rounds=def.data and tonumber(def.data.rounds)or nil}
    end
    table.sort(out,function(a,b)return a.slot<b.slot end)
    return out
end)
-- One complete stack per confirmed exchange. Existing row identity and metadata are preserved.
exports('LinkTransfer',function(src,charId,carry,direction,slot,expectedId)
    if not caller()then return {ok=false}end
    local a,p=T.of(src);if not a or p.charId==charId then return {ok=false}end
    local b=T.character(charId,carry or 40)
    local ka,kb=tostring(p.charId),tostring(charId)
    if Inv.TradeLock[src] or Inv.TradeLockedOwner[ka] or Inv.TradeLockedOwner[kb] or Inv.MutationOwners[ka] or Inv.MutationOwners[kb] or T.pending(a)>0 or T.pending(b)>0 then return {ok=false,error='Inventory is busy.'}end
    Inv.MutationOwners[ka],Inv.MutationOwners[kb]=true,true
    local ok,result=pcall(function()
        local from,to=direction=='give' and a or b,direction=='give' and b or a
        slot=tonumber(slot);local entry=from.slots[slot]
        if not T.isBag(from,slot) or not entry or entry.id~=tonumber(expectedId)then return {ok=false,error='That item moved. Unequip it before trading.'}end
        local def=Items.Get(entry.item) or {};if Inv.Weight(to)+(def.weight or .5)*entry.amount>to.maxWeight then return {ok=false,error='Not enough carry capacity.'}end
        local target
        for _,n in ipairs(T.bagSlots(to))do if not to.slots[n]then target=n;break end end
        if not target then return {ok=false,error='No room in the bag.'}end
        local x,y,rot=Grid.FirstFit(T.gridBounds(to),T.gridEntries(to),{id=target,w=def.w or 1,h=def.h or 1},true)
        if not x then return {ok=false,error='No room in the bag.'}end
        local moved=MySQL.transaction.await({{query='UPDATE bs_inventory_items SET inventory_id=?,slot_x=?,grid_x=?,grid_y=?,rotated=? WHERE id=? AND inventory_id=? AND slot_x=?',values={to.id,target,x,y,rot and 1 or 0,entry.id,from.id,slot}}})
        if not moved then return {ok=false,error='Trade could not be saved.'}end
        T.evict(p.charId);T.evict(charId);return {ok=true}
    end)
    Inv.MutationOwners[ka],Inv.MutationOwners[kb]=nil,nil
    if not ok then return {ok=false,error='Trade failed.'}end
    if result.ok then Inv.Push(src)end
    return result
end)

-- Trade range check for a companion peer (see sv_trade).
function Inv.LinkNear(src,charId)
    local ok,link=pcall(function()return exports.bs_survivor_link:GetCompanion(src)end)
    if not ok or type(link)~='table'or tonumber(link.id)~=tonumber(charId)or not link.life or link.life.status~='alive'then return false end
    local ped=NetworkGetEntityFromNetworkId(link.net or 0);local me=GetPlayerPed(src)
    if ped==0 or me==0 or not DoesEntityExist(ped)or GetEntityRoutingBucket(ped)~=GetPlayerRoutingBucket(src)then return false end
    return #(GetEntityCoords(ped)-GetEntityCoords(me))<=(Inventory.Settings.tradeDistance or 3.0)
end
-- Admin test loadout straight into the companion's own inventory.
exports('LinkGive',function(charId,item,amount)
    if not caller()then return false end
    local kb=tostring(charId)
    if Inv.MutationOwners[kb]or Inv.TradeLockedOwner[kb]then return false,'busy'end
    return T.add(T.character(tonumber(charId),40),item,math.max(1,math.floor(tonumber(amount)or 1)))
end)
exports('LinkEvict',function(id)if caller()then T.evict(id)end end)

-- Open the companion's real inventory as the second panel, like a stash or a body.
exports('LinkOpen',function(src,charId,pos,label,carry)
    if not caller()then return {ok=false}end
    local a,p=T.of(src);charId=tonumber(charId)
    if not a or not charId or p.charId==charId then return {ok=false}end
    local b=T.character(charId,carry or 40)
    if Inv.TradeLockedOwner[tostring(charId)]or Inv.MutationOwners[tostring(charId)]or T.pending(b)>0 then return {ok=false,error='Companion inventory is busy.'}end
    b.linkBaseCarry=carry or 40
    local view=T.serialise(b)
    b.maxWeight=(carry or 40)+(view.equipStats and view.equipStats.carry or 0)
    b.label=label or 'Companion'
    T.openAs(src,'character:'..charId,pos)
    Inv.Push(src)
    return {ok=true,container=T.serialise(b),label=b.label}
end)
exports('LinkClose',function(src,charId)
    if caller()and T.openKey(src)==('character:'..tostring(charId))then T.openAs(src,nil,nil);Inv.Push(src)end
end)
exports('LinkIsOpen',function(src,charId)
    if not caller()then return false end
    return T.openKey(src)==('character:'..tostring(charId))
end)
-- Takes rounds (or anything) out of the companion's bag; grid first, bar last. Returns how many came out.
exports('LinkTake',function(charId,item,amount)
    if not caller()then return 0 end
    local inv=T.character(tonumber(charId),40)
    local kb=tostring(charId)
    if Inv.MutationOwners[kb] or Inv.TradeLockedOwner[kb] then return 0 end
    amount=math.max(0,math.floor(tonumber(amount)or 0))
    local slots={}
    for slot,e in pairs(inv.slots)do if e.item==item then slots[#slots+1]=slot end end
    table.sort(slots,function(x,y)local bx,by=T.isBag(inv,x),T.isBag(inv,y);if bx~=by then return bx end;return x>y end)
    local taken=0
    for _,slot in ipairs(slots)do
        if taken>=amount then break end
        local e=inv.slots[slot];local take=math.min(e.amount,amount-taken)
        e.amount=e.amount-take;taken=taken+take
        if e.amount<=0 then inv.slots[slot]=nil end
        T.persist(inv,slot)
    end
    return taken
end)
