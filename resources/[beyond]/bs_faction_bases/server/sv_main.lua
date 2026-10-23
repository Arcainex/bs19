local Flags, Ready = {}, false
local S = FactionBases.Settings
local function q(sql, params) return exports.oxmysql:query_async(sql, params or {}) or {} end
local function one(sql, params) return q(sql, params)[1] end
local function x(sql, params) return exports.oxmysql:execute_async(sql, params or {}) end
local function faction(src) return exports.bs_factions:GetFactionSummary(tonumber(src)) end
-- FactionRank needs the faction id, otherwise nobody counts as owner.
local function rank(src) local f=faction(src);return f and exports.bs_factions:FactionRank(tonumber(src),f.factionId) end
local function admin(src) return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin') end
local function dead(src) local ped=GetPlayerPed(src);return not ped or ped==0 or GetEntityHealth(ped)<=0 end
local function point(src) local ped=GetPlayerPed(src);if not ped or ped==0 then return nil end;local c=GetEntityCoords(ped);return {x=c.x,y=c.y,z=c.z,h=GetEntityHeading(ped)} end
local function dist(a,b) local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z;return math.sqrt(dx*dx+dy*dy+dz*dz) end
local function isVanilla(id) local row=one('SELECT is_config FROM bs_faction_registry WHERE faction_id=? LIMIT 1',{id});return row and (row.is_config==true or tonumber(row.is_config)==1) end
-- Town safezones (and the traders inside them) plus padding. Faction flag zones are skipped, flags use the overlap rule.
local function safezoneBlocked(at)
 local ok,zones=pcall(function() return exports.bs_zombies:SafeZones() end);if not ok then return true end -- fail closed
 for _,zone in ipairs(zones or {}) do if not zone.flag and dist(at,{x=zone.x,y=zone.y,z=at.z}) < (tonumber(zone.radius) or 0)+S.safeZonePadding then return true end end
 return false
end
local function guardLog(src,kind,details,at)
 src=tonumber(src) or 0;local name=src>0 and GetPlayerName(src) or 'server'
 local lic=src>0 and GetPlayerIdentifierByType and GetPlayerIdentifierByType(tostring(src),'license') or nil
 exports.oxmysql:insert('INSERT INTO `bs_guard_log` (`src`,`license`,`char_id`,`name`,`kind`,`confidence`,`details`,`x`,`y`,`z`) VALUES (?,?,?,?,?,?,?,?,?,?)',
  {src,lic,nil,(name or '?'):sub(1,64),('fb_'..kind):sub(1,32),0,tostring(details or ''):sub(1,512),at and at.x or nil,at and at.y or nil,at and at.z or nil})
end
-- Old kinds: main = safezone, build = outpost (migration 034 rewrites them too).
local function normKind(k) if k=='main' then return 'safezone' end;if k=='build' or k==nil then return 'outpost' end;return k end
local function flagRows()
 local rows=q('SELECT f.*, r.label AS flabel FROM bs_faction_flags f LEFT JOIN bs_faction_registry r ON r.faction_id=f.faction_id WHERE f.status<>? ORDER BY f.id',{'removed'});local out={}
 for _,r in ipairs(rows) do out[#out+1]={id=tonumber(r.id),factionId=r.faction_id,kind=normKind(r.kind),x=tonumber(r.x),y=tonumber(r.y),z=tonumber(r.z),heading=tonumber(r.heading) or 0,radius=tonumber(r.radius),status=r.status,label=r.flabel,reclaimBy=r.reclaim_by,reclaimEnds=tonumber(r.reclaim_ends) or 0} end
 return out
end
-- Safezone flags are secret: only their own faction gets them.
local function visibleFor(src)
 local f=faction(src);local mine=f and f.factionId;local out={}
 for _,flag in ipairs(Flags) do
  if flag.kind~='safezone' or flag.factionId==mine then
   local c={};for k,v in pairs(flag) do c[k]=v end;c.mine=mine~=nil and flag.factionId==mine;out[#out+1]=c
  end
 end
 return out
end
local function sync(target)
 if target then TriggerClientEvent('bs:factionBases:sync',target,visibleFor(target)) return end
 for _,pid in ipairs(GetPlayers()) do pid=tonumber(pid);TriggerClientEvent('bs:factionBases:sync',pid,visibleFor(pid)) end
 TriggerEvent('bs:factionBases:changed',Flags) -- server side: bs_zombies keeps its zones in step
end
local function countFlags(id,kind) local n=0;for _,f in ipairs(Flags) do if f.factionId==id and (not kind or f.kind==kind) then n=n+1 end end;return n end
local function role(src) local r=rank(src);if r=='owner' then return 'leader' end;if r=='officer' then return 'officer' end;return 'member' end
local function allowed(src, permission)
 local f=faction(src);if not f or not f.factionId then return false end
 -- Rank permissions live in bs_factions (factions:perms:*). It answers nil for permissions it does not own (reclaim, manage), which fall through.
 local okRank,byRank=pcall(function() return exports.bs_factions:RankAllowed(tonumber(src),permission) end)
 if okRank and byRank~=nil then return byRank==true end
 local row=one('SELECT permissions_json FROM bs_faction_role_permissions WHERE faction_id=? AND role_id=? LIMIT 1',{f.factionId,role(src)})
 local data=row and json.decode(row.permissions_json or '{}') or FactionBases.DefaultRoles[role(src)] or {}
 return data[permission] == true
end
local function flagAt(src)
 local at=point(src);if not at then return nil end
 for _,f in ipairs(Flags) do if f.status=='active' and dist(at,f)<=f.radius then return f end end
 return nil
end
-- Sanctions: legacy bs_faction_sanctions rows (effect_id = old effect name or template id) plus faction-wide rows of the new store (sv_sanctions.lua).
local LegacyTemplateIds={xp={'xp_5'},drops={'drops_5'},build={'build_lock'},bank={'bank_lock'},leave={'leave_lock'}}
local function activeSanction(factionId,effect)
 if not factionId then return false end
 local canonical=FactionBases.SanctionAliases[effect] or effect
 if BSSanctions and BSSanctions.FactionEffect(factionId,canonical) then return true end
 local ids={effect,canonical}
 for old,new in pairs(FactionBases.SanctionAliases) do if new==canonical then ids[#ids+1]=old;for _,t in ipairs(LegacyTemplateIds[old] or {}) do ids[#ids+1]=t end end end
 local marks={};for i=1,#ids do marks[i]='?' end
 local params={factionId};for _,v in ipairs(ids) do params[#params+1]=v end;params[#params+1]=os.time()
 return one('SELECT id FROM bs_faction_sanctions WHERE faction_id=? AND effect_id IN ('..table.concat(marks,',')..') AND ends_at>? LIMIT 1',params)~=nil
end
-- Caps. Player factions: 1 safezone + maxOutposts (+ faction level bonus). Vanilla: 1 outpost, no safezone (they have towns).
local function capFor(id,kind,maxOutposts)
 if isVanilla(id) then return kind=='outpost' and S.vanillaOutposts or 0 end
 if kind=='safezone' then return S.maxSafezones end
 local okBonus,bonus=pcall(function() return exports.bs_factions:FactionFlagBonus(id) end)
 return (tonumber(maxOutposts) or S.maxOutposts)+(okBonus and tonumber(bonus) or 0)
end
local function notify(src,msg,kind) TriggerClientEvent('bs:ui:notify',src,{type=kind or 'info',message=msg,duration=5000}) end
local function itemFor(kind) return kind=='safezone' and S.safezoneFlagItem or S.flagItem end

BSB.RegisterCallback('factionBases:status',function(src)
 local f=faction(src);local at=flagAt(src)
 if at and at.kind=='safezone' and (not f or f.factionId~=at.factionId) then at=nil end -- never reveal a hidden safezone
 return {ok=Ready,flags=visibleFor(src),nearby=at,role=f and role(src) or nil,canBuild=allowed(src,'build'),canDeposit=allowed(src,'deposit'),canWithdraw=allowed(src,'withdraw')}
end)
-- Flags are planted through the F2 build wheel (bs_building -> PlaceFlagAt).
BSB.RegisterCallback('factionBases:placeFlag',function(src) return {ok=false,error=Lp(src,'fb.use_wheel')} end)
-- bs_building places both flag kinds through this. kind = 'safezone' | 'outpost'.
exports('PlaceFlagAt',function(src,fx,fy,fz,heading,buildRadius,kind,opts)
 src=tonumber(src);if not Ready then return {ok=false,error=Lp(src, 'fb.starting')} end
 if dead(src) then return {ok=false,error=Lp(src, 'fb.dead_place')} end
 local f=faction(src);if not f or not f.factionId then return {ok=false,error=Lp(src, 'fb.join_first')} end
 if rank(src)~='owner' then return {ok=false,error=Lp(src, 'fb.leader_flags')} end
 kind=kind=='safezone' and 'safezone' or 'outpost';opts=type(opts)=='table' and opts or {}
 local at={x=tonumber(fx),y=tonumber(fy),z=tonumber(fz),h=tonumber(heading) or 0.0};local me=point(src)
 if not at.x or not me or dist(me,at)>10.0 then return {ok=false,error=Lp(src, 'fb.too_far')} end
 if safezoneBlocked(at) then return {ok=false,error=Lp(src, 'fb.safezone_km')} end
 local radius=tonumber(buildRadius) or 50.0
 -- Radii may not overlap: centres at least the sum of both radii apart.
 for _,flag in ipairs(Flags) do if flag.status~='removed' and dist({x=at.x,y=at.y,z=0},{x=flag.x,y=flag.y,z=0})<(flag.radius or radius)+radius then return {ok=false,error=Lp(src, 'fb.too_close')} end end
 local vanilla=isVanilla(f.factionId)
 if vanilla and kind=='safezone' then return {ok=false,error=Lp(src, 'fb.main_safezones')} end
 if countFlags(f.factionId,kind)>=capFor(f.factionId,kind,opts.maxOutposts) then return {ok=false,error=Lp(src, kind=='safezone' and 'fb.has_main' or 'fb.flag_limit')} end
 local item=itemFor(kind)
 if not opts.free then
  if exports.bs_inventory:CountItem(src,item)<1 or not exports.bs_inventory:RemoveItem(src,item,1) then return {ok=false,error=Lp(src, 'fb.need_kit')} end
 end
 x('INSERT INTO bs_faction_flags(faction_id,kind,x,y,z,heading,radius,created_by,status) VALUES(?,?,?,?,?,?,?,?,?)',{f.factionId,kind,at.x,at.y,at.z,at.h,radius,tonumber(exports.bs_core:GetPlayerSummary(src).charId),'active'})
 guardLog(src,'flag_place',('%s flag for %s r=%.0f'):format(kind,f.factionId,radius),at)
 Flags=flagRows();sync();return {ok=true,flag=true,kind=kind}
end)
exports('IsVanilla',function(id) return isVanilla(id)==true end)
-- Leader picks the flag up: the kit comes back, the claim ends and bs_building starts decaying the pieces it covered.
local function pickUp(src,id)
 local flag;for _,v in ipairs(Flags) do if v.id==tonumber(id) then flag=v break end end -- by DB id only
 local f=faction(src);if not flag or not f or f.factionId~=flag.factionId or rank(src)~='owner' then return {ok=false,error=Lp(src, 'fb.leader_remove')} end
 if flag.status~='active' then return {ok=false,error=Lp(src, 'fb.flag_unavail')} end
 local at=point(src);if not at or dist(at,flag)>6.0 then return {ok=false,error=Lp(src, 'fb.too_far')} end
 x('UPDATE bs_faction_flags SET status=? WHERE id=?',{'removed',flag.id})
 pcall(function() exports.bs_inventory:GiveItem(src,itemFor(flag.kind),1) end)
 guardLog(src,'flag_pickup',('%s flag #%d of %s'):format(flag.kind,flag.id,flag.factionId),flag)
 Flags=flagRows();sync();return {ok=true}
end
BSB.RegisterCallback('factionBases:removeFlag',function(src,id) return pickUp(src,id) end)
BSB.RegisterCallback('factionBases:pickupFlag',function(src,id) return pickUp(src,id) end)
-- Is a raid on this faction allowed for the attacker right now? Window + declared raid, owned by bs_building.
local function raidAllowed(attackerId,targetId)
 local ok,r=pcall(function() return exports.bs_building:RaidAllowed(attackerId,targetId) end)
 return ok and r==true
end
-- Only outposts can be reclaimed, and only during a declared raid in the raid window.
BSB.RegisterCallback('factionBases:reclaim',function(src,id)
 local flag=nil;for _,v in ipairs(Flags) do if v.id==tonumber(id) then flag=v break end end
 local attacker=faction(src);if not flag or flag.status~='active' or flag.kind~='outpost' then return {ok=false,error=Lp(src, 'fb.flag_unavail')} end
 if dead(src) then return {ok=false,error=Lp(src, 'fb.dead_reclaim')} end
 local at=point(src);if not at or dist(at,flag)>flag.radius then return {ok=false,error=Lp(src, 'fb.stand_radius')} end
 if not attacker or attacker.factionId==flag.factionId or not allowed(src,'reclaim') then return {ok=false,error=Lp(src, 'fb.cant_reclaim')} end
 if not raidAllowed(attacker.factionId,flag.factionId) then return {ok=false,error=Lp(src, 'fb.no_raid')} end
 if countFlags(attacker.factionId,'outpost')>=capFor(attacker.factionId,'outpost') then return {ok=false,error=Lp(src, 'fb.flag_limit')} end
 local defenders=0;for _,pid in ipairs(GetPlayers()) do local other=faction(tonumber(pid));if other and other.factionId==flag.factionId then defenders=defenders+1;notify(tonumber(pid),Lp(tonumber(pid),'fb.under_reclaim'),'warn') end end
 if defenders==0 then return {ok=false,error=Lp(src, 'fb.offline')} end
 local ends=os.time()+S.reclaimSeconds;x('UPDATE bs_faction_flags SET status=?,reclaim_by=?,reclaim_ends=? WHERE id=?',{'reclaiming',attacker.factionId,ends,flag.id})
 guardLog(src,'flag_reclaim',('outpost #%d of %s by %s'):format(flag.id,flag.factionId,attacker.factionId),flag)
 Flags=flagRows();sync();return {ok=true,ends=ends}
end)
local function playerLocked(src,effect) if not BSSanctions then return false end;local cid=BSSanctions.CharOf(src);return cid~=nil and BSSanctions.PlayerEffect(cid,effect)~=nil end
exports('CanBuild',function(src) local f=faction(src);return not dead(src) and allowed(src,'build') and not activeSanction(f and f.factionId,'build') and not playerLocked(src,'build_lock') and flagAt(src)~=nil end)
exports('FactionSanctioned',function(factionId,effect) return activeSanction(factionId,tostring(effect or '')) end)
exports('FactionAllowed',function(src,permission) return allowed(tonumber(src),tostring(permission or '')) end)
-- Disband cleanup: flags removed, role perms and sanctions dropped, resync.
exports('ClearFaction',function(factionId)
 if not factionId then return false end
 x('UPDATE bs_faction_flags SET status=?,reclaim_by=NULL,reclaim_ends=0 WHERE faction_id=?',{'removed',factionId})
 x('UPDATE bs_faction_flags SET status=?,reclaim_by=NULL,reclaim_ends=0 WHERE reclaim_by=?',{'active',factionId})
 x('DELETE FROM bs_faction_role_permissions WHERE faction_id=?',{factionId})
 x('DELETE FROM bs_faction_sanctions WHERE faction_id=?',{factionId})
 if Ready then Flags=flagRows();sync() end;return true
end)
-- Reclaim resolves at the timer: fails if the attacker hit its flag cap, or if a living defender holds the radius while no living attacker is inside.
local function reclaimHolds(flag)
 if countFlags(flag.reclaimBy,'outpost')>=capFor(flag.reclaimBy,'outpost') then return false end
 local defenders,attackers=0,0
 for _,pid in ipairs(GetPlayers()) do
  local id=tonumber(pid);local f=faction(id)
  if f and (f.factionId==flag.factionId or f.factionId==flag.reclaimBy) and not dead(id) then
   local at=point(id)
   if at and dist(at,flag)<=flag.radius then if f.factionId==flag.factionId then defenders=defenders+1 else attackers=attackers+1 end end
  end
 end
 return not (defenders>0 and attackers==0)
end
exports('FlagAt',function(src) return flagAt(src) end)
-- Admin tooling (bs_factions sv_admin.lua). Callers check the ACE themselves.
exports('ListFlags',function(factionId) local out={};for _,f in ipairs(Flags) do if not factionId or f.factionId==factionId then out[#out+1]=f end end;return out end)
exports('AdminRemoveFlag',function(id)
 id=tonumber(id);local found;for _,f in ipairs(Flags) do if f.id==id then found=f break end end
 if not found then return false end
 x('UPDATE bs_faction_flags SET status=?,reclaim_by=NULL,reclaim_ends=0 WHERE id=?',{'removed',id});Flags=flagRows();sync();return true
end)
CreateThread(function()
 while GetResourceState('oxmysql')~='started' do Wait(250) end
 x('CREATE TABLE IF NOT EXISTS bs_faction_flags (id INT UNSIGNED NOT NULL AUTO_INCREMENT,faction_id VARCHAR(32) NOT NULL,kind VARCHAR(16) NOT NULL,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,heading FLOAT NOT NULL DEFAULT 0,radius FLOAT NOT NULL,created_by INT UNSIGNED NULL,status VARCHAR(16) NOT NULL DEFAULT \'active\',reclaim_by VARCHAR(32) NULL,reclaim_ends BIGINT NOT NULL DEFAULT 0,created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(id),KEY faction_id (faction_id))')
 x('CREATE TABLE IF NOT EXISTS bs_faction_role_permissions (faction_id VARCHAR(32) NOT NULL,role_id VARCHAR(24) NOT NULL,permissions_json TEXT NOT NULL,PRIMARY KEY(faction_id,role_id))')
 x('CREATE TABLE IF NOT EXISTS bs_faction_flag_storage (flag_id INT UNSIGNED NOT NULL,storage_type VARCHAR(16) NOT NULL,permissions_json TEXT NOT NULL,PRIMARY KEY(flag_id,storage_type))')
 x('CREATE TABLE IF NOT EXISTS bs_faction_sanctions (id INT UNSIGNED NOT NULL AUTO_INCREMENT,faction_id VARCHAR(32) NOT NULL,effect_id VARCHAR(32) NOT NULL,value INT NOT NULL DEFAULT 0,reason VARCHAR(255) NULL,ends_at BIGINT NOT NULL,created_by INT UNSIGNED NULL,PRIMARY KEY(id),KEY faction_id (faction_id))')
 Wait(500);Flags=flagRows();Ready=true;sync();print('^2[BeyondSurvival]^7 faction bases ready')
end)
CreateThread(function() while true do Wait(1000);if Ready then local now=os.time();local changed=false;for _,flag in ipairs(Flags) do if flag.status=='reclaiming' and flag.reclaimEnds<=now then if reclaimHolds(flag) then x('UPDATE bs_faction_flags SET faction_id=?,kind=?,status=?,reclaim_by=NULL,reclaim_ends=0 WHERE id=?',{flag.reclaimBy,'outpost','active',flag.id}) else x('UPDATE bs_faction_flags SET status=?,reclaim_by=NULL,reclaim_ends=0 WHERE id=?',{'active',flag.id}) end;changed=true end end;if changed then Flags=flagRows();sync() end end end end)