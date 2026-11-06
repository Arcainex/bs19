local locks={}
local function caller()return GetInvokingResource()=='bs_survivor_link'end
local function row(src,id)
    local session=BS.GetSession(src)
    if not session then return end
    return BS.Characters.Get(tonumber(id),session.id)
end
exports('LinkCharacter',function(src,id)
    if not caller()then return end
    local c=row(src,id);if not c then return end
    c.appearance=BS.Util.Decode(c.appearance,{})
    c.metadata=BS.Util.Decode(c.metadata,{})
    local class,classId=Config.GetClass(c.class)
    c.inventoryStats={name=c.first_name..' '..c.last_name,classId=classId,className=class and class.label,
        level=c.level,xp=c.xp,xpToNext=Config.Progression.xpCurve(c.level or 1),
        needs={hunger=c.hunger or 100,thirst=c.thirst or 100,infection=c.infection or 0}}
    c.inventoryCarry=class and class.stats and class.stats.carryWeight or 40
    return c
end)
exports('LinkRoster',function(src)
    if not caller()then return {}end
    local u=BS.GetSession(src);return u and BS.Characters.List(u.id) or {}
end)
exports('LinkSave',function(src,id,life,position)
    if not caller() or BS.GetPlayerByCharId(tonumber(id)) then return false end
    local c=row(src,id);if not c then return false end
    local meta=BS.Util.Decode(c.metadata,{})
    meta.survivorLink=life
    if life.recallVersion==2 then meta.survivorLinkRecallAt=life.availableAt or 0
    elseif life.availableAt then meta.survivorLinkRecallAt=math.max(meta.survivorLinkRecallAt or 0,life.availableAt)end
    BS.DB.Update('UPDATE bs_characters SET metadata=?,pos_x=?,pos_y=?,pos_z=?,heading=? WHERE id=?',
        {BS.Util.Encode(meta),position.x,position.y,position.z,position.h or 0,c.id})
    return true
end)
exports('LinkSwitch',function(src,id,position,life)
    if not caller() or locks[src]then return {ok=false,error='A character change is already underway.'}end
    locks[src]=true
    local rollbackId,rollbackPosition
    local ok,result=pcall(function()
        local old=BS.GetPlayer(src);local target=row(src,id)
        if not old or not target or old.charId==target.id or BS.GetPlayerByCharId(target.id)then return {ok=false,error='Character unavailable.'}end
        old:SetMeta('survivorLink',life)
        local p=GetEntityCoords(GetPlayerPed(src));old:SetPosition(p.x,p.y,p.z,GetEntityHeading(GetPlayerPed(src)))
        if not old:Save(true)then return {ok=false,error='Could not save the current survivor.'}end
        rollbackId,rollbackPosition=old.charId,old.position
        local oldId=old.charId
        BS.UnloadPlayer(src,'survivor_link')
        TriggerClientEvent(BS.Events.PlayerUnloaded,src,'survivor_link')
        local loaded,err=BS.Characters.Select(src,target.id,{position=position,survivorLink=true})
        if not loaded then
            BS.Characters.Select(src,oldId,{position=old.position,survivorLink=true})
            return {ok=false,error=err or 'Could not switch; original survivor restored.'}
        end
        return {ok=true,oldId=oldId}
    end)
    locks[src]=nil
    if not ok then
        print('[bs_core] survivor link switch failed: '..tostring(result))
        if rollbackId and not BS.GetPlayer(src)then
            local restored=pcall(BS.Characters.Select,src,rollbackId,{position=rollbackPosition,survivorLink=true})
            if not restored then print('[bs_core] survivor link rollback needs character selection recovery')end
        end
        return {ok=false,error='Character change failed.'}
    end
    return result
end)

exports('LinkRecover',function(src,id,rules)
    if not caller() or BS.GetPlayerByCharId(tonumber(id))then return false end
    local c=row(src,id);if not c then return false end
    local meta=BS.Util.Decode(c.metadata,{})
    local life=meta.survivorLink
    if not life or life.status~='dead'or os.time()<math.max(life.availableAt or 0,meta.survivorLinkRecallAt or 0)then return false end
    meta.survivorLink={status='alive',health=200,armour=0,lastNeedsAt=os.time()}
    meta.lastWeapon=nil
    local queries={{query='UPDATE bs_characters SET metadata=?,hunger=?,thirst=? WHERE id=?',values={BS.Util.Encode(meta),rules.hunger,rules.thirst,c.id}},
        {query='DELETE FROM bs_character_medical WHERE character_id=?',values={c.id}},
        {query='INSERT INTO bs_character_stats (character_id,deaths) VALUES (?,1) ON DUPLICATE KEY UPDATE deaths=deaths+1',values={c.id}}}
    if rules.wipe then
        queries[#queries+1]={query="DELETE i FROM bs_inventory_items i JOIN bs_inventories v ON v.id=i.inventory_id WHERE v.owner_type='character'AND v.owner_id=?",values={tostring(c.id)}}
        queries[#queries+1]={query='UPDATE bs_character_weapons SET ammo=0 WHERE character_id=?',values={c.id}}
    end
    return exports.oxmysql:transaction_async(queries)==true
end)
