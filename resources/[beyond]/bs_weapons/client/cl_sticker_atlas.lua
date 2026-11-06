-- Sticker atlas: the designs that have no picture of their own - faction emblems from bs_factions, and any design
-- whose PNG is missing - are drawn by one DUI page into a runtime texture. The page lays up to 64 tiles of 128 px in
-- a 1024x1024 surface and the tile tables here carry the matching UVs. Everything with a picture in html/stickers is
-- drawn from that file instead (cl_stickers.lua), so this page only has to paint when one of those designs is worn.
Weapons.StickerAtlas={version=0}
local A=Weapons.StickerAtlas
local DICT='bs_sticker_atlas'
local TILE,INSET,SIZE,MAX=128,4,1024,64
local entries,tiles,record={}, {},nil
local sequence,retryAt,stamp,failures=0,0,'',0
local txd
local function stop()
    if record and record.dui then DestroyDui(record.dui)end
    record=nil
end
local function sendAtlas()
    if record and record.dui and record.loaded then
        SendDuiMessage(record.dui,json.encode({action='atlas',entries=entries,token=record.token}))
    end
end
-- Faction emblems always need the page: their artwork is made at run time by bs_ui's emblem.js.
local function needsAtlas(d)
    return type(d)=='table'and not d.image and (d.art=='faction' or d.art==nil)
end
local function update(list)
    if type(list)~='table'then return end
    for id in pairs(Weapons.Stickers.designs)do if id:sub(1,8)=='faction:'then Weapons.Stickers.designs[id]=nil end end
    for _,d in ipairs(list)do if type(d.id)=='string'and #d.id<=64 then
        local copy={};for k,v in pairs(d)do copy[k]=v end;copy.id=nil
        Weapons.Stickers.designs[d.id]=copy
    end end
    local nextEntries={}
    for id,d in pairs(Weapons.Stickers.designs)do if type(d)=='table'then
        local item={id=id};for k,v in pairs(d)do item[k]=v end;nextEntries[#nextEntries+1]=item
    end end
    -- Tile order is sent to the page, so the order here is the order it paints: designs that need the page first.
    table.sort(nextEntries,function(a,b)
        local ap,bp=needsAtlas(a)and 0 or 1,needsAtlas(b)and 0 or 1
        if ap~=bp then return ap<bp end
        return a.id<b.id
    end)
    while #nextEntries>MAX do table.remove(nextEntries)end
    local nextStamp=json.encode(nextEntries)
    if nextStamp==stamp then return end
    stamp=nextStamp;entries=nextEntries;A.version=A.version+1
    -- Callers keep the tile table they were given, so their UVs and texture name move with the atlas.
    local keep=tiles;tiles={}
    for i,d in ipairs(entries)do
        local col,row=(i-1)%8,math.floor((i-1)/8)
        local t=keep[d.id]or {}
        t.name,t.dictionary=record and record.txn or 'atlas',DICT
        t.u0,t.v0,t.u1,t.v1=(col*TILE+INSET)/SIZE,(row*TILE+INSET)/SIZE,(col*TILE+TILE-INSET)/SIZE,(row*TILE+TILE-INSET)/SIZE
        t.version=A.version
        tiles[d.id]=t
    end
    sendAtlas()
end
A.Update=update
RegisterNetEvent('bs:weapons:stickerCatalogue',update)
RegisterNUICallback('stickerAtlasPage',function(data,cb)
    local current=record
    if current and data.token==current.token then current.loaded=true;sendAtlas()end
    cb({ok=true})
end)
RegisterNUICallback('stickerAtlasReady',function(data,cb)
    local current=record
    if current and data.token==current.token then
        current.painted=true
        if Weapons.Stickers.debug then
            print(('[bs_weapons] sticker atlas page painted %s tiles'):format(tostring(data.count)))
        end
    end
    cb({ok=true})
end)
local function start()
    if record or #entries==0 or GetGameTimer()<retryAt then return end
    sequence=sequence+1
    local current={token=sequence};record=current
    CreateThread(function()
        local ok,reason=pcall(function()
            txd=txd or CreateRuntimeTxd(DICT)
            if not txd or txd==0 then txd=nil;error('Sticker texture dictionary unavailable')end
            current.dui=CreateDui(('https://cfx-nui-%s/html/sticker-atlas.html?resource=%s&token=%s'):format(GetCurrentResourceName(),GetCurrentResourceName(),current.token),SIZE,SIZE)
            if not current.dui or current.dui==0 then error('Sticker atlas page could not be created')end
            local untilAt=GetGameTimer()+8000
            local resendAt=0
            while record==current and GetGameTimer()<untilAt and (not IsDuiAvailable(current.dui)or not current.painted)do
                -- The page asks for the list itself; resend in case that first request was missed.
                if IsDuiAvailable(current.dui)and GetGameTimer()>resendAt then current.loaded=true;sendAtlas();resendAt=GetGameTimer()+1500 end
                Wait(25)
            end
            if record~=current then return end
            if not current.painted then error('Sticker atlas page did not draw in time')end
            -- A fresh texture name per page: a name can only be created once inside a runtime dictionary.
            current.txn='atlas'..current.token
            local texture=CreateRuntimeTextureFromDuiHandle(txd,current.txn,GetDuiHandle(current.dui))
            if not texture or texture==0 then error('Sticker atlas texture unavailable')end
            for _,t in pairs(tiles)do t.name=current.txn end
            current.ready=true
            if Weapons.Stickers.debug then print(('[bs_weapons] sticker atlas ready: %s/%s'):format(DICT,current.txn))end
        end)
        if not ok and record==current then
            stop()
            -- Back off further each time, so a broken page cannot keep rebuilding a browser every few seconds.
            failures=failures+1
            retryAt=GetGameTimer()+(failures>=3 and 60000 or 5000*failures)
            print('[bs_weapons] '..tostring(reason))
        end
    end)
end
function A.TextureName()return record and record.ready and record.txn or nil end
function A.GetTexture(id)
    start()
    if not record or not record.ready then return end
    return tiles[id]
end
local function fetch()
    local ok,list=pcall(BSB.Await,'weapons:stickerCatalogue',8000)
    if ok and type(list)=='table'then update(list);return true end
    return false
end
RegisterNetEvent('bs:factions:emblem',function()CreateThread(fetch)end)
AddEventHandler('onClientResourceStart',function(name)if name=='bs_factions'then CreateThread(fetch)end end)
CreateThread(function()Wait(2000);for attempt=1,3 do if fetch()then break end;Wait(3000)end end)
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName()then stop()end end)
