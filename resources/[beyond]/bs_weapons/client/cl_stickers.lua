-- Sticker textures: every design is its own picture in html/stickers (art or PNG), drawn into one runtime dictionary
-- and tinted by the vertex colour in the draw below. Designs with no shipped picture (faction emblems from
-- bs_factions) come from the live atlas in cl_sticker_atlas.lua instead.
local preview, targets = nil, {}
local textures, dictionary = {}, 'bs_weapon_stickers'
local txd, tried = nil, {}

local function runtimeTxd()
    if txd then return txd end
    local ok, value = pcall(CreateRuntimeTxd, dictionary)
    if ok and value and value ~= 0 then txd = value end
    return txd
end

-- The file behind a design: its configured image, else the picture generated from its art in html/stickers.
local function imageFor(entry, id)
    if type(entry) ~= 'table' then return nil end
    if entry.image then return entry.image end
    if entry.art and entry.art ~= 'faction' then return 'html/stickers/'..id..'.png' end
end

-- One runtime texture per design, made the first time it is drawn. A design whose picture is missing keeps its
-- attempt recorded so the file is not asked for every frame; the live atlas then has a go at it.
local function textureFor(id)
    local texture = textures[id]
    if texture then return texture end
    local file = imageFor(Weapons.Stickers.designs[id], id)
    if file and not tried[id] then
        local handle = runtimeTxd()
        if not handle then return end
        tried[id] = true
        local ok, value = pcall(CreateRuntimeTextureFromImage, handle, id, file)
        if ok and value and value ~= 0 then
            textures[id] = { name = id, dictionary = dictionary, u0 = 0, v0 = 0, u1 = 1, v1 = 1 }
            return textures[id]
        end
    end
    if Weapons.StickerAtlas then texture = Weapons.StickerAtlas.GetTexture(id) end
    if texture then textures[id] = texture end
    return texture
end

local function refreshOwnPreview()
    local ped=PlayerPedId()
    for i=#targets,1,-1 do if targets[i].ped==ped then table.remove(targets,i)end end
    local data=preview or Player(GetPlayerServerId(PlayerId())).state.bsWeaponStickers
    if not data then return end
    local entries=Weapons.ValidStickers(data.weapon,data.entries)
    local object=Weapons.InspectionObject and Weapons.InspectionObject()or nil
    object=object or GetCurrentPedWeaponEntityIndex(ped,0)
    if not entries or not object or object==0 or not DoesEntityExist(object)then return end
    local quads={}
    for _,entry in ipairs(entries)do
        local plane=Weapons.Stickers.surfaces[data.weapon][entry.surface]
        plane=Weapons.ResolveStickerPlane and Weapons.ResolveStickerPlane(plane,object)or plane
        quads[#quads+1]={design=entry.design,colour=entry.colour,opacity=entry.opacity,corners=Weapons.StickerQuadCorners and Weapons.StickerQuadCorners(plane,entry,data.weapon)or Weapons.StickerCorners(plane,entry)}
    end
    if #quads>0 then targets[#targets+1]={ped=ped,weapon=GetHashKey(data.weapon),quads=quads,distance=-1}end
end
function Weapons.PreviewStickers(entries, weapon, serial)
    if entries == nil then preview=nil;refreshOwnPreview();return true end
    if not Weapons.Stickers.enabled then return false end
    local clean = Weapons.ValidStickers(weapon, entries)
    if not clean then return false end
    if not (Weapons.InspectionObject and Weapons.InspectionObject())and Weapons.HeldWeapon()~=weapon then return false end
    preview = { weapon = weapon, serial = serial, entries = clean }
    refreshOwnPreview()
    return true
end

local function collect()
    local out = {}
    if not Weapons.Stickers.enabled then return out end
    local origin = GetEntityCoords(PlayerPedId())
    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        local data = player == PlayerId() and preview or Player(GetPlayerServerId(player)).state.bsWeaponStickers
        if data and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
            local at = GetEntityCoords(ped)
            local dx, dy, dz = at.x - origin.x, at.y - origin.y, at.z - origin.z
            local distance = dx * dx + dy * dy + dz * dz
            if distance <= math.min(12, Weapons.Stickers.drawDistance) ^ 2
                and ((player==PlayerId()and Weapons.InspectionObject and Weapons.InspectionObject())or GetSelectedPedWeapon(ped)==GetHashKey(data.weapon))
                and (player == PlayerId() or HasEntityClearLosToEntity(PlayerPedId(), ped, 17)) then
                local entries = Weapons.ValidStickers(data.weapon, data.entries)
                if entries and #entries > 0 and Weapons.EnsureStickerDepth then Weapons.EnsureStickerDepth(data.weapon) end
                if entries and #entries > 0 then
                    local quads = {}
                    for _, entry in ipairs(entries) do
                        if textureFor(entry.design) then
                            local object=player==PlayerId()and Weapons.InspectionObject and Weapons.InspectionObject()or nil
                            object=object or GetCurrentPedWeaponEntityIndex(ped,0)
                            local plane=Weapons.Stickers.surfaces[data.weapon][entry.surface]
                            plane=Weapons.ResolveStickerPlane and Weapons.ResolveStickerPlane(plane,object)or plane
                            quads[#quads+1]={design=entry.design,colour=entry.colour,opacity=entry.opacity,corners=Weapons.StickerQuadCorners and Weapons.StickerQuadCorners(plane,entry,data.weapon)or Weapons.StickerCorners(plane,entry)}
                        end
                    end
                    if #quads > 0 then out[#out + 1] = { ped = ped, weapon = GetHashKey(data.weapon), quads = quads, distance = distance } end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.distance < b.distance end)
    while #out > math.min(6, Weapons.Stickers.maxVisiblePlayers) do table.remove(out) end
    return out
end

CreateThread(function()
    while true do
        targets = collect()
        Wait(250)
    end
end)

-- World textured triangle. native 'basic' = DRAW_TEXTURED_POLY (0x29280002282F1928): 9 coords, r,g,b,a (0-255),
-- dict, name, then u,v,w per corner. 'uv' = DRAW_TEXTURED_POLY_UV (0x736D7AA1B750856B): same, but r,g,b,a per corner.
function Weapons.StickerPoly(a,b,c,r,g,bl,al,dict,name,ua,va,ub,vb,uc,vc,native)
    native=native or (Weapons.Stickers.poly and Weapons.Stickers.poly.native)or 'basic'
    if native=='uv'then
        Citizen.InvokeNative(0x736D7AA1B750856B,a.x+0.0,a.y+0.0,a.z+0.0,b.x+0.0,b.y+0.0,b.z+0.0,c.x+0.0,c.y+0.0,c.z+0.0,
            r,g,bl,al,r,g,bl,al,r,g,bl,al,dict,name,ua+0.0,va+0.0,1.0,ub+0.0,vb+0.0,1.0,uc+0.0,vc+0.0,1.0)
    else
        Citizen.InvokeNative(0x29280002282F1928,a.x+0.0,a.y+0.0,a.z+0.0,b.x+0.0,b.y+0.0,b.z+0.0,c.x+0.0,c.y+0.0,c.z+0.0,
            r,g,bl,al,dict,name,ua+0.0,va+0.0,1.0,ub+0.0,vb+0.0,1.0,uc+0.0,vc+0.0,1.0)
    end
end
local function triangle(a, b, c, design, ua, va, ub, vb, uc, vc, colour, opacity)
    local texture = textureFor(design)
    if not texture then return end
    local function uv(u, v) return texture.u0 + u*(texture.u1 - texture.u0), texture.v0 + v*(texture.v1 - texture.v0) end
    ua, va = uv(ua, va); ub, vb = uv(ub, vb); uc, vc = uv(uc, vc)
    -- The pictures are light artwork, so the vertex colour both keeps them as drawn (#FFFFFF) and tints them.
    colour = colour or '#FFFFFF'
    if Weapons.Stickers.debug then
        local key = design..colour
        Weapons.Stickers.debugSeen = Weapons.Stickers.debugSeen or {}
        if not Weapons.Stickers.debugSeen[key] then
            Weapons.Stickers.debugSeen[key] = true
            print(('[bs_weapons] sticker draw %s colour=%s texture=%s/%s uv=%.3f..%.3f'):format(design, colour,
                tostring(texture.dictionary), tostring(texture.name), texture.u0, texture.u1))
        end
    end
    local red,green,blue = tonumber(colour:sub(2, 3), 16) or 255, tonumber(colour:sub(4, 5), 16) or 255, tonumber(colour:sub(6, 7), 16) or 255
    local alpha = math.floor(math.max(.1, math.min(1, opacity or 1))*255 + .5)
    if Weapons.Stickers.debug then Weapons.Stickers.debugDesign,Weapons.Stickers.debugRGB=design,{red,green,blue,alpha}end
    Weapons.StickerPoly(a,b,c,math.floor(red),math.floor(green),math.floor(blue),alpha,texture.dictionary,texture.name,ua,va,ub,vb,uc,vc)
end

-- Marker path (default). World textured polys render a runtime texture's colour black (front face lit black,
-- back face culled; seen in the /stickerdebug self-test), so stickers are drawn as flat textured markers instead.
-- Markers are unlit and take the colour as a tint. The image is assumed to lie on the marker's local X/Y plane
-- facing +Z ('xy'); 'xz' = lying on X/Z facing -Y. Weapons.Stickers.markerPlane picks one.
local function v3(x,y,z)return vector3(x+0.0,y+0.0,z+0.0)end
local function crossv(a,b)return v3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)end
local function norm(a)local l=math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z);if l<1e-9 then return v3(0,0,0),0 end;return v3(a.x/l,a.y/l,a.z/l),l end
-- Euler angles for rotation order 2, the same convention the workbench uses for attached props.
-- X, Y, Z are where the marker's own axes must end up in the world.
local function eulerFrom(X,Y,Z)
    local m32=math.max(-1,math.min(1,Y.z))
    local rx=math.deg(math.asin(m32))
    local ry,rz
    if math.abs(m32)<.9999999 then ry,rz=math.deg(math.atan(-X.z,Z.z)),math.deg(math.atan(-Y.x,Y.y))
    else ry,rz=0.0,math.deg(math.atan(X.y,X.x))end
    return rx,ry,rz
end
function Weapons.StickerMarker(c,right,up,w,h,r,g,b,a,dict,name,plane)
    plane=plane or Weapons.Stickers.markerPlane or 'xy'
    local n=crossv(right,up)
    local X,Y,Z,sx,sy,sz
    if plane=='xz'then X,Y,Z,sx,sy,sz=right,v3(-n.x,-n.y,-n.z),up,w,1.0,h
    else X,Y,Z,sx,sy,sz=right,up,n,w,h,1.0 end
    local rx,ry,rz=eulerFrom(X,Y,Z)
    DrawMarker(9,c.x,c.y,c.z,0.0,0.0,0.0,rx,ry,rz,sx+0.0,sy+0.0,sz+0.0,r,g,b,a,false,false,2,false,dict,name,false)
end
local function drawMarker(p,quad)
    if (Weapons.Stickers.draw or 'marker')~='marker'then return false end
    local texture=textureFor(quad.design)
    -- A marker shows a whole texture; atlas tiles (faction emblems) are part of one, so they stay on the poly path.
    if not texture or texture.u0~=0 or texture.u1~=1 then return false end
    local right,w=norm(p[2]-p[1]);local up,h=norm(p[4]-p[1])
    local c=(p[1]+p[3])*0.5
    local colour=quad.colour or '#FFFFFF'
    local red,green,blue=tonumber(colour:sub(2,3),16)or 255,tonumber(colour:sub(4,5),16)or 255,tonumber(colour:sub(6,7),16)or 255
    local alpha=math.floor(math.max(.1,math.min(1,quad.opacity or 1))*255+.5)
    if Weapons.Stickers.debug then
        Weapons.Stickers.debugDesign,Weapons.Stickers.debugRGB=quad.design,{red,green,blue,alpha}
        Weapons.Stickers.debugSeen=Weapons.Stickers.debugSeen or {}
        local key='m'..quad.design..colour
        if not Weapons.Stickers.debugSeen[key]then Weapons.Stickers.debugSeen[key]=true
            print(('[bs_weapons] sticker marker %s colour=%s size=%.3fx%.3f texture=%s/%s'):format(quad.design,colour,w,h,texture.dictionary,texture.name))end
    end
    Weapons.StickerMarker(c,right,up,w,h,red,green,blue,alpha,texture.dictionary,texture.name)
    return true
end
function Weapons.DrawStickerTargets(list)
    if not Weapons.Stickers.enabled then return end
    for _, target in ipairs(list) do
        if DoesEntityExist(target.ped) and not IsEntityDead(target.ped) and ((target.ped==PlayerPedId()and Weapons.InspectionObject and Weapons.InspectionObject())or GetSelectedPedWeapon(target.ped)==target.weapon)then
            local object=target.ped==PlayerPedId() and Weapons.InspectionObject and Weapons.InspectionObject() or nil
            object=object or GetCurrentPedWeaponEntityIndex(target.ped,0)
            if object and object ~= 0 and DoesEntityExist(object) then
                for _, quad in ipairs(target.quads) do
                    local p = {}
                    for i, corner in ipairs(quad.corners) do p[i] = GetOffsetFromEntityInWorldCoords(object, corner.x, corner.y, corner.z) end
                    if not drawMarker(p, quad) then
                    local flip=(Weapons.Stickers.poly and Weapons.Stickers.poly.flip)or 'off'
                    if flip~='only'then
                        triangle(p[1], p[2], p[3], quad.design, 0, 1, 1, 1, 1, 0, quad.colour, quad.opacity)
                        triangle(p[1], p[3], p[4], quad.design, 0, 1, 1, 0, 0, 0, quad.colour, quad.opacity)
                    end
                    if flip~='off'then
                        -- Same quad wound the other way and 0.15 mm further out. A world poly is lit from the side its
                        -- winding faces; if the first copy faces into the gun it renders black, this one is lit.
                        local ax,ay,az=p[2].x-p[1].x,p[2].y-p[1].y,p[2].z-p[1].z
                        local bx,by,bz=p[3].x-p[1].x,p[3].y-p[1].y,p[3].z-p[1].z
                        local nx,ny,nz=ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx
                        local len=math.sqrt(nx*nx+ny*ny+nz*nz);if len<1e-9 then len=1 end
                        local k=.00015/len
                        local q={}
                        for i=1,4 do q[i]=vector3(p[i].x+nx*k,p[i].y+ny*k,p[i].z+nz*k)end
                        triangle(q[1], q[3], q[2], quad.design, 0, 1, 1, 0, 1, 1, quad.colour, quad.opacity)
                        triangle(q[1], q[4], q[3], quad.design, 0, 1, 0, 0, 1, 0, quad.colour, quad.opacity)
                    end
                    end
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        if #targets > 0 and Weapons.Stickers.enabled then
            Weapons.DrawStickerTargets(targets)
            Wait(0)
        else Wait(Weapons.Stickers.enabled and Weapons.InspectionObject and Weapons.InspectionObject()and 0 or 250)end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then targets = {}; preview = nil end
end)

-- /stickerdebug: prints the colour, texture and UV that reach the sticker draw once per change.
-- /stickerdebug texture: shows the live atlas for 15 s (left: designs that need it, i.e. faction emblems).
RegisterCommand('stickerdebug',function(_,args)
    if args[1]=='texture'then
        local name=Weapons.StickerAtlas and Weapons.StickerAtlas.TextureName()
        if not name then print('[bs_weapons] sticker atlas is not ready yet');return end
        print('[bs_weapons] drawing bs_sticker_atlas/'..name)
        CreateThread(function()
            local untilAt=GetGameTimer()+15000
            while GetGameTimer()<untilAt do
                DrawRect(.5,.5,.92,.48,40,40,40,230)
                DrawSprite('bs_sticker_atlas',name,.5,.5,.9,.45,0.0,255,255,255,255)
                Wait(0)
            end
        end)
        return
    end
    if args[1]=='mode'then
        -- /stickerdebug mode marker [xy|xz]   or   /stickerdebug mode poly [basic|uv] [off|both|only]
        if args[2]=='marker'then
            Weapons.Stickers.draw='marker'
            if args[3]=='xy'or args[3]=='xz'then Weapons.Stickers.markerPlane=args[3]end
        elseif args[2]=='poly'then
            Weapons.Stickers.draw='poly';Weapons.Stickers.poly=Weapons.Stickers.poly or {}
            if args[3]=='basic'or args[3]=='uv'then Weapons.Stickers.poly.native=args[3]end
            if args[4]=='off'or args[4]=='both'or args[4]=='only'then Weapons.Stickers.poly.flip=args[4]end
        end
        local P=Weapons.Stickers.poly or {}
        print(('[bs_weapons] sticker draw: %s (marker plane %s; poly %s, flip %s)'):format(Weapons.Stickers.draw or 'marker',
            Weapons.Stickers.markerPlane or 'xy',P.native or 'basic',P.flip or 'off'))
        return
    end
    Weapons.Stickers.debug=not Weapons.Stickers.debug;Weapons.Stickers.debugSeen={}
    local shipped=0
    for id in pairs(textures)do if id then shipped=shipped+1 end end
    print(('[bs_weapons] sticker colour debug %s (%s designs textured, atlas %s)'):format(
        Weapons.Stickers.debug and 'on'or'off',shipped,
        Weapons.StickerAtlas and Weapons.StickerAtlas.TextureName()or'not ready'))
end,false)

-- Self-test while /stickerdebug is on. Top left, left to right:
--   1 raw texture (DrawSprite)   2 same, tinted green (DrawSprite)
--   3-6 world quads in front of the camera, tinted green: basic front, basic flipped, uv front, uv flipped.
-- Whichever square shows the art in green is the path that works; F8 gets the texture size and colour.
local function label(text,x,y)
    SetTextFont(4);SetTextScale(.28,.28);SetTextColour(255,255,255,230);SetTextOutline()
    BeginTextCommandDisplayText('STRING');AddTextComponentSubstringPlayerName(text);EndTextCommandDisplayText(x,y)
end
CreateThread(function()
    local printed
    while true do
        if not Weapons.Stickers.debug then Wait(500)
        else
            Wait(0)
            local design=Weapons.Stickers.debugDesign or 'biohazard'
            local tex=textureFor(design)
            if tex then
                local dict,name=tex.dictionary,tex.name
                DrawRect(.17,.13,.32,.2,0,0,0,170)
                DrawSprite(dict,name,.05,.1,.05,.09,0.0,255,255,255,255);label('1 raw',.03,.16)
                DrawSprite(dict,name,.11,.1,.05,.09,0.0,40,200,40,255);label('2 green',.09,.16)
                local cam=GetFinalRenderedCamCoord();local rot=GetFinalRenderedCamRot(2)
                local yaw,pitch=math.rad(rot.z),math.rad(rot.x)
                local f=vector3(-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch))
                local r=vector3(math.cos(yaw),math.sin(yaw),0.0)
                local u=vector3(r.y*f.z-r.z*f.y,r.z*f.x-r.x*f.z,r.x*f.y-r.y*f.x)
                local fov=math.rad(GetFinalRenderedCamFov());local d=.5;local h=math.tan(fov*.5)*d
                local w=h*GetAspectRatio(false)
                for i,mode in ipairs({{'basic',false},{'basic',true},{'uv',false},{'uv',true}})do
                    -- squares under the sprites, across the top-left of the screen
                    local cx=(-.80+(i-1)*.12)*w;local cy=.55*h;local s=.045*h
                    local c=cam+f*d+r*cx+u*cy
                    local p1,p2,p3,p4=c-r*s-u*s,c+r*s-u*s,c+r*s+u*s,c-r*s+u*s
                    if mode[2]then
                        Weapons.StickerPoly(p1,p3,p2,40,200,40,255,dict,name,0,1,1,0,1,1,mode[1]);Weapons.StickerPoly(p1,p4,p3,40,200,40,255,dict,name,0,1,0,0,1,0,mode[1])
                    else
                        Weapons.StickerPoly(p1,p2,p3,40,200,40,255,dict,name,0,1,1,1,1,0,mode[1]);Weapons.StickerPoly(p1,p3,p4,40,200,40,255,dict,name,0,1,1,0,0,0,mode[1])
                    end
                end
                -- 7: marker, image assumed on X/Y; 8: marker, image assumed on X/Z. The one that shows a green,
                -- upright, unmirrored biohazard is the right markerPlane.
                for i,plane in ipairs({'xy','xz'})do
                    local cx=(-.80+(i+3)*.12)*w;local cy=.55*h;local s=.045*h
                    local c=cam+f*d+r*cx+u*cy
                    Weapons.StickerMarker(c,r,u,s*2,s*2,40,200,40,255,dict,name,plane)
                end
                label('3 basic  4 flip  5 uv  6 flip  7 marker xy  8 marker xz',.15,.16)
                if printed~=design then
                    printed=design
                    local res=GetTextureResolution(dict,name)
                    local rgb=Weapons.Stickers.debugRGB or {}
                    print(('[bs_weapons] sticker self-test %s: texture %s/%s %dx%d (4x4 = missing), last draw rgba %s,%s,%s,%s, draw %s, marker plane %s')
                        :format(design,dict,name,math.floor(res.x),math.floor(res.y),tostring(rgb[1]),tostring(rgb[2]),tostring(rgb[3]),tostring(rgb[4]),
                        tostring(Weapons.Stickers.draw or 'marker'),Weapons.Stickers.markerPlane or 'xy'))
                end
            end
        end
    end
end)
