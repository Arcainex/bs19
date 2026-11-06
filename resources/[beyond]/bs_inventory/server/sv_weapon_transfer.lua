local T = Inv.TradeInternals
Inv.MutationOwners = Inv.MutationOwners or {}

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, entry in pairs(value) do out[key] = copy(entry) end
    return out
end

local function serial()
    return ('AT-%x-%08x-%08x'):format(os.time(), math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

local function transfer(src, weaponSlot, expectedSerial, mount, attachment, item, mode, profile, cosmetic, stickerRules)
    if GetInvokingResource() ~= 'bs_weapons' then return { ok = false } end
    src, weaponSlot = tonumber(src), math.tointeger(tonumber(weaponSlot))
    if not src or not weaponSlot or type(expectedSerial) ~= 'string' or expectedSerial == ''
        or type(mount) ~= 'string' or #mount > 32 or type(attachment) ~= 'string'
        or (mode ~= 'profile' and mode ~= 'stickers' and not Items.Get(item)) or (mode ~= 'fit' and mode ~= 'remove' and mode ~= 'profile' and mode ~= 'cosmeticUpdate' and mode ~= 'stickers') then return { ok = false } end
    local inv, player = T.of(src)
    if not inv or not player or Inv.TradeLock[src] or Inv.TradeLockedOwner[tostring(player.charId)]
        or T.pending(inv) > 0 then return { ok = false, error = 'Inventory is busy.' } end
    local owner = tostring(player.charId)
    if Inv.MutationOwners[owner] then return { ok = false, error = 'Inventory is busy.' } end
    Inv.MutationOwners[owner] = true

    local ok, result = pcall(function()
        local slots = copy(inv.slots)
        local weapon = slots[weaponSlot]
        if not weapon or weapon.amount ~= 1 or not weapon.metadata or weapon.metadata.serial ~= expectedSerial then
            return { ok = false, error = 'The selected weapon has moved.' }
        end
        local meta = weapon.metadata
        meta.attachments, meta.attachmentInstances = meta.attachments or {}, meta.attachmentInstances or {}
        local changed = { [weaponSlot] = true }
        local placement
        if cosmetic then
            if mount ~= 'cosmetic' or mode == 'profile' then return { ok = false } end
            if mode ~= 'remove' then
                if type(cosmetic) ~= 'table' or type(cosmetic.position) ~= 'table' or type(cosmetic.rotation) ~= 'table' then return { ok = false } end
                placement = { id = attachment, position = {}, rotation = {} }
                for _, axis in ipairs({'x','y','z'}) do
                    for _, key in ipairs({'position','rotation'}) do
                        local value = cosmetic[key][axis]
                        local bound = key == 'position' and 0.75 or 180
                        if type(value) ~= 'number' or value ~= value or math.abs(value) > bound then
                            return { ok = false, error = 'Invalid cosmetic placement.' }
                        end
                        placement[key][axis] = value
                    end
                end
            end
        elseif mode == 'cosmeticUpdate' then return { ok = false } end
        if mode == 'stickers' then
            if type(profile) ~= 'table' or #profile > 5 then return {ok=false,error='Too many weapon stickers.'} end
            local cleaned, count = {}, 0
            for index, sticker in pairs(profile) do
                if type(index) ~= 'number' or index % 1 ~= 0 or index < 1 or index > #profile
                    or type(sticker) ~= 'table' or not (stickerRules and stickerRules.designs or {skull=true,star=true,hazard=true})[sticker.design]
                    or not ({receiver_left=true,receiver_right=true,stock_left=true,magazine_left=true})[sticker.surface] then return {ok=false,error='Invalid weapon sticker.'} end
                local value = {design=sticker.design,surface=sticker.surface}
                for key,bounds in pairs({u={-1,1},v={-1,1},size={0.015,0.06},rotation={-180,180}}) do
                    local n = sticker[key]
                    if type(n) ~= 'number' or n ~= n or n < bounds[1] or n > bounds[2] then return {ok=false,error='Sticker placement is outside the supported surface.'} end
                    value[key] = n
                end
                local colour=sticker.colour or '#FFFFFF'
                local opacity=sticker.opacity==nil and 1 or sticker.opacity
                if type(colour)~='string'or not colour:match('^#%x%x%x%x%x%x$')or type(opacity)~='number'or opacity~=opacity or opacity<.1 or opacity>1 then return {ok=false,error='Invalid sticker colour or opacity.'}end
                value.colour,value.opacity=colour:upper(),opacity
                count=count+1;cleaned[index]=value
            end
            if count ~= #profile then return {ok=false,error='Invalid sticker list.'} end
            meta.weaponStickers = cleaned
        elseif mode == 'profile' then
            if type(profile) ~= 'table' or type(profile.name) ~= 'string' or #profile.name > 48
                or profile.name:find('[%c]') or type(profile.tint) ~= 'number' or profile.tint % 1 ~= 0
                or profile.tint < 0 or profile.tint > 31 then return { ok = false, error = 'Invalid weapon profile.' } end
            meta.customName, meta.tint = profile.name, profile.tint
        elseif mode == 'cosmeticUpdate' then
            local fitted = meta.attachmentInstances[mount]
            if meta.attachments[mount] ~= attachment or not fitted or fitted.item ~= item then
                return { ok = false, error = 'That cosmetic part is no longer fitted.' }
            end
        elseif mode == 'fit' then
            if meta.attachments[mount] then return { ok = false, error = 'Remove the fitted attachment first.' } end
            local selected
            for _, slot in ipairs(T.bagSlots(inv)) do
                if slots[slot] and slots[slot].item == item and slots[slot].amount >= 1 then selected = slot; break end
            end
            if not selected then return { ok = false, error = 'You are not carrying that attachment.' } end
            local entry = slots[selected]
            local instance = copy(entry.metadata or {})
            instance.serial = instance.serial or serial()
            meta.attachments[mount] = attachment
            meta.attachmentInstances[mount] = { serial = instance.serial, item = item, metadata = instance, durability = entry.durability }
            entry.amount = entry.amount - 1
            if entry.amount == 0 then slots[selected] = nil end
            changed[selected] = true
        else
            if meta.attachments[mount] ~= attachment then return { ok = false, error = 'That attachment is no longer fitted.' } end
            local fitted = meta.attachmentInstances[mount]
            if fitted and fitted.item ~= item then return { ok = false, error = 'Attachment record does not match.' } end
            local def = Items.Get(item)
            local draft = copy(inv)
            draft.slots = slots
            if Inv.Weight(draft) + (def.weight or 0) > inv.maxWeight then return { ok = false, error = 'Your bag is too heavy.' } end
            local free
            for _, slot in ipairs(T.bagSlots(inv)) do if not slots[slot] then free = slot; break end end
            if not free then return { ok = false, error = 'No room in your bag.' } end
            local x, y, rot = Grid.FirstFit(T.gridBounds(draft), T.gridEntries(draft), { id = free, w = def.w or 1, h = def.h or 1 }, true)
            if not x then return { ok = false, error = 'No room in your bag.' } end
            local instance = fitted and copy(fitted.metadata) or {}
            instance.serial = fitted and fitted.serial or instance.serial or serial()
            slots[free] = { item = item, amount = 1, slot = free, x = x, y = y, rot = rot, metadata = instance, durability = fitted and fitted.durability }
            meta.attachments[mount], meta.attachmentInstances[mount] = nil, nil
            changed[free] = true
        end
        if cosmetic then meta.cosmeticMount = placement end
        local queries = {}
        for slot in pairs(changed) do
            queries[#queries + 1] = { query = 'DELETE FROM bs_inventory_items WHERE inventory_id = ? AND slot_x = ?', values = { inv.id, slot } }
            local entry = slots[slot]
            if entry then
                queries[#queries + 1] = {
                    query = 'INSERT INTO bs_inventory_items (inventory_id,item,amount,slot_x,slot_y,grid_x,grid_y,rotated,durability,metadata) VALUES (?,?,?,?,0,?,?,?,?,?)',
                    values = { inv.id, entry.item, entry.amount, slot, entry.x or 0, entry.y or 0, entry.rot and 1 or 0, entry.durability, json.encode(entry.metadata or {}) },
                }
            end
        end
        if not MySQL.transaction.await(queries) then return { ok = false, error = 'Could not save the attachment change.' } end
        -- Eviction reloads database row IDs after the transaction, including after a reconnect.
        T.evict(player.charId)
        return { ok = true, metadata = copy(meta) }
    end)
    Inv.MutationOwners[owner] = nil
    if not ok then
        print(('[bs_inventory] attachment transfer failed for character %s: %s'):format(owner, tostring(result)))
        return { ok = false, error = 'Could not save the attachment change.' }
    end
    if result.ok then Inv.Push(src) end
    return result
end
exports('WeaponTransfer', transfer)
exports('UpdateWeaponProfile', function(src, slot, expectedSerial, profile)
    return transfer(src, slot, expectedSerial, '', '', nil, 'profile', profile)
end)

-- Cosmetics are owned item instances stored inside one uniquely identified weapon.
local function array(value,maximum)
    if type(value)~='table'or #value>maximum then return false end
    local count=0
    for key in pairs(value)do
        if type(key)~='number'or key%1~=0 or key<1 or key>#value then return false end
        count=count+1
    end
    return count==#value
end
local function finite(value)return type(value)=='number'and value==value and math.abs(value)<math.huge end
local function mountTransform(value,limits)
    if type(value)~='table'or type(value.position)~='table'or type(value.rotation)~='table'then return nil end
    local scale=value.scale==nil and 1 or value.scale
    local minimum=math.max(.5,tonumber(limits.minScale)or .5)
    local maximum=math.min(1.5,tonumber(limits.maxScale)or 1.5)
    if not finite(scale)or scale<minimum or scale>maximum then return nil end
    local result={position={},rotation={},scale=scale}
    for _,axis in ipairs({'x','y','z'})do
        local p,r=value.position[axis],value.rotation[axis]
        if not finite(p)or math.abs(p)>math.min(.75,tonumber(limits.maxOffset)or .75)or not finite(r)or math.abs(r)>180 then return nil end
        result.position[axis],result.rotation[axis]=p,r
    end
    return result
end
local function storedMounts(meta,catalogue)
    if type(meta.cosmeticMounts)=='table'then return copy(meta.cosmeticMounts)end
    local legacy=meta.cosmeticMount
    if not legacy then return {}end
    local instance=meta.attachmentInstances and meta.attachmentInstances.cosmetic or {}
    local def=catalogue[legacy.id]
    local item=instance.item or (def and def.item)
    if not item or not Items.Get(item)then return nil end
    return {{key='legacy:'..legacy.id,id=legacy.id,item=item,serial=instance.serial,
        metadata=copy(instance.metadata or {}),durability=instance.durability,
        position=copy(legacy.position),rotation=copy(legacy.rotation),scale=legacy.scale or 1}}
end
local function workshop(src,weaponSlot,expectedSerial,profile,mounts,stickers,limits,catalogue)
    if GetInvokingResource()~='bs_weapons'then return {ok=false}end
    src,weaponSlot=tonumber(src),math.tointeger(tonumber(weaponSlot))
    if not src or not weaponSlot or type(expectedSerial)~='string'or expectedSerial==''or type(limits)~='table'or type(catalogue)~='table'then return {ok=false}end
    local inv,player=T.of(src)
    if not inv or not player or Inv.TradeLock[src]or Inv.TradeLockedOwner[tostring(player.charId)]or T.pending(inv)>0 then return {ok=false,error='Inventory is busy.'}end
    local owner=tostring(player.charId)
    if Inv.MutationOwners[owner]then return {ok=false,error='Inventory is busy.'}end
    Inv.MutationOwners[owner]=true
    local ok,result=pcall(function()
        local slots=copy(inv.slots)
        local weapon=slots[weaponSlot]
        if not weapon or weapon.amount~=1 or not weapon.metadata or weapon.metadata.serial~=expectedSerial then return {ok=false,error='The selected weapon has moved.'}end
        local meta=weapon.metadata
        local previous=storedMounts(meta,catalogue)
        if not previous or not array(previous,12)then return {ok=false,error='Existing cosmetic ownership needs repair.'}end
        local oldByKey={}
        for _,mount in ipairs(previous)do
            if type(mount.key)~='string'or oldByKey[mount.key]then return {ok=false,error='Duplicate cosmetic ownership record.'}end
            oldByKey[mount.key]=mount
        end
        mounts=mounts or previous
        local cap=math.max(1,math.min(12,math.floor(tonumber(limits.maxMounts)or 6)))
        if not array(mounts,math.max(cap,#previous))then return {ok=false,error='Too many cosmetic pieces.'}end
        local planned,seen,changed={}, {}, {[weaponSlot]=true}
        for _,mount in ipairs(mounts)do
            local def=type(mount)=='table'and catalogue[mount.id]
            local transform=mountTransform(mount,limits)
            if not def or not Items.Get(def.item)or not transform then return {ok=false,error='Invalid cosmetic piece or transform.'}end
            local key=mount.key or mount.mountKey
            if key~=nil and (type(key)~='string'or #key>96 or key:find('[^%w_:%-]')or seen[key])then return {ok=false,error='Invalid cosmetic piece identity.'}end
            if key then seen[key]=true end
            local old=key and oldByKey[key]
            local own
            if old then
                if old.id~=mount.id or old.item~=def.item then return {ok=false,error='A fitted piece cannot change its item type.'}end
                own=copy(old)
            else
                if #mounts>cap then return {ok=false,error='Remove existing pieces before adding more.'}end
                local selected
                for _,slot in ipairs(T.bagSlots(inv))do local e=slots[slot];if e and e.item==def.item and e.amount>=1 then selected=slot;break end end
                if not selected then return {ok=false,error='You are not carrying '..def.item..'.'}end
                local e=slots[selected];local instance=copy(e.metadata or {})
                instance.serial=instance.serial or serial()
                own={key='CM-'..serial(),id=mount.id,item=def.item,serial=instance.serial,metadata=instance,durability=e.durability}
                e.amount=e.amount-1;if e.amount==0 then slots[selected]=nil end;changed[selected]=true
            end
            own.serial=own.serial or (own.metadata and own.metadata.serial)or serial()
            own.metadata=own.metadata or {};own.metadata.serial=own.serial
            own.position,own.rotation,own.scale=transform.position,transform.rotation,transform.scale
            planned[#planned+1]=own
        end
        local retained={};for _,mount in ipairs(planned)do retained[mount.key]=true end
        for _,old in ipairs(previous)do
            if not retained[old.key]then
                local def=Items.Get(old.item);if not def then return {ok=false,error='Cannot return an unknown cosmetic item.'}end
                local free;for _,slot in ipairs(T.bagSlots(inv))do if not slots[slot]then free=slot;break end end
                if not free then return {ok=false,error='No room to return a removed piece.'}end
                local draft=copy(inv);draft.slots=slots
                local x,y,rot=Grid.FirstFit(T.gridBounds(draft),T.gridEntries(draft),{id=free,w=def.w or 1,h=def.h or 1},true)
                if not x then return {ok=false,error='No room to return a removed piece.'}end
                local instance=copy(old.metadata or {});instance.serial=old.serial or instance.serial or serial()
                slots[free]={item=old.item,amount=1,slot=free,x=x,y=y,rot=rot,metadata=instance,durability=old.durability};changed[free]=true
            end
        end
        meta.cosmeticMounts=planned
        -- Remove the old single-slot representation only inside the successful transaction.
        meta.cosmeticMount=nil
        if meta.attachments then meta.attachments.cosmetic=nil end
        if meta.attachmentInstances then meta.attachmentInstances.cosmetic=nil end
        if profile~=nil then
            if type(profile)~='table'or type(profile.name)~='string'or #profile.name>48 or profile.name:find('[%c]')or not finite(profile.tint)or profile.tint%1~=0 or profile.tint<0 or profile.tint>31 then return {ok=false,error='Invalid weapon profile.'}end
            meta.customName,meta.tint=profile.name,profile.tint
        end
        if stickers~=nil then
            if not array(stickers,5)then return {ok=false,error='Too many weapon stickers.'}end
            local clean={}
            for _,sticker in ipairs(stickers)do
                if type(sticker)~='table'or not (limits.stickerDesigns or {skull=true,star=true,hazard=true})[sticker.design]or not ({receiver_left=true,receiver_right=true,stock_left=true,magazine_left=true})[sticker.surface]then return {ok=false,error='Invalid sticker design or surface.'}end
                local value={design=sticker.design,surface=sticker.surface}
                for key,bounds in pairs({u={-1,1},v={-1,1},size={.015,.06},rotation={-180,180}})do
                    local n=sticker[key];if not finite(n)or n<bounds[1]or n>bounds[2]then return {ok=false,error='Invalid sticker placement.'}end;value[key]=n
                end
                local colour=sticker.colour or '#FFFFFF'
                local opacity=sticker.opacity==nil and 1 or sticker.opacity
                if type(colour)~='string'or not colour:match('^#%x%x%x%x%x%x$')or type(opacity)~='number'or opacity~=opacity or opacity<.1 or opacity>1 then return {ok=false,error='Invalid sticker colour or opacity.'}end
                value.colour,value.opacity=colour:upper(),opacity
                clean[#clean+1]=value
            end
            meta.weaponStickers=clean
        end
        local draft=copy(inv);draft.slots=slots
        if Inv.Weight(draft)>inv.maxWeight+.001 then return {ok=false,error='Your bag is too heavy to return these pieces.'}end
        local queries={}
        for slot in pairs(changed)do
            queries[#queries+1]={query='DELETE FROM bs_inventory_items WHERE inventory_id=? AND slot_x=?',values={inv.id,slot}}
            local entry=slots[slot]
            if entry then queries[#queries+1]={query='INSERT INTO bs_inventory_items (inventory_id,item,amount,slot_x,slot_y,grid_x,grid_y,rotated,durability,metadata) VALUES (?,?,?,?,0,?,?,?,?,?)',values={inv.id,entry.item,entry.amount,slot,entry.x or 0,entry.y or 0,entry.rot and 1 or 0,entry.durability,json.encode(entry.metadata or {})}}end
        end
        if not MySQL.transaction.await(queries)then return {ok=false,error='Could not save the workshop changes.'}end
        T.evict(player.charId)
        return {ok=true,metadata=copy(meta)}
    end)
    Inv.MutationOwners[owner]=nil
    if not ok then print('[bs_inventory] workshop transaction failed: '..tostring(result));return {ok=false,error='Could not save the workshop changes.'}end
    if result.ok then Inv.Push(src)end
    return result
end
exports('WeaponWorkshop',workshop)

exports('WeaponCosmetic',function(src,slot,expectedSerial,id,item,mode,placement,options)
    if GetInvokingResource()~='bs_weapons'or (mode~='fit'and mode~='update'and mode~='remove')then return {ok=false}end
    options=options or {};options.catalogue=options.catalogue or {[id]={item=item}}
    local inv=T.of(src);local entry=inv and inv.slots[tonumber(slot)]
    if not entry or not entry.metadata or entry.metadata.serial~=expectedSerial then return {ok=false,error='The selected weapon has changed.'}end
    local mounts=storedMounts(entry.metadata,options.catalogue)
    if not mounts then return {ok=false}end
    local key=placement and (placement.key or placement.mountKey)
    local found
    if mode~='fit'then
        for i,mount in ipairs(mounts)do if (key and mount.key==key)or (not key and mount.id==id)then if found then return {ok=false,error='Select the exact fitted piece.'}end;found=i end end
        if not found or mounts[found].id~=id then return {ok=false,error='That piece is no longer fitted.'}end
    end
    if mode=='remove'then table.remove(mounts,found)
    else
        local transform=copy(placement or {});transform.id=id;transform.key=mode=='update'and mounts[found].key or nil
        if mode=='fit'then mounts[#mounts+1]=transform else mounts[found]=transform end
    end
    return workshop(src,slot,expectedSerial,nil,mounts,nil,options,options.catalogue)
end)

exports('UpdateWeaponStickers',function(src,slot,expectedSerial,stickers,rules)
    return transfer(src,slot,expectedSerial,'','',nil,'stickers',stickers,nil,rules)
end)
