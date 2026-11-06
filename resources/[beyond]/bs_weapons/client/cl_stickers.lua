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
    -- DRAW_TEXTURED_POLY, formerly _DRAW_SPRITE_POLY. Coordinates are in world space, uvw per corner.
    Citizen.InvokeNative(0x29280002282F1928, a.x + 0.0, a.y + 0.0, a.z + 0.0,
        b.x + 0.0, b.y + 0.0, b.z + 0.0, c.x + 0.0, c.y + 0.0, c.z + 0.0,
        red, green, blue, alpha, texture.dictionary, texture.name, ua + 0.0, va + 0.0, 1.0,
        ub + 0.0, vb + 0.0, 1.0, uc + 0.0, vc + 0.0, 1.0)
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
                    triangle(p[1], p[2], p[3], quad.design, 0, 1, 1, 1, 1, 0, quad.colour, quad.opacity)
                    triangle(p[1], p[3], p[4], quad.design, 0, 1, 1, 0, 0, 0, quad.colour, quad.opacity)
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
    Weapons.Stickers.debug=not Weapons.Stickers.debug;Weapons.Stickers.debugSeen=nil
    local shipped=0
    for id in pairs(textures)do if id then shipped=shipped+1 end end
    print(('[bs_weapons] sticker colour debug %s (%s designs textured, atlas %s)'):format(
        Weapons.Stickers.debug and 'on'or'off',shipped,
        Weapons.StickerAtlas and Weapons.StickerAtlas.TextureName()or'not ready'))
end,false)
