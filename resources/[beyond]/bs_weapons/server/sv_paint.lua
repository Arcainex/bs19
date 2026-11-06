-- Experimental weapon paint storage. Keyed by the weapon's serial, so it follows the gun through trades and drops.
-- Kept in this resource's KVP store: no inventory or database schema change.
local busy={}
local function key(serial)return 'paint:'..tostring(serial)end
function Weapons.LoadPaint(serial)
    if not serial then return nil end
    local raw=GetResourceKvpString(key(serial))
    if not raw or raw==''then return nil end
    local ok,data=pcall(json.decode,raw)
    return ok and Weapons.ValidPaint(data)or nil
end
function Weapons.PublishPaint(src,weapon,meta)
    local paint=Weapons.Paint.enabled and meta and Weapons.LoadPaint(meta.serial)or nil
    Player(src).state:set('bsWeaponPaint',paint and {weapon=weapon,serial=meta.serial,paint=paint}or nil,true)
end
BSB.RegisterCallback('weapons:paintState',function(src,weapon)
    if type(weapon)~='string'then return {ok=false}end
    local slot,_,meta=Weapons.Instance(src,weapon)
    if not slot then return {ok=false}end
    return {ok=true,enabled=Weapons.Paint.enabled==true,serial=meta.serial,paint=Weapons.LoadPaint(meta.serial)}
end)
BSB.RegisterCallback('weapons:paintSave',function(src,weapon,serial,paint)
    if type(weapon)~='string'or busy[src]then return {ok=false,error='Paint shop is busy.'}end
    if Weapons.Settings.editorEnabled==false then return {ok=false,error='The weapon cosmetic editor is disabled.'}end
    local clean=nil
    if paint~=nil then
        if not Weapons.Paint.enabled then return {ok=false,error='Weapon paint is switched off on this server.'}end
        clean=Weapons.ValidPaint(paint)
        if not clean then return {ok=false,error='That paint job is too large or invalid.'}end
        local encoded=json.encode(clean)
        if #encoded>16000 then return {ok=false,error='That paint job has too many brush strokes.'}end
    end
    local slot,_,meta=Weapons.Instance(src,weapon)
    if not slot or meta.serial~=serial then return {ok=false,error='The selected weapon has changed.'}end
    local ped=GetPlayerPed(src)
    if ped==0 or GetEntityHealth(ped)<=0 or GetSelectedPedWeapon(ped)~=GetHashKey(weapon)then return {ok=false,error='Hold the weapon to save its paint.'}end
    busy[src]=true
    if clean then SetResourceKvp(key(serial),json.encode(clean))else DeleteResourceKvp(key(serial))end
    busy[src]=nil
    Weapons.PublishPaint(src,weapon,meta)
    return {ok=true,paint=clean}
end)
AddEventHandler('playerDropped',function()busy[source]=nil end)
AddEventHandler('bs:hook:player:unloaded',function(player)
    if player and player.source then Player(player.source).state:set('bsWeaponPaint',nil,true)end
end)
