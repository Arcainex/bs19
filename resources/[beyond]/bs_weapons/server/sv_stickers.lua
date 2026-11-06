local busy = {}
local catalogStamp,nextCatalog='',0
function Weapons.RefreshStickerCatalogue(force)
    if not force and GetGameTimer()<nextCatalog then return end
    nextCatalog=GetGameTimer()+3000
    if GetResourceState('bs_factions')=='started'then
        local ok,list=pcall(function()return exports.bs_factions:GetStickerEmblems()end)
        if ok and type(list)=='table'then
            for id in pairs(Weapons.Stickers.designs)do if id:sub(1,8)=='faction:'then Weapons.Stickers.designs[id]=nil end end
            for _,f in ipairs(list)do if type(f.id)=='string'and #f.id<=48 then
                Weapons.Stickers.designs['faction:'..f.id]={label=f.label or f.id,category='Factions',art='faction',emblem=f.emblem,logo=f.logo}
            end end
        end
    end
    local list={};for id,d in pairs(Weapons.Stickers.designs)do local item={id=id};for k,v in pairs(d)do item[k]=v end;list[#list+1]=item end
    table.sort(list,function(a,b)return a.id<b.id end)
    local stamp=json.encode(list)
    if stamp~=catalogStamp then catalogStamp=stamp;TriggerClientEvent('bs:weapons:stickerCatalogue',-1,list)end
    return list
end
function Weapons.StickerDesignRules()
    local out={};for id in pairs(Weapons.Stickers.designs)do out[id]=true end
    return {designs=out}
end
BSB.RegisterCallback('weapons:stickerCatalogue',function()return Weapons.RefreshStickerCatalogue(true)end)


function Weapons.PublishStickers(src, weapon, meta)
    Weapons.RefreshStickerCatalogue()
    local entries = Weapons.Stickers.enabled and meta and Weapons.ValidStickers(weapon, meta.weaponStickers or {})
    Player(src).state:set('bsWeaponStickers', entries and #entries > 0 and {
        weapon = weapon, serial = meta.serial, entries = entries } or nil, true)
end

BSB.RegisterCallback('weapons:stickerState', function(src, weapon)
    Weapons.RefreshStickerCatalogue()
    if type(weapon) ~= 'string' or not Weapons.Stickers.surfaces[weapon] then
        return { ok = true, enabled = false }
    end
    local slot, _, meta = Weapons.Instance(src, weapon)
    if not slot then return { ok = false } end
    if not Weapons.Stickers.enabled and #(meta.weaponStickers or {}) == 0 then return { ok = true, enabled = false } end
    local designs, surfaces = {}, {}
    for id, entry in pairs(Weapons.Stickers.designs) do designs[#designs + 1] = { id=id,label=entry.label,category=entry.category or 'Marks',image=entry.image,art=entry.art,emblem=entry.emblem,logo=entry.logo } end
    for id, entry in pairs(Weapons.Stickers.surfaces[weapon]) do surfaces[#surfaces + 1] = { id = id, label = entry.label, halfWidth = entry.halfWidth, halfHeight = entry.halfHeight } end
    table.sort(designs, function(a, b) return a.id < b.id end)
    table.sort(surfaces,function(a,b)return a.id<b.id end)
    return { ok = true, enabled = true, removeOnly = not Weapons.Stickers.enabled, serial = meta.serial, designs = designs, surfaces = surfaces,
        maxCount=math.min(5,Weapons.Stickers.maxCount or 5),minSize=Weapons.Stickers.minSize,maxSize=Weapons.Stickers.maxSize,
        entries = Weapons.ValidStickers(weapon, meta.weaponStickers or {}) or {} }
end)

BSB.RegisterCallback('weapons:stickerSave', function(src, weapon, serial, entries)
    if type(weapon) ~= 'string' or busy[src] then return { ok = false } end
    Weapons.RefreshStickerCatalogue()
    local clean = Weapons.ValidStickers(weapon, entries)
    if not clean then return { ok = false, error = 'Sticker extends beyond the configured surface or uses invalid values' } end
    if not Weapons.Stickers.enabled and #clean > 0 then return { ok = false, error = 'Experimental stickers are disabled; existing stickers can only be cleared' } end
    local slot, _, meta = Weapons.Instance(src, weapon)
    if not slot or meta.serial ~= serial then return { ok = false, error = 'The selected weapon has changed' } end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 or GetSelectedPedWeapon(ped) ~= GetHashKey(weapon) then
        return { ok = false, error = 'Hold the selected weapon before saving its stickers' }
    end
    busy[src] = true
    local ok, result = pcall(function() return exports.bs_inventory:UpdateWeaponStickers(src, slot, serial, clean, Weapons.StickerDesignRules()) end)
    busy[src] = nil
    if not ok then return { ok = false, error = 'Could not save the weapon stickers' } end
    if result and result.ok then Weapons.PublishStickers(src, weapon, result.metadata) end
    return result or { ok = false }
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)
AddEventHandler('bs:hook:player:unloaded', function(player)
    if player and player.source then
        busy[player.source] = nil
        Player(player.source).state:set('bsWeaponStickers', nil, true)
    end
end)
