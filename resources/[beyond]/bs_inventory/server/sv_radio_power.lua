local T=Inv.TradeInternals
local function copy(t)local out={};for k,v in pairs(t or {})do out[k]=v end;return out end
exports('AdjustRadioCharge',function(src,expectedId,delta)
    if GetInvokingResource()~='bs_radio'or type(delta)~='number'or delta~=delta or math.abs(delta)>10 then return nil end
    local inv,p=T.of(src)
    if not inv or not p or Inv.TradeLock[src]or Inv.TradeLockedOwner[tostring(p.charId)]or T.pending(inv)>0 then return nil end
    local entry=inv.slots[921]
    local def=entry and Items.Get(entry.item)
    if not entry or entry.id~=expectedId or not def or not def.data or not def.data.radio then return nil end
    local owner=tostring(p.charId)
    if Inv.MutationOwners[owner]then return nil end
    Inv.MutationOwners[owner]=true
    local ok,result=pcall(function()
        local meta=copy(entry.metadata)
        meta.radioCharge=math.max(0,math.min(100,(tonumber(meta.radioCharge)or 100)+delta))
        local changed=MySQL.update.await('UPDATE bs_inventory_items SET metadata=? WHERE id=? AND inventory_id=? AND slot_x=921',{json.encode(meta),entry.id,inv.id})
        if not changed or changed<1 then return nil end
        entry.metadata=meta
        return meta.radioCharge
    end)
    Inv.MutationOwners[owner]=nil
    return ok and result or nil
end)
-- Installing an accessory consumes its actual row and saves the vehicle in the same transaction.
exports('InstallVehicleInverter',function(src,slot,vehicleId,parts)
    if GetInvokingResource()~='bs_vehicles'then return false end
    local inv,p=T.of(src);slot=tonumber(slot)
    if not inv or not p or Inv.TradeLock[src]or Inv.TradeLockedOwner[tostring(p.charId)]or T.pending(inv)>0 then return false end
    local entry=inv.slots[slot]
    if not entry or entry.item~='vehicle_inverter'or entry.amount~=1 then return false end
    local owner=tostring(p.charId);if Inv.MutationOwners[owner]then return false end
    Inv.MutationOwners[owner]=true
    local ok,result=pcall(function()
        local saved=MySQL.transaction.await({
            {query='DELETE FROM bs_inventory_items WHERE id=? AND inventory_id=? AND item=?',values={entry.id,inv.id,'vehicle_inverter'}},
            {query='UPDATE bs_vehicles SET parts=? WHERE id=?',values={json.encode(parts),vehicleId}}
        })
        if not saved then return false end
        T.evict(p.charId);return true
    end)
    Inv.MutationOwners[owner]=nil
    if ok and result then Inv.Push(src);return true end
    return false
end)
