Weapons.Cosmetics = {
    enabled=false,
    maxMounts=10,
    minScale=0.5,
    maxScale=1.5,
    maxOffset=0.75,
    drawDistance=18.0,
    maxVisiblePlayers=6,
    weapons={WEAPON_CARBINERIFLE=true,WEAPON_ASSAULTRIFLE=true,WEAPON_PUMPSHOTGUN=true,
        WEAPON_SMG=true,WEAPON_COMBATPDW=true,WEAPON_SPECIALCARBINE=true,WEAPON_BULLPUPRIFLE=true},
    -- Catalogue models are real GTA objects; runtime availability is checked before they are rendered.
    parts={
        knife={label='Hunting knife',item='hunting_knife',weaponModel='WEAPON_KNIFE',
            position={x=0,y=.25,z=0},rotation={x=0,y=0,z=0}},
        flashlight={label='Flashlight',item='flashlight',weaponModel='WEAPON_FLASHLIGHT',
            position={x=.03,y=.18,z=-.03},rotation={x=0,y=0,z=0}},
        hammer={label='Hammer',item='hammer',weaponModel='WEAPON_HAMMER',
            position={x=.04,y=.15,z=-.04},rotation={x=0,y=0,z=0}},
        crowbar={label='Crowbar',item='crowbar',weaponModel='WEAPON_CROWBAR',
            position={x=.04,y=.18,z=-.04},rotation={x=0,y=0,z=0}},
        machete={label='Machete',item='machete',weaponModel='WEAPON_MACHETE',
            position={x=.04,y=.2,z=-.04},rotation={x=0,y=0,z=0}},
        tape={label='Duct tape strip',item='duct_tape',model='prop_gaffer_tape_strip',baseScale=.45,
            position={x=-.02,y=0,z=.03},rotation={x=0,y=90,z=0}},
        wrap={label='Cloth wrap',item='rag',model='prop_rag_01',baseScale=.25,
            position={x=-.02,y=0,z=.03},rotation={x=0,y=90,z=0}},
        wire={label='Cable tie',item='electrical_wire',model='prop_ld_cable_tie_01',baseScale=.5,
            position={x=0,y=.1,z=.02},rotation={x=90,y=0,z=0}},
        scrap={label='Scrap plate',item='scrap_metal',model='prop_ld_scrap',baseScale=.12,
            position={x=-.025,y=.05,z=.01},rotation={x=0,y=90,z=0}},
        spike={label='Metal spike',item='scrap_metal',model='prop_mp_spike_01',baseScale=.12,
            position={x=.025,y=.25,z=.01},rotation={x=0,y=0,z=0}},
    },
}

local function finite(value)return type(value)=='number'and value==value and math.abs(value)<math.huge end
function Weapons.CosmeticLimits()
    local c=Weapons.Cosmetics
    local minimum=math.max(.5,math.min(1.5,tonumber(c.minScale)or .5))
    local maximum=math.max(minimum,math.min(1.5,tonumber(c.maxScale)or 1.5))
    return {maxMounts=math.max(1,math.min(12,math.floor(tonumber(c.maxMounts)or 10))),
        minScale=minimum,maxScale=maximum,maxOffset=math.max(.05,math.min(.75,tonumber(c.maxOffset)or .75))}
end
function Weapons.ValidCosmeticTransform(value)
    if type(value)~='table'or type(value.position)~='table'or type(value.rotation)~='table'then return nil end
    local limits=Weapons.CosmeticLimits()
    local scale=value.scale==nil and 1 or value.scale
    if not finite(scale)or scale<limits.minScale or scale>limits.maxScale then return nil end
    local out={position={},rotation={},scale=scale}
    for _,axis in ipairs({'x','y','z'})do
        local p,r=value.position[axis],value.rotation[axis]
        if not finite(p)or math.abs(p)>limits.maxOffset or not finite(r)or math.abs(r)>180 then return nil end
        out.position[axis],out.rotation[axis]=p,r
    end
    return out
end
-- Legacy ownership stays intact until the next successful inventory transaction migrates it.
function Weapons.CosmeticMounts(meta)
    if type(meta)~='table'then return {}end
    if type(meta.cosmeticMounts)=='table'then return meta.cosmeticMounts end
    local mount=meta.cosmeticMount
    if type(mount)~='table'or type(mount.id)~='string'then return {}end
    return {{key='legacy:'..mount.id,id=mount.id,position=mount.position,rotation=mount.rotation,scale=mount.scale or 1}}
end
function Weapons.ValidCosmeticMounts(values,maximum)
    if type(values)~='table'or #values>math.min(12,maximum or Weapons.CosmeticLimits().maxMounts)then return nil end
    local out,seen={},{}
    for k in pairs(values)do if type(k)~='number'or k%1~=0 or k<1 or k>#values then return nil end end
    for _,mount in ipairs(values)do
        if type(mount)~='table'or not Weapons.Cosmetics.parts[mount.id]then return nil end
        local transform=Weapons.ValidCosmeticTransform(mount)
        if not transform then return nil end
        local key=mount.key or mount.mountKey
        if key~=nil and (type(key)~='string'or #key>96 or key:find('[^%w_:%-]')or seen[key])then return nil end
        if key then seen[key]=true end
        transform.id,transform.key=mount.id,key
        out[#out+1]=transform
    end
    return out
end
