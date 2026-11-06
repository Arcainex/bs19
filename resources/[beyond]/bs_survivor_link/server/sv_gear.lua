-- Companion weapon and ammunition. He draws the best weapon he carries and every round comes from his own bag.
LinkGear={}
local MODES={conserve=true,normal=true,free=true}
LinkGear.Modes=MODES

local function ammoInfo(weapon)
    local item=exports.bs_inventory:AmmoItemFor(weapon)
    if not item then return nil,1 end
    local blurb=exports.bs_inventory:ItemBlurb(item)
    return item,math.max(1,math.floor(tonumber(blurb and blurb.rounds)or 1))
end
local function savedRounds(charId,weapon)
    return math.max(0,math.floor(MySQL.scalar.await('SELECT ammo FROM bs_character_weapons WHERE character_id=? AND weapon=?',{charId,weapon})or 0))
end

-- Loaded rounds plus every box he carries for that gun.
function LinkGear.Pool(w)
    if not w then return 0 end
    if not w.ammoItem then return 0 end
    return w.ammo+w.boxes*w.per
end
function LinkGear.Payload(rec)
    local w=rec.weapon
    if not w then return nil end
    return {weapon=w.weapon,item=w.item,ammo=LinkGear.Pool(w),melee=w.ammoItem==nil,rev=w.rev,mode=rec.ammoMode or 'normal'}
end
function LinkGear.Save(rec)
    local w=rec.weapon
    if not w or not w.ammoItem then return end
    MySQL.update.await([[INSERT INTO bs_character_weapons (character_id,weapon,attachments,ammo) VALUES (?,?,'{}',?)
        ON DUPLICATE KEY UPDATE ammo=VALUES(ammo)]],{rec.char.id,w.weapon,math.max(0,math.floor(w.ammo))})
end

-- Pick a weapon: a gun with rounds, then a melee weapon, then an empty gun. Item value breaks ties.
function LinkGear.Arm(rec)
    local bag=exports.bs_inventory:LinkBag(rec.char.id)or {}
    local counts={}
    for _,e in ipairs(bag)do counts[e.item]=(counts[e.item]or 0)+e.amount end
    local old=rec.weapon
    local best,bestScore
    for _,e in ipairs(bag)do
        if e.weapon and e.category=='weapon'and not e.throwable then
            local item,per=ammoInfo(e.weapon)
            local loaded=0
            if item then loaded=(old and old.weapon==e.weapon)and old.ammo or savedRounds(rec.char.id,e.weapon)end
            local boxes=item and(counts[item]or 0)or 0
            local rounds=loaded+boxes*per
            local score=(item and(rounds>0 and 20000 or 0)or 10000)+(tonumber(e.value)or 0)
            if not bestScore or score>bestScore then
                bestScore=score
                best={weapon=e.weapon,item=e.item,serial=e.metadata and e.metadata.serial,ammo=loaded,ammoItem=item,per=per,boxes=boxes}
            end
        end
    end
    if old and(not best or best.weapon~=old.weapon)then LinkGear.Save(rec)end
    if best then best.rev=((old and old.rev)or 0)+1 end
    rec.weapon=best
    return best
end

-- The client reports what is left in the ped; the difference is taken from loaded rounds, then whole boxes.
function LinkGear.Spend(rec,reported,rev)
    local w=rec.weapon
    reported=tonumber(reported)
    if not w or not w.ammoItem or not reported or reported~=reported or tonumber(rev)~=w.rev then return false end
    reported=math.floor(reported)
    local spent=LinkGear.Pool(w)-reported
    if spent<=0 then return false end
    if spent<=w.ammo then w.ammo=w.ammo-spent;return true end
    local need=spent-w.ammo
    local boxes=math.min(w.boxes,math.ceil(need/w.per))
    local taken=boxes>0 and exports.bs_inventory:LinkTake(rec.char.id,w.ammoItem,boxes)or 0
    w.boxes=w.boxes-taken
    w.ammo=math.max(0,taken*w.per-need)
    return true
end
