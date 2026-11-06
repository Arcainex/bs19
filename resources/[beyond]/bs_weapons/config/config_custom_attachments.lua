-- Original models; native components provide supported functionality.
Weapons.CustomAttachments={}
for _,p in ipairs(CustomAttachmentCatalogue or {})do
    local base=p.base and Weapons.Attachments[p.base]
    Weapons.CustomAttachments[p.id]=p
    Weapons.Cosmetics.parts[p.id]={label=p.label..(base and ' · functional fit in O' or ' · cosmetic'),item=p.item,model=p.model,mountBone=p.bone,
        position={x=0,y=.12,z=0},rotation={x=0,y=0,z=90}}
    if base then
        if Weapons.Effects and Weapons.Effects[p.base]then Weapons.Effects[p.id]=Weapons.Effects[p.base]end
        Weapons.Attachments[p.id]={slot=base.slot,item=p.item,label=p.label,icon=base.icon,components=base.components,
            blurb='Uses a supported native component. Original outer model; mounting may need per-weapon calibration.'}
    end
end
for weapon in pairs(Weapons.Magazines or {})do Weapons.Cosmetics.weapons[weapon]=true end
function Weapons.CustomFunctionalMounts(meta)
    local out={}
    for _,slot in ipairs(Weapons.Slots)do
        local id=meta and meta.attachments and meta.attachments[slot.id]
        local part=id and Weapons.CustomAttachments[id]
        if part and part.base and Weapons.Attachments[id]then
            out[#out+1]={id=id,key='native:'..slot.id,functional=true,position={x=0,y=0,z=0},rotation={x=0,y=0,z=90},scale=1}
        end
    end
    return out
end
