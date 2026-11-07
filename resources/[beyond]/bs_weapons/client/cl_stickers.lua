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
    native=native or (Weapons.Stickers.draw and Weapons.Stickers.draw.native)or 'basic'
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
        if Weapons.Stickers.debugSeen ~= key then
            Weapons.Stickers.debugSeen = key
            print(('[bs_weapons] sticker draw %s colour=%s texture=%s/%s uv=%.3f..%.3f'):format(design, colour,
                tostring(texture.dictionary), tostring(texture.name), texture.u0, texture.u1))
        end
    end
    local red,green,blue = tonumber(colour:sub(2, 3), 16) or 255, tonumber(colour:sub(4, 5), 16) or 255, tonumber(colour:sub(6, 7), 16) or 255
    local alpha = math.floor(math.max(.1, math.min(1, opacity or 1))*255 + .5)
    if Weapons.Stickers.debug then Weapons.Stickers.debugDesign,Weapons.Stickers.debugRGB=design,{red,green,blue,alpha}end
    Weapons.StickerPoly(a,b,c,math.floor(red),math.floor(green),math.floor(blue),alpha,texture.dictionary,texture.name,ua,va,ub,vb,uc,vc)
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
                    local flip=(Weapons.Stickers.draw and Weapons.Stickers.draw.flip)or 'both'
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
        Weapons.Stickers.draw=Weapons.Stickers.draw or {}
        if args[2]=='basic'or args[2]=='uv'then Weapons.Stickers.draw.native=args[2]end
        if args[3]=='off'or args[3]=='both'or args[3]=='only'then Weapons.Stickers.draw.flip=args[3]end
        print(('[bs_weapons] sticker draw: native=%s flip=%s'):format(Weapons.Stickers.draw.native or 'basic',Weapons.Stickers.draw.flip or 'both'))
        return
    end
    Weapons.Stickers.debug=not Weapons.Stickers.debug;Weapons.Stickers.debugSeen=nil
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
                label('3 basic  4 basic flip  5 uv  6 uv flip',.15,.16)
                if printed~=design then
                    printed=design
                    local res=GetTextureResolution(dict,name)
                    local rgb=Weapons.Stickers.debugRGB or {}
                    print(('[bs_weapons] sticker self-test %s: texture %s/%s %dx%d (4x4 = missing), last draw rgba %s,%s,%s,%s, mode %s flip %s')
                        :format(design,dict,name,math.floor(res.x),math.floor(res.y),tostring(rgb[1]),tostring(rgb[2]),tostring(rgb[3]),tostring(rgb[4]),
                        (Weapons.Stickers.draw and Weapons.Stickers.draw.native)or 'basic',(Weapons.Stickers.draw and Weapons.Stickers.draw.flip)or 'both'))
                end
            end
        end
    end
end)
