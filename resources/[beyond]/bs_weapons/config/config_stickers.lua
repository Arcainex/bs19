Weapons.Stickers = {
    enabled = false,
    maxCount = 5,
    minSize = 0.015,
    maxSize = 0.06,
    drawDistance = 8.0,
    maxVisiblePlayers = 6,
    designs = {
        skull = { label = 'Skull', image = 'html/stickers/skull.png' },
        star = { label = 'Field star', image = 'html/stickers/star.png' },
        hazard = { label = 'Hazard', image = 'html/stickers/hazard.png' },
    },
    -- Named receiver planes are model-specific; verify custom replacement weapon meshes in-game.
    surfaces = {},
}

-- Stencil designs share the same vector art in the library and native decal atlas.
Weapons.Stickers.designs.radiation={label='Radiation',art='radiation',category='Warnings'}
Weapons.Stickers.designs.biohazard={label='Biohazard',art='biohazard',category='Warnings'}
Weapons.Stickers.designs.quarantine={label='Quarantine',art='quarantine',category='Warnings'}
Weapons.Stickers.designs.infected={label='Infected',art='infected',category='Warnings'}
Weapons.Stickers.designs.survivor={label='Survivor',art='survivor',category='Marks'}
Weapons.Stickers.designs.no_mercy={label='No mercy',art='no_mercy',category='Marks'}
Weapons.Stickers.designs.dead_inside={label='Dead inside',art='dead_inside',category='Marks'}
Weapons.Stickers.designs.do_not_open={label='Do not open',art='do_not_open',category='Warnings'}
Weapons.Stickers.designs.stay_back={label='Stay back',art='stay_back',category='Warnings'}
Weapons.Stickers.designs.last_round={label='Last round',art='last_round',category='Marks'}
Weapons.Stickers.designs.lightning={label='Lightning',art='lightning',category='Marks'}
Weapons.Stickers.designs.cross={label='Field medic',art='cross',category='Marks'}
Weapons.Stickers.designs.crosshair={label='Crosshair',art='crosshair',category='Marks'}
Weapons.Stickers.designs.eye={label='Watchful eye',art='eye',category='Marks'}
Weapons.Stickers.designs.claw={label='Claw marks',art='claw',category='Marks'}
Weapons.Stickers.designs.tally={label='Kill tally',art='tally',category='Marks'}
Weapons.Stickers.designs.wolf={label='Wolf',art='wolf',category='Marks'}
Weapons.Stickers.designs.raven={label='Raven',art='raven',category='Marks'}
Weapons.Stickers.designs.snake={label='Snake',art='snake',category='Marks'}
Weapons.Stickers.designs.reaper={label='Reaper',art='reaper',category='Marks'}
Weapons.Stickers.designs.broken_heart={label='Broken heart',art='broken_heart',category='Marks'}
Weapons.Stickers.designs.blood_hand={label='Bloody hand',art='blood_hand',category='Marks'}
Weapons.Stickers.designs.scavenger={label='Scavenger',art='scavenger',category='Marks'}
Weapons.Stickers.designs.chevrons={label='Rank chevrons',art='chevrons',category='Marks'}
Weapons.Stickers.designs.barbed_wire={label='Barbed wire',art='barbed_wire',category='Marks'}
Weapons.Stickers.designs.cracked_star={label='Cracked star',art='cracked_star',category='Marks'}

Weapons.Stickers.designs.paint_patch={label='Paint patch',art='paint_patch',category='Paint'}
Weapons.Stickers.designs.paint_stripes={label='Paint stripes',art='paint_stripes',category='Paint'}
Weapons.Stickers.designs.paint_checker={label='Checker paint',art='paint_checker',category='Paint'}
Weapons.Stickers.designs.paint_camo={label='Camouflage paint',art='paint_camo',category='Paint'}

local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function receiver(x,y,z,width,height)
    return {
        receiver_left={label='Receiver - left',origin={x=-x,y=y,z=z},axisU={x=0,y=-1,z=0},axisV={x=0,y=0,z=1},halfWidth=width,halfHeight=height,depthOffset=.0004},
        receiver_right={label='Receiver - right',origin={x=x,y=y,z=z},axisU={x=0,y=1,z=0},axisV={x=0,y=0,z=1},halfWidth=width,halfHeight=height,depthOffset=.0004},
    }
end
Weapons.Stickers.surfaces={
    WEAPON_CARBINERIFLE=receiver(.018,.02,.05,.08,.035),
    WEAPON_ASSAULTRIFLE=receiver(.021,.01,.055,.09,.035),
    WEAPON_SPECIALCARBINE=receiver(.021,.015,.05,.075,.032),
    WEAPON_BULLPUPRIFLE=receiver(.024,-.055,.05,.07,.032),
    WEAPON_SMG=receiver(.021,-.015,.055,.055,.03),
    WEAPON_COMBATPDW=receiver(.022,-.015,.05,.065,.03),
    WEAPON_PUMPSHOTGUN=receiver(.022,-.02,.045,.06,.03),
    WEAPON_PISTOL=receiver(.018,-.015,.045,.045,.025),
    WEAPON_COMBATPISTOL=receiver(.018,-.01,.045,.045,.025),
}
-- Whole-weapon faces for every firearm: left/right side, top and bottom, built in game from the model's bounds and
-- measured against the real mesh. halfWidth/halfHeight are only the coordinate scale (metres per 1.0 of u/v) and
-- the outer limit the server accepts; the client keeps stickers inside the actual model.
-- The ids are the four sticker surfaces the inventory save accepts, so top uses stock_left and bottom magazine_left.
-- How stickers are drawn in the world. 'marker' (default): flat textured marker, unlit, tinted by the colour.
-- 'poly': world textured triangles (renders custom textures black here; kept as a fallback). Faction emblems
-- come from the shared atlas and always use the poly path.
-- markerPlane: 'xy' or 'xz', the marker axes the image lies on. /stickerdebug mode marker xy|xz tries it live.
Weapons.Stickers.draw='marker'
Weapons.Stickers.markerPlane='xy'
Weapons.Stickers.poly={native='basic',flip='off'}
Weapons.Stickers.autoSurfaces=true
local function wholeWeapon()
    local base={origin={x=0,y=0,z=0},halfWidth=.45,halfHeight=.2,depthOffset=0}
    local function face(label,auto,u,v)local f={label=label,auto=auto,axisU=u,axisV=v};for k,val in pairs(base)do f[k]=val end;return f end
    return {
        receiver_left=face('Left side','left',{x=0,y=-1,z=0},{x=0,y=0,z=1}),
        receiver_right=face('Right side','right',{x=0,y=1,z=0},{x=0,y=0,z=1}),
        stock_left=face('Top','top',{x=1,y=0,z=0},{x=0,y=1,z=0}),
        magazine_left=face('Bottom','bottom',{x=1,y=0,z=0},{x=0,y=-1,z=0}),
    }
end
if Weapons.Stickers.autoSurfaces then
    for weapon in pairs(Weapons.Magazines or {})do Weapons.Stickers.surfaces[weapon]=wholeWeapon()end
end
function Weapons.StickerSurfacesAuto(weapon)
    local list=Weapons.Stickers.surfaces[weapon]
    return list and list.receiver_left and list.receiver_left.auto~=nil or false
end
-- Per-weapon flush correction for the receiver planes above, metres along the surface normal (+ = out).
-- Calibrate in the workbench with /stickerdepth <mm>, then copy the printed line here.
Weapons.Stickers.depth=Weapons.Stickers.depth or {}
for weapon,list in pairs(Weapons.Stickers.surfaces)do for _,plane in pairs(list)do plane.weapon=weapon end end
function Weapons.ValidStickers(weapon,entries)
    local config=Weapons.Stickers
    if type(entries)~='table'or #entries>math.min(5,config.maxCount or 5)then return nil end
    local count=0
    for key in pairs(entries)do if type(key)~='number'or key%1~=0 or key<1 or key>#entries then return nil end;count=count+1 end
    if count~=#entries then return nil end
    if #entries==0 then return {}end
    local surfaces=config.surfaces[weapon]
    if not surfaces then return nil end
    local out={}
    for _,value in ipairs(entries)do
        if type(value)~='table'or type(value.design)~='string'or not config.designs[value.design]or type(value.surface)~='string'then return nil end
        local plane=surfaces[value.surface]
        if not plane or not finite(value.u)or not finite(value.v)or math.abs(value.u)>1 or math.abs(value.v)>1
            or not finite(value.size)or value.size<config.minSize or value.size>config.maxSize
            or not finite(value.rotation)or math.abs(value.rotation)>180 then return nil end
        local angle=math.rad(value.rotation)
        local extent=value.size*.5*(math.abs(math.cos(angle))+math.abs(math.sin(angle)))
        if math.abs(value.u*plane.halfWidth)+extent>plane.halfWidth+.000001 or math.abs(value.v*plane.halfHeight)+extent>plane.halfHeight+.000001 then return nil end
        local colour=value.colour or '#FFFFFF'
        local opacity=value.opacity==nil and 1 or value.opacity
        if type(colour)~='string'or not colour:match('^#%x%x%x%x%x%x$')or not finite(opacity)or opacity<.1 or opacity>1 then return nil end
        out[#out+1]={design=value.design,surface=value.surface,u=value.u,v=value.v,size=value.size,rotation=value.rotation,colour=colour:upper(),opacity=opacity}
    end
    return out
end

function Weapons.StickerCorners(plane, sticker)
    local corners = {}
    local angle, half = math.rad(sticker.rotation), sticker.size * 0.5
    local cos, sin = math.cos(angle), math.sin(angle)
    for i, p in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
        local u = sticker.u * plane.halfWidth + half * (p[1] * cos - p[2] * sin)
        local v = sticker.v * plane.halfHeight + half * (p[1] * sin + p[2] * cos)
        local corner = {}
        for _, axis in ipairs({ 'x', 'y', 'z' }) do
            local normal={x=plane.axisU.y*plane.axisV.z-plane.axisU.z*plane.axisV.y,y=plane.axisU.z*plane.axisV.x-plane.axisU.x*plane.axisV.z,z=plane.axisU.x*plane.axisV.y-plane.axisU.y*plane.axisV.x}
            corner[axis] = plane.origin[axis] + plane.axisU[axis] * u + plane.axisV[axis] * v + normal[axis]*(plane.depthOffset or .0015)
        end
        corners[i] = corner
    end
    return corners
end
