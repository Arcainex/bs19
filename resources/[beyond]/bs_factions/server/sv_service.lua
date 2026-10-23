local Registry, State, Invites, BankBalances, Ready = {}, {}, {}, {}, false
-- Defined with the rank system further down; sync, members and directory need them first.
local function q(sql,p) return exports.oxmysql:query_async(sql,p or {}) or {} end
local function one(sql,p) return q(sql,p)[1] end
local function x(sql,p) return exports.oxmysql:execute_async(sql,p or {}) end
-- Cross-resource player exports are data snapshots; their Lua methods do not travel. Keep the snapshot for identity only and use the bs_core money exports for cash.
local function p(src) return exports.bs_core:GetPlayer(tonumber(src)) end
local function playerSummary(src) return exports.bs_core:GetPlayerSummary(tonumber(src)) end
local ranksOf, rankIdx, rankLabel, rankHas
local function sync(src)
 local s=State[src]; if not s then return end; local f=s.id and Registry[s.id]
 local label=s.id and rankLabel(s.id,s.rank) or nil
 Player(src).state:set('bsFactionTag', f and { tag=f.short, name=f.label, rank=s.rank, rankLabel=label } or nil, true)
 TriggerClientEvent('bs:factions:sync',src,{factionId=s.id,label=f and f.label,short=f and f.short,rank=s.rank,rankLabel=label,canInvite=s.id and rankHas(s.id,s.rank,'invite') or false,reputation=s.rep or 0,unlocks={}})
end
local function load(src)
 local pl=p(src); if not pl or not pl.charId then return nil end; local cid=tonumber(pl.charId); local m=one('SELECT faction_id, rank FROM bs_faction_members WHERE character_id=? LIMIT 1',{cid}); local rep=0
 if m then local v=one('SELECT reputation FROM bs_faction_reputation WHERE character_id=? AND faction_id=? LIMIT 1',{cid,m.faction_id}); rep=v and tonumber(v.reputation) or 0 end
 State[tonumber(src)]={cid=cid,id=m and m.faction_id,rank=m and m.rank,rep=rep}; sync(tonumber(src)); return State[tonumber(src)]
end
local function state(src) return State[tonumber(src)] or load(src) end
local function save(s) if s and s.id then x('INSERT INTO bs_faction_reputation(character_id,faction_id,reputation) VALUES(?,?,?) ON DUPLICATE KEY UPDATE reputation=VALUES(reputation)',{s.cid,s.id,s.rep or 0}) end end
local function members(id)
 local rows=q('SELECT m.character_id,m.rank,c.first_name,c.last_name FROM bs_faction_members m JOIN bs_characters c ON c.id=m.character_id WHERE m.faction_id=? ORDER BY FIELD(m.rank,\'owner\',\'officer\',\'member\'),c.first_name',{id}); local online={}; for _,v in ipairs(GetPlayers()) do local s=State[tonumber(v)];if s then online[s.cid]=tonumber(v) end end; local out={}
 for _,v in ipairs(rows) do out[#out+1]={charId=tonumber(v.character_id),rank=v.rank,rankLabel=rankLabel(id,v.rank),src=online[tonumber(v.character_id)],name=((v.first_name or '?')..' '..(v.last_name or '')):gsub('%s+$','')} end
 table.sort(out,function(a,b) local i,j=rankIdx(id,a.rank),rankIdx(id,b.rank); if i~=j then return i<j end; return a.name<b.name end); return out
end
local function treasury(id)
    -- The database write is async here. Mirror the balance so a deposit shows in the panel right after the callback.
    if BankBalances[id] == nil then
        local row=one('SELECT balance FROM bs_faction_banks WHERE faction_id=? LIMIT 1',{id})
        BankBalances[id]=row and tonumber(row.balance) or 0
    end
    local history=q('SELECT direction,amount,note,created_at FROM bs_faction_bank_log WHERE faction_id=? ORDER BY id DESC LIMIT 8',{id})
    return { balance=BankBalances[id], history=history }
end
local function isAdmin(src)
 return IsPlayerAceAllowed(src, 'bs.admin') or IsPlayerAceAllowed(src, 'bs.superadmin')
end

-- Faction score only uses the player facts shown by the scoreboard. Empty factions are not ranked or listed publicly.
local function directory()
 local rows=q([[SELECT m.faction_id,m.character_id,m.rank,c.first_name,c.last_name,c.level,c.xp,
  COALESCE(s.zombie_kills,0) AS zombie_kills,COALESCE(s.player_kills,0) AS player_kills
  FROM bs_faction_members m JOIN bs_characters c ON c.id=m.character_id
  LEFT JOIN bs_character_stats s ON s.character_id=c.id
  WHERE c.deleted_at IS NULL
  ORDER BY m.faction_id,FIELD(m.rank,'owner','officer','member'),c.first_name]])
 local online,byId={},{}
 for _,id in ipairs(GetPlayers()) do local state=State[tonumber(id)];if state then online[state.cid]=tonumber(id) end end
 for _,v in ipairs(rows) do
  local faction=Registry[v.faction_id]
  if faction then
   local d=byId[v.faction_id] or {id=faction.id,label=faction.label,short=faction.short,description=faction.description or '',logo=faction.logo,members=0,reputation=0,zombieKills=0,survivorKills=0,xp=0,memberList={}}
   byId[v.faction_id]=d
   local zombies=math.max(0,tonumber(v.zombie_kills) or 0);local survivors=math.max(0,tonumber(v.player_kills) or 0);local xp=math.max(0,tonumber(v.xp) or 0);local level=math.max(1,tonumber(v.level) or 1)
   local score=zombies+(survivors*10)+math.floor(xp/100)+level
   d.members=d.members+1;d.zombieKills=d.zombieKills+zombies;d.survivorKills=d.survivorKills+survivors;d.xp=d.xp+xp;d.reputation=d.reputation+score
   d.memberList[#d.memberList+1]={charId=tonumber(v.character_id),rank=v.rank,rankLabel=rankLabel(v.faction_id,v.rank),name=((v.first_name or '?')..' '..(v.last_name or '')):gsub('%s+$',''),level=level,zombieKills=zombies,survivorKills=survivors,xp=xp,score=score,src=online[tonumber(v.character_id)]}
  end
 end
 local out={}
 -- Vanilla factions are always listed, even with nobody in them.
 for _,fid in ipairs(Factions.Order or {}) do local f=Registry[fid]; if f and f.config and not byId[fid] then byId[fid]={id=f.id,label=f.label,short=f.short,description=f.description or '',logo=f.logo,members=0,reputation=0,zombieKills=0,survivorKills=0,xp=0,memberList={}} end end
 for _,d in pairs(byId) do
  if d.members>0 or (Registry[d.id] and Registry[d.id].config) then
   table.sort(d.memberList,function(a,b) local i,j=rankIdx(d.id,a.rank),rankIdx(d.id,b.rank); if i~=j then return i<j end; return a.score>b.score end)
   out[#out+1]=d
  end
 end
 table.sort(out,function(a,b) if a.reputation==b.reputation then return a.members>b.members end return a.reputation>b.reputation end)
 return out
end

local function adminDirectory(public)
 -- Never mutate the public ranking (score-sorted, empty factions excluded). Admin management gets its own copy plus empty vanilla factions.
 local out,known={},{}
 for _,v in ipairs(public) do
  local copy={id=v.id,label=v.label,short=v.short,description=v.description,logo=v.logo,members=v.members,reputation=v.reputation,zombieKills=v.zombieKills,survivorKills=v.survivorKills,xp=v.xp,memberList=v.memberList,isConfig=v.isConfig}
  out[#out+1]=copy;known[copy.id]=copy
 end
 for id,f in pairs(Registry) do
  if not known[id] then out[#out+1]={id=id,label=f.label,short=f.short,description=f.description or '',logo=f.logo,members=0,reputation=0,zombieKills=0,survivorKills=0,xp=0,memberList={},isConfig=f.config}
  else known[id].isConfig=f.config end
 end
 table.sort(out,function(a,b) if a.isConfig~=b.isConfig then return a.isConfig end return a.label<b.label end)
 return out
end
-- Base permissions and sanctions live in bs_faction_bases; fail closed if it is down.
local function baseAllowed(src,perm) local ok,r=pcall(function() return exports.bs_faction_bases:FactionAllowed(src,perm) end);return ok and r==true end
local function sanctioned(id,effect) local ok,r=pcall(function() return exports.bs_faction_bases:FactionSanctioned(id,effect) end);if not ok then return true end;return r==true end
-- Per-player sanctions (bs_faction_bases/sv_sanctions.lua). failOpen for soft effects.
local function psanctioned(cid,effect,failOpen) local ok,r=pcall(function() return exports.bs_faction_bases:PlayerSanctioned(cid,effect) end);if not ok then return not failOpen end;return r==true end

-- Ranks. Each faction has its own ordered list; the first is always 'owner' (the Leader), who holds every
-- permission and can't be moved or deleted. Leaders add, rename, reorder and delete the others, and set
-- what each one may do. Rows live in bs_faction_ranks; the old fixed three (and their bs_faction_rank_perms
-- settings) are copied over the first time a faction is read. Vanilla factions start from Factions.DefaultRanks.
local PERMS = { 'deposit','withdraw','invite','kick','promote','sanction','build','demolish','storage','jail','squad_manage','skills','raid','jobs' }
local PermSet = {}; for _,k in ipairs(PERMS) do PermSet[k]=true end
local DefaultPerms = {
 officer = { deposit=true, withdraw=false, invite=true, kick=true, promote=false, sanction=true, build=true, demolish=true, storage=true, jail=true, squad_manage=true, skills=true, raid=true, jobs=true },
 member  = { deposit=true, withdraw=false, invite=false, kick=false, promote=false, sanction=false, build=true, demolish=false, storage=true, jail=false, squad_manage=false, skills=false, raid=false, jobs=false },
}
local LegacyLabel = { owner='Leader', officer='Vice Leader', member='Member' }
local MAX_RANKS = 10
local Ranks = {}          -- [fid] = { { id, label, perms, cap }, ... } top to bottom
local PermCache = Ranks   -- old name; sv_admin.lua clears an entry on disband

local function copyPerms(base) local out={}; for _,k in ipairs(PERMS) do out[k]=(base and base[k])==true end; return out end
local function decodePerms(raw, base)
 local perms=copyPerms(base)
 local ok,d=pcall(json.decode,raw or '{}')
 if ok and type(d)=='table' then for k,v in pairs(d) do if PermSet[k] then perms[k]=v==true end end end
 return perms
end
local function saveAll(fid)
 for i,r in ipairs(Ranks[fid] or {}) do
  x('INSERT INTO bs_faction_ranks(faction_id,rank_id,label,sort,perms_json,daily_cap) VALUES(?,?,?,?,?,?) ON DUPLICATE KEY UPDATE label=VALUES(label),sort=VALUES(sort),perms_json=VALUES(perms_json),daily_cap=VALUES(daily_cap)',
   {fid,r.id,r.label,i,json.encode(r.perms or {}),r.cap or 0})
 end
end
local function seedRanks(fid)
 local list={}
 for _,r in ipairs((Factions.DefaultRanks or {})[fid] or {}) do
  local perms=copyPerms(DefaultPerms[r.base or r.id] or DefaultPerms.member)
  for k,v in pairs(r.perms or {}) do if PermSet[k] then perms[k]=v==true end end
  list[#list+1]={id=r.id,label=r.label,perms=perms,cap=0}
 end
 if not list[1] or list[1].id~='owner' then table.insert(list,1,{id='owner',label=LegacyLabel.owner,perms={},cap=0}) end
 if #list<2 then
  list[#list+1]={id='officer',label=LegacyLabel.officer,perms=copyPerms(DefaultPerms.officer),cap=0}
  list[#list+1]={id='member',label=LegacyLabel.member,perms=copyPerms(DefaultPerms.member),cap=0}
 end
 -- keep whatever the leader had already set on the old fixed ranks
 for _,row in ipairs(q('SELECT `rank`,perms_json,daily_cap FROM bs_faction_rank_perms WHERE faction_id=?',{fid})) do
  for _,r in ipairs(list) do
   if r.id==row.rank then
    if r.id~='owner' then r.perms=decodePerms(row.perms_json,r.perms) end
    r.cap=tonumber(row.daily_cap) or 0
   end
  end
 end
 Ranks[fid]=list; saveAll(fid)
 return list
end
function ranksOf(fid)
 if not fid then return {} end
 if Ranks[fid] then return Ranks[fid] end
 local rows=q('SELECT rank_id,label,perms_json,daily_cap FROM bs_faction_ranks WHERE faction_id=? ORDER BY sort',{fid})
 if #rows==0 then return seedRanks(fid) end
 local list,owner={},nil
 for _,r in ipairs(rows) do
  local e={id=r.rank_id,label=r.label,perms=r.rank_id=='owner' and {} or decodePerms(r.perms_json,nil),cap=tonumber(r.daily_cap) or 0}
  if e.id=='owner' then owner=e else list[#list+1]=e end
 end
 table.insert(list,1,owner or {id='owner',label=LegacyLabel.owner,perms={},cap=0})
 Ranks[fid]=list
 return list
end
-- Position from the top (1 = Leader). A rank that no longer exists counts as the lowest.
function rankIdx(fid,id) local list=ranksOf(fid); for i,r in ipairs(list) do if r.id==id then return i end end; return #list end
local function rankValid(fid,id) for _,r in ipairs(ranksOf(fid)) do if r.id==id then return true end end; return false end
local function rankEntry(fid,id) local list=ranksOf(fid); for _,r in ipairs(list) do if r.id==id then return r end end; return list[#list] end
local function lowestRank(fid) local list=ranksOf(fid); return list[#list] and list[#list].id or 'member' end
local function secondRank(fid) local list=ranksOf(fid); return (list[2] or list[1] or {}).id or 'member' end
function rankLabel(fid,id) if not id then return nil end; for _,r in ipairs(ranksOf(fid)) do if r.id==id then return r.label end end; return LegacyLabel[id] or id end
local function rankRow(fid,rank) return rankEntry(fid,rank) or { perms={}, cap=0 } end
function rankHas(fid,rank,perm)
 if not fid or not rank then return false end
 if rank=='owner' then return true end
 local r=rankEntry(fid,rank)
 return r~=nil and r.id~='owner' and r.perms[perm]==true
end
local function permOk(s,perm) return s and s.id and rankHas(s.id,s.rank,perm) or false end
local function saveRank(fid) saveAll(fid) end
local function rankListOf(fid) local out={}; for _,r in ipairs(ranksOf(fid)) do out[#out+1]={id=r.id,label=r.label} end; return out end
local function myPerms(s) local out={}; for _,k in ipairs(PERMS) do out[k]=permOk(s,k) end; return out end
-- Leader sets any rank but Leader. Someone with `promote` only moves people below them, to ranks below them.
local function canSetRank(s,targetRank,want)
 if not s or not s.id or want=='owner' or targetRank=='owner' or not rankValid(s.id,want) then return false end
 if s.rank=='owner' then return true end
 if not permOk(s,'promote') then return false end
 local me=rankIdx(s.id,s.rank)
 return rankIdx(s.id,targetRank)>me and rankIdx(s.id,want)>me
end
-- Kick needs the permission and a target strictly below you.
local function canKick(s,targetRank)
 if not s or not s.id or targetRank=='owner' or not permOk(s,'kick') then return false end
 return s.rank=='owner' or rankIdx(s.id,targetRank)>rankIdx(s.id,s.rank)
end
local function args(names,a,...) if type(a)=='table' then return a end; local out,rest={}, {a,...}; for i,n in ipairs(names) do out[n]=rest[i] end; return out end
local function creditTreasury(fid,amount,cid,direction,note)
 amount=math.floor(tonumber(amount) or 0); if not fid or amount<1 then return false end
 x('INSERT INTO bs_faction_banks(faction_id,balance) VALUES(?,?) ON DUPLICATE KEY UPDATE balance=balance+VALUES(balance)',{fid,amount})
 BankBalances[fid]=nil
 x('INSERT INTO bs_faction_bank_log(faction_id,character_id,direction,amount,note) VALUES(?,?,?,?,?)',{fid,cid,direction,amount,tostring(note or ''):sub(1,96)})
 return true
end
local function bankMove(src, amount, withdraw)
    local s=state(src); amount=math.floor(tonumber(amount) or 0)
    if not s or not s.id or amount<1 then return {ok=false,error=Lp(src, 'fac.enter_a_valid_amount')} end
    local pl=p(src); if not pl then return {ok=false,error=Lp(src, 'fac.character_is_unavailable')} end; local bank=treasury(s.id)
    if withdraw then
        if not permOk(s,'withdraw') then return {ok=false,error=Lp(src, 'fac.your_rank_may_not_withdraw')} end
        if sanctioned(s.id,'bank') then return {ok=false,error=Lp(src, 'fac.the_faction_treasury_is_locked_by_a')} end
        if psanctioned(s.cid,'bank_lock') then return {ok=false,error=Lp(src, 'fac.you_are_sanctioned_treasury_access_i')} end
        -- Daily cap: reserve atomically first, refund if the balance move fails.
        local cap=rankRow(s.id,s.rank).cap
        if cap>0 then
            x('INSERT INTO bs_faction_bank_daily(faction_id,character_id,day,amount) VALUES(?,?,CURDATE(),0) ON DUPLICATE KEY UPDATE amount=amount',{s.id,s.cid})
            local reserved=exports.oxmysql:update_async('UPDATE bs_faction_bank_daily SET amount=amount+? WHERE faction_id=? AND character_id=? AND day=CURDATE() AND amount+?<=?',{amount,s.id,s.cid,amount,cap})
            if (tonumber(reserved) or 0)<1 then return {ok=false,error=Lp(src, 'fac.withdraw_cap', { cap = cap })} end
        end
        -- Atomic: the row only moves if the balance still covers it.
        local moved=exports.oxmysql:update_async('UPDATE bs_faction_banks SET balance=balance-? WHERE faction_id=? AND balance>=?',{amount,s.id,amount})
        if (tonumber(moved) or 0)<1 then
            BankBalances[s.id]=nil
            if cap>0 then x('UPDATE bs_faction_bank_daily SET amount=GREATEST(0,amount-?) WHERE faction_id=? AND character_id=? AND day=CURDATE()',{amount,s.id,s.cid}) end
            return {ok=false,error=Lp(src, 'fac.the_faction_bank_does_not_have_enoug')}
        end
        BankBalances[s.id]=nil; exports.bs_core:AddMoney(src,'cash',amount,'faction treasury withdrawal'); x('INSERT INTO bs_faction_bank_log(faction_id,character_id,direction,amount,note) VALUES(?,?,\'withdraw\',?,?)',{s.id,s.cid,amount,(rankLabel(s.id,s.rank) or 'Member')..' withdrawal'})
    else
        if not permOk(s,'deposit') then return {ok=false,error=Lp(src, 'fac.your_rank_may_not_deposit')} end
        if not exports.bs_core:RemoveMoney(src,'cash',amount,'faction treasury deposit') then return {ok=false,error=Lp(src, 'fac.you_do_not_have_enough_cash')} end
        x('INSERT INTO bs_faction_banks(faction_id,balance) VALUES(?,?) ON DUPLICATE KEY UPDATE balance=balance+VALUES(balance)',{s.id,amount}); BankBalances[s.id]=bank.balance+amount; x('INSERT INTO bs_faction_bank_log(faction_id,character_id,direction,amount,note) VALUES(?,?,\'deposit\',?,?)',{s.id,s.cid,amount,'Member deposit'})
    end
    return {ok=true}
end
local function adminCandidates()
    local rows = q([[SELECT c.id, c.first_name, c.last_name, c.level
        FROM bs_characters c
        LEFT JOIN bs_faction_members m ON m.character_id = c.id
        WHERE c.deleted_at IS NULL AND m.character_id IS NULL
        ORDER BY c.first_name, c.last_name
        LIMIT 200]])
    local out = {}
    for _, row in ipairs(rows) do
        local name = ((row.first_name or '?') .. ' ' .. (row.last_name or '')):gsub('%s+$', '')
        out[#out + 1] = { id = tonumber(row.id), name = name, level = tonumber(row.level) or 1 }
    end
    return out
end
local function panel(src)
 if not Ready then return {ok=false,error=Lp(src, 'fac.faction_service_is_starting')} end
 local s=state(src);if not s then return {ok=false,error=Lp(src, 'fac.character_is_loading')} end
 local summary=playerSummary(src);if not summary then return {ok=false,error=Lp(src, 'fac.character_is_unavailable')} end
 local public=directory();local out={ok=true,faction=nil,rank=nil,members={},nearby={},invite=nil,canCreate=not s.id,directory=public,admin=isAdmin(src)}
 if out.admin then out.adminFactions=adminDirectory(public);out.adminCandidates=adminCandidates() end
 local i=Invites[src];if i and i.until_>os.time() and Registry[i.id] then out.invite={faction=i.id,label=Registry[i.id].label,seconds=i.until_-os.time()} end
 if not s.id then return out end
 local f=Registry[s.id];if not f then return {ok=false,error=Lp(src, 'fac.faction_data_is_missing')} end
 local details=nil;for _,entry in ipairs(public) do if entry.id==s.id then details=entry;break end end
 details=details or {members=0,reputation=0,zombieKills=0,survivorKills=0,xp=0,memberList={}}
 out.rank=s.rank;out.rankLabel=rankLabel(s.id,s.rank);out.ranks=rankListOf(s.id);out.myPerms=myPerms(s);out.myRankIdx=rankIdx(s.id,s.rank);out.faction={id=f.id,label=f.label,short=f.short,blurb=(f.description and f.description~='' and f.description or 'No faction description has been written yet.'),description=f.description or '',lore=f.config,reputation=details.reputation,bank=treasury(s.id),cash=((summary.accounts or {}).cash or 0),logo=f.logo,scoreboard={members=details.members,zombieKills=details.zombieKills,survivorKills=details.survivorKills,xp=details.xp}}
 for _,m in ipairs(details.memberList or {}) do m.you=m.charId==s.cid;out.members[#out.members+1]=m end
 if permOk(s,'invite') then local ped=GetPlayerPed(src);if ped and ped~=0 then local at=GetEntityCoords(ped);for _,v in ipairs(GetPlayers()) do local t=tonumber(v);local ts=state(t);local tp=GetPlayerPed(t);if t~=src and ts and not ts.id and tp and tp~=0 and #(GetEntityCoords(tp)-at)<=25.0 then out.nearby[#out.nearby+1]={src=t,name=GetPlayerName(t) or 'Survivor'} end end end end
 return out
end
local function description(src,text)
 local s=state(src);if not s or not s.id or s.rank~='owner' then return {ok=false,error=Lp(src, 'fac.only_the_faction_leader_may_edit_the')} end;local f=Registry[s.id];if not f then return {ok=false,error=Lp(src, 'fac.faction_data_is_missing')} end;text=tostring(text or ''):gsub('[%c]',' '):gsub('%s+',' '):sub(1,360);x('UPDATE bs_faction_registry SET description=? WHERE faction_id=?',{text,s.id});f.description=text;return {ok=true}
end
local function logo(src, mark, color)
 local s=state(src); if not s or not s.id or s.rank~='owner' then return {ok=false,error=Lp(src, 'fac.only_the_faction_leader_may_change_t')} end
 mark=tostring(mark or ''):lower(); color=tostring(color or ''):lower()
 local allowed={wolf=true,skull=true,claw=true,shield=true,eye=true,bolt=true,crown=true,serpent=true}
 if not allowed[mark] or not color:match('^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$') then return {ok=false,error=Lp(src, 'fac.that_emblem_is_invalid')} end
 local value=json.encode({mark=mark,color=color}); local f=Registry[s.id]; if not f then return {ok=false,error=Lp(src, 'fac.faction_data_is_missing')} end
 x('UPDATE bs_faction_registry SET logo=? WHERE faction_id=?',{value,s.id}); f.logo=value; return {ok=true,logo=value}
end
local function create(src,name,short)
 local s=state(src);name=tostring(name or ''):gsub('[%c]',''):sub(1,48);short=tostring(short or ''):upper():gsub('[^A-Z0-9]',''):sub(1,8);local id=name:lower():gsub('[^a-z0-9]',''):sub(1,24)
 if not s then return {ok=false,error=Lp(src, 'fac.character_is_loading')} end;if s.id then return {ok=false,error=Lp(src, 'fac.leave_your_current_faction_first')} end;if #name<3 or #short<2 or #id<3 then return {ok=false,error=Lp(src, 'fac.use_a_name_and_2_8_character_tag')} end;if Registry[id] then return {ok=false,error=Lp(src, 'fac.that_faction_already_exists')} end
 local ok=pcall(x,'INSERT INTO bs_faction_registry(faction_id,label,short,owner_character_id,created_by,is_config) VALUES(?,?,?,?,?,0)',{id,name,short,s.cid,s.cid});if not ok then return {ok=false,error=Lp(src, 'fac.faction_could_not_be_saved')} end;Registry[id]={id=id,label=name,short=short,owner=s.cid,config=false};x('INSERT INTO bs_faction_members(character_id,faction_id,rank) VALUES(?,?,?)',{s.cid,id,'owner'});s.id=id;s.rank='owner';s.rep=0;sync(src);return {ok=true,label=name}
end
local function invite(src,target)
 local s=state(src);target=tonumber(target);local t=target and state(target);if not s or not s.id or not permOk(s,'invite') then return {ok=false,error=Lp(src, 'fac.your_rank_may_not_invite')} end;if not t or t.id then return {ok=false,error=Lp(src, 'fac.that_survivor_is_unavailable')} end;local a,b=GetPlayerPed(src),GetPlayerPed(target);if not a or a==0 or not b or b==0 or #(GetEntityCoords(a)-GetEntityCoords(b))>25.0 then return {ok=false,error=Lp(src, 'fac.stand_closer_to_invite_them')} end;Invites[target]={id=s.id,by=s.cid,until_=os.time()+120};TriggerClientEvent('bs:ui:notify',target,{type='info',message=Lp(target, 'fac.faction_invitation_received_open_u_f'),duration=6000});return {ok=true}
end
local function accept(src)local s=state(src);local i=Invites[src];if not s or s.id then return {ok=false,error=Lp(src, 'fac.you_are_already_in_a_faction')} end;if not i or i.until_<os.time() or not Registry[i.id] then Invites[src]=nil;return {ok=false,error=Lp(src, 'fac.invitation_expired')} end;local by=one('SELECT rank FROM bs_faction_members WHERE character_id=? AND faction_id=? LIMIT 1',{i.by,i.id});if not by or not rankHas(i.id,by.rank,'invite') then Invites[src]=nil;return {ok=false,error=Lp(src, 'fac.that_invitation_is_no_longer_valid')} end;local low=lowestRank(i.id);x('INSERT INTO bs_faction_members(character_id,faction_id,rank) VALUES(?,?,?)',{s.cid,i.id,low});s.id=i.id;s.rank=low;s.rep=0;Invites[src]=nil;sync(src);return {ok=true,label=Registry[s.id].label}end
local function rank(src,target,want)local s=state(src);local t=state(target);want=tostring(want or ''):lower();if not s or not t or t==s or t.id~=s.id or not canSetRank(s,t.rank,want) then return {ok=false,error=Lp(src, 'fac.that_role_change_is_unavailable')} end;x('UPDATE bs_faction_members SET rank=? WHERE character_id=? AND faction_id=?',{want,t.cid,s.id});t.rank=want;sync(target);return {ok=true,rank=want}end
local function kick(src,target)local s=state(src);local t=state(target);if not s or not t or t==s or t.id~=s.id or not canKick(s,t.rank) then return {ok=false,error=Lp(src, 'fac.you_cannot_remove_that_member')}end;save(t);x('DELETE FROM bs_faction_members WHERE character_id=?',{t.cid});t.id=nil;t.rank=nil;t.rep=0;sync(target);return {ok=true}end
local function leave(src)local s=state(src);if not s or not s.id then return {ok=false,error=Lp(src, 'fac.you_are_not_in_a_faction')}end;if s.rank=='owner'then return {ok=false,error=Lp(src, 'fac.leaders_cannot_leave_transfer_owners')}end;if sanctioned(s.id,'leave') then return {ok=false,error=Lp(src, 'fac.your_faction_is_sanctioned_membershi')}end;if psanctioned(s.cid,'leave_lock') then return {ok=false,error=Lp(src, 'fac.you_are_sanctioned_you_cannot_leave')}end;return kickOwnerless(src,s)end
function kickOwnerless(src,s) save(s);x('DELETE FROM bs_faction_members WHERE character_id=?',{s.cid});s.id=nil;s.rank=nil;s.rep=0;sync(src);return {ok=true}end
local function disband(src)local s=state(src);if not s or s.rank~='owner' then return {ok=false,error=Lp(src, 'fac.only_the_owner_may_disband')}end;local f=Registry[s.id];if not f or f.config then return {ok=false,error=Lp(src, 'fac.this_faction_cannot_be_disbanded')}end;local id=s.id;for _,v in ipairs(GetPlayers())do local t=State[tonumber(v)];if t and t.id==id then t.id=nil;t.rank=nil;t.rep=0;sync(tonumber(v))end end;x('DELETE FROM bs_faction_members WHERE faction_id=?',{id});x('DELETE FROM bs_faction_registry WHERE faction_id=?',{id});x('DELETE FROM bs_faction_rank_perms WHERE faction_id=?',{id});Ranks[id]=nil;x('DELETE FROM bs_faction_ranks WHERE faction_id=?',{id});pcall(function() exports.bs_faction_bases:ClearFaction(id) end);Registry[id]=nil;return {ok=true,label=f.label}end
BSB.RegisterCallback('factions:description',description);BSB.RegisterCallback('factions:logo',logo);BSB.RegisterCallback('factions:bank:deposit',function(src,amount)return bankMove(src,amount,false)end);BSB.RegisterCallback('factions:bank:withdraw',function(src,amount)return bankMove(src,amount,true)end);BSB.RegisterCallback('factions:panel',panel);BSB.RegisterCallback('factions:create',create);BSB.RegisterCallback('factions:invite',invite);BSB.RegisterCallback('factions:targetInvite',invite);BSB.RegisterCallback('factions:accept',accept);BSB.RegisterCallback('factions:promote',rank);BSB.RegisterCallback('factions:kick',kick);BSB.RegisterCallback('factions:leave',leave);BSB.RegisterCallback('factions:leave2',leave);BSB.RegisterCallback('factions:disband',disband);BSB.RegisterCallback('factions:status',function(src)local s=state(src);return s and {ok=true,factionId=s.id,rank=s.rank,reputation=s.rep}or{ok=false}end);BSB.RegisterCallback('factions:roster',function(src)local s=state(src);return s and s.id and{ok=true,members=members(s.id)}or{ok=false}end);
exports('GetFaction',function(src)local s=state(src);return s and s.id end);exports('GetFactionSummary',function(src)local s=state(src);local f=s and Registry[s.id];return s and{factionId=s.id,label=f and f.label,short=f and f.short,reputation=s.rep,rank=s.rank,rankLabel=s.id and rankLabel(s.id,s.rank) or nil}end);exports('FactionRank',function(src)local s=state(src);return s and s.rank end);exports('AddReputation',function(src,n)local s=state(src);if not s or not s.id then return false end;if (tonumber(n) or 0)>0 and psanctioned(s.cid,'rep_freeze',true) then return s.rep end;s.rep=math.max(0,math.min(Factions.Settings.maxReputation,(s.rep or 0)+math.floor(tonumber(n)or 0)));sync(src);return s.rep end)
-- Treasury info / rank permissions / caps
local function bankInfo(src)
 local s=state(src); if not s or not s.id then return {ok=false,error=Lp(src, 'fac.you_are_not_in_a_faction')} end
 local bal=treasury(s.id).balance
 local rows=q('SELECT l.direction,l.amount,l.note,l.character_id,UNIX_TIMESTAMP(l.created_at) AS at,c.first_name,c.last_name FROM bs_faction_bank_log l LEFT JOIN bs_characters c ON c.id=l.character_id WHERE l.faction_id=? ORDER BY l.id DESC LIMIT 50',{s.id})
 local log={}; for _,v in ipairs(rows) do log[#log+1]={direction=v.direction,amount=tonumber(v.amount),note=v.note,charId=tonumber(v.character_id),at=tonumber(v.at),name=v.first_name and ((v.first_name..' '..(v.last_name or '')):gsub('%s+$','')) or nil} end
 local caps,rankList={},{}; for _,r in ipairs(ranksOf(s.id)) do caps[r.id]=r.cap or 0; rankList[#rankList+1]={id=r.id,label=r.label} end
 local cap=caps[s.rank] or 0; local left=-1
 if cap>0 then local d=one('SELECT amount FROM bs_faction_bank_daily WHERE faction_id=? AND character_id=? AND day=CURDATE() LIMIT 1',{s.id,s.cid}); left=math.max(0,cap-(d and tonumber(d.amount) or 0)) end
 return {ok=true,balance=bal,log=log,myDailyLeft=left,caps=caps,rank=s.rank,rankLabel=rankLabel(s.id,s.rank),rankList=rankList,canWithdraw=permOk(s,'withdraw') and not sanctioned(s.id,'bank') and not psanctioned(s.cid,'bank_lock'),canDeposit=permOk(s,'deposit'),canEdit=s.rank=='owner'}
end
local function permsGet(src)
 local s=state(src); if not s or not s.id then return {ok=false,error=Lp(src, 'fac.you_are_not_in_a_faction')} end
 local ranks,matrix,caps,counts={}, {}, {}, {}
 for _,row in ipairs(q('SELECT `rank`,COUNT(*) AS n FROM bs_faction_members WHERE faction_id=? GROUP BY `rank`',{s.id})) do counts[row.rank]=tonumber(row.n) or 0 end
 for _,r in ipairs(ranksOf(s.id)) do
  ranks[#ranks+1]={id=r.id,label=r.label,locked=r.id=='owner',members=counts[r.id] or 0}
  local m={}; for _,p in ipairs(PERMS) do m[p]=rankHas(s.id,r.id,p) end; matrix[r.id]=m; caps[r.id]=r.cap or 0
 end
 local mine={}; for _,p in ipairs(PERMS) do mine[p]=permOk(s,p) end
 return {ok=true,ranks=ranks,perms=PERMS,matrix=matrix,caps=caps,mine=mine,rank=s.rank,canEdit=s.rank=='owner',maxRanks=MAX_RANKS}
end
local function permsSet(src,...)
 local s=state(src); if not s or not s.id or s.rank~='owner' then return {ok=false,error=Lp(src, 'fac.only_the_faction_leader_may_edit_per')} end
 local a=args({'rank','perm','bool'},...); local rank=tostring(a.rank or ''); local perm=tostring(a.perm or ''); local val=a.bool; if val==nil then val=a.value end
 if rank=='owner' or not rankValid(s.id,rank) or not PermSet[perm] then return {ok=false,error=Lp(src, 'fac.that_permission_cannot_be_changed')} end
 rankRow(s.id,rank).perms[perm]=(val==true or val==1 or val=='true'); saveRank(s.id,rank)
 return permsGet(src)
end
local function setCap(src,...)
 local s=state(src); if not s or not s.id or s.rank~='owner' then return {ok=false,error=Lp(src, 'fac.only_the_faction_leader_may_set_caps')} end
 local a=args({'rank','amount'},...); local rank=tostring(a.rank or ''); local amount=math.floor(tonumber(a.amount) or -1)
 if not rankValid(s.id,rank) or amount<0 or amount>1000000000 then return {ok=false,error=Lp(src, 'fac.enter_a_valid_cap_0_unlimited')} end
 rankRow(s.id,rank).cap=amount; saveRank(s.id,rank)
 return {ok=true,rank=rank,amount=amount}
end
BSB.RegisterCallback('factions:bank:info',bankInfo)
BSB.RegisterCallback('factions:perms:get',permsGet)
BSB.RegisterCallback('factions:perms:set',permsSet)
BSB.RegisterCallback('factions:bank:setCap',setCap)

-- Rank editor, Leader only: create, rename, move, delete. Each answers with the fresh permissions view.
local function leaderOf(src) local s=state(src); if not s or not s.id or s.rank~='owner' then return nil end; return s end
local function noLeader(src) return {ok=false,error=Lp(src, 'fac.only_the_faction_leader_may_edit_per')} end
local function cleanLabel(t) return (tostring(t or ''):gsub('[%c<>"]',''):gsub('%s+',' '):gsub('^%s+',''):gsub('%s+$',''):sub(1,24)) end
local function resyncFaction(fid) for src,st in pairs(State) do if st.id==fid then sync(src) end end end
local function findRank(fid,id) for i,e in ipairs(ranksOf(fid)) do if e.id==id then return i,e end end end

BSB.RegisterCallback('factions:ranks:create',function(src,...)
 local s=leaderOf(src); if not s then return noLeader(src) end
 local a=args({'label'},...); local label=cleanLabel(a.label)
 if #label<2 then return {ok=false,error=Lp(src, 'fac.rank_name_bad')} end
 local list=ranksOf(s.id)
 if #list>=MAX_RANKS then return {ok=false,error=Lp(src, 'fac.rank_limit',{n=MAX_RANKS})} end
 local id; repeat id=('r%d'):format(math.random(100000,999999)) until not rankValid(s.id,id)
 -- goes just above the bottom rank, so newcomers keep joining at the bottom
 table.insert(list,#list,{id=id,label=label,perms=copyPerms(DefaultPerms.member),cap=0})
 saveAll(s.id); resyncFaction(s.id)
 return permsGet(src)
end)

BSB.RegisterCallback('factions:ranks:rename',function(src,...)
 local s=leaderOf(src); if not s then return noLeader(src) end
 local a=args({'rank','label'},...); local label=cleanLabel(a.label)
 if #label<2 then return {ok=false,error=Lp(src, 'fac.rank_name_bad')} end
 local _,r=findRank(s.id,tostring(a.rank or ''))
 if not r then return {ok=false,error=Lp(src, 'fac.rank_unknown')} end
 r.label=label; saveAll(s.id); resyncFaction(s.id)
 return permsGet(src)
end)

BSB.RegisterCallback('factions:ranks:move',function(src,...)
 local s=leaderOf(src); if not s then return noLeader(src) end
 local a=args({'rank','dir'},...)
 local list=ranksOf(s.id); local i=findRank(s.id,tostring(a.rank or ''))
 if not i or i==1 then return {ok=false,error=Lp(src, 'fac.rank_unknown')} end
 local j=a.dir=='up' and i-1 or i+1
 if j>=2 and j<=#list then list[i],list[j]=list[j],list[i]; saveAll(s.id); resyncFaction(s.id) end
 return permsGet(src)
end)

-- Members of a deleted rank drop to the rank that was below it (or the new bottom one).
BSB.RegisterCallback('factions:ranks:delete',function(src,...)
 local s=leaderOf(src); if not s then return noLeader(src) end
 local a=args({'rank'},...)
 local list=ranksOf(s.id); local i,gone=findRank(s.id,tostring(a.rank or ''))
 if not i or i==1 then return {ok=false,error=Lp(src, 'fac.rank_unknown')} end
 if #list<=2 then return {ok=false,error=Lp(src, 'fac.rank_keep_one')} end
 table.remove(list,i)
 local into=(list[i] or list[#list]).id
 x('UPDATE bs_faction_members SET `rank`=? WHERE faction_id=? AND `rank`=?',{into,s.id,gone.id})
 x('DELETE FROM bs_faction_ranks WHERE faction_id=? AND rank_id=?',{s.id,gone.id})
 for _,st in pairs(State) do if st.id==s.id and st.rank==gone.id then st.rank=into end end
 saveAll(s.id); resyncFaction(s.id)
 return permsGet(src)
end)

-- Promote / kick by character id, so offline members can be managed too.
-- Online targets go through the normal rank()/kick() path; same checks either way.
local function srcOfChar(cid) for _,v in ipairs(GetPlayers()) do local t=State[tonumber(v)]; if t and t.cid==cid then return tonumber(v) end end end
local function offlineRow(s,cid)
    if not s or not s.id or not cid or cid==s.cid then return nil end
    local r=one('SELECT rank FROM bs_faction_members WHERE character_id=? AND faction_id=? LIMIT 1',{cid,s.id})
    return r
end
BSB.RegisterCallback('factions:promoteChar',function(src,...)
    local a=args({'charId','rank'},...); local cid=tonumber(a.charId); local want=tostring(a.rank or ''):lower()
    local online=cid and srcOfChar(cid); if online then return rank(src,online,want) end
    local s=state(src); local t=offlineRow(s,cid)
    if not s or not t or not canSetRank(s,t.rank,want) then return {ok=false,error=Lp(src, 'fac.that_role_change_is_unavailable')} end
    x('UPDATE bs_faction_members SET rank=? WHERE character_id=? AND faction_id=?',{want,cid,s.id})
    return {ok=true,rank=want}
end)
BSB.RegisterCallback('factions:kickChar',function(src,...)
    local a=args({'charId'},...); local cid=tonumber(a.charId)
    local online=cid and srcOfChar(cid); if online then return kick(src,online) end
    local s=state(src); local t=offlineRow(s,cid)
    if not s or not t or not canKick(s,t.rank) then return {ok=false,error=Lp(src, 'fac.you_cannot_remove_that_member')} end
    x('DELETE FROM bs_faction_members WHERE character_id=? AND faction_id=?',{cid,s.id})
    -- kicked from the faction = out of the squad right away, even offline
    if SquadRemoveChar then pcall(SquadRemoveChar,cid) end
    return {ok=true}
end)
-- Whole roster (online + offline) of the caller's faction.
BSB.RegisterCallback('factions:rosterAll',function(src) local s=state(src); return s and s.id and {ok=true,members=members(s.id)} or {ok=false,error=Lp(src, 'fac.you_are_not_in_a_faction')} end)
-- nil for a permission this service does not own, so callers can fall back.
exports('RankAllowed',function(src,perm) perm=tostring(perm or ''); if not PermSet[perm] then return nil end; return permOk(state(src),perm) end)
-- Position of a rank in its faction, 1 = Leader. Lower number = higher rank.
exports('RankIndex',function(fid,rank) if not fid or not Registry[fid] then return nil end; return rankIdx(fid,rank) end)
-- Number of ranks in a faction (last = recruit).
exports('RankCount',function(fid) if not fid or not Registry[fid] then return nil end; return #ranksOf(fid) end)
exports('RankLabel',function(rank,fid) if fid then return rankLabel(fid,rank) end; return LegacyLabel[rank] or rank end)
-- Progression (sv_progression.lua): mission pay and member donations.
exports('TreasuryDeposit',function(fid,amount,cid,direction,note) return creditTreasury(fid,amount,tonumber(cid),tostring(direction or 'deposit'):sub(1,16),note) end)
exports('TreasuryCredit',function(fid,amount,cid,note) return creditTreasury(fid,amount,tonumber(cid),'fine',note or 'Sanction fine') end)
-- Removes up to `amount` (never below 0) and returns what was taken.
exports('TreasuryDebit',function(fid,amount,note)
 amount=math.floor(tonumber(amount) or 0); if not fid or amount<1 then return 0 end
 local bal=treasury(fid).balance; local take=math.min(amount,math.max(0,bal)); if take<1 then return 0 end
 local moved=exports.oxmysql:update_async('UPDATE bs_faction_banks SET balance=balance-? WHERE faction_id=? AND balance>=?',{take,fid,take}); BankBalances[fid]=nil
 if (tonumber(moved) or 0)<1 then return 0 end
 x('INSERT INTO bs_faction_bank_log(faction_id,character_id,direction,amount,note) VALUES(?,NULL,?,?,?)',{fid,'fine',take,tostring(note or 'Sanction fine'):sub(1,96)}); return take
end)
-- Reputation change by character, online or offline (sanction rep_penalty).
exports('AdjustReputation',function(cid,delta)
 cid=tonumber(cid); delta=math.floor(tonumber(delta) or 0); if not cid or delta==0 then return false end
 for src,st in pairs(State) do if st.cid==cid and st.id then st.rep=math.max(0,math.min(Factions.Settings.maxReputation,(st.rep or 0)+delta)); save(st); sync(src); return st.rep end end
 local m=one('SELECT faction_id FROM bs_faction_members WHERE character_id=? LIMIT 1',{cid}); if not m then return false end
 x('INSERT INTO bs_faction_reputation(character_id,faction_id,reputation) VALUES(?,?,GREATEST(0,?)) ON DUPLICATE KEY UPDATE reputation=GREATEST(0,reputation+?)',{cid,m.faction_id,delta,delta}); return true
end)
local staff=isAdmin
local function adminUpdate(src,id,text,mark,color)
 if not staff(src) then return {ok=false,error=Lp(src, 'fac.not_allowed')} end
 local f=Registry[tostring(id or '')];if not f then return {ok=false,error=Lp(src, 'fac.faction_not_found')} end
 text=tostring(text or ''):gsub('[%c]',' '):gsub('%s+',' '):sub(1,360)
 mark=tostring(mark or ''):lower();color=tostring(color or ''):lower()
 local allowed={wolf=true,skull=true,claw=true,shield=true,eye=true,bolt=true,crown=true,serpent=true}
 if not allowed[mark] or not color:match('^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$') then return {ok=false,error=Lp(src, 'fac.the_emblem_is_invalid')} end
 local value=json.encode({mark=mark,color=color})
 x('UPDATE bs_faction_registry SET description=?,logo=? WHERE faction_id=?',{text,value,f.id});f.description=text;f.logo=value
 return {ok=true}
end
local function adminAssignVanilla(src, id, charId)
    if not staff(src) then return { ok = false, error = Lp(src, 'fac.not_allowed') } end
    local faction = Registry[tostring(id or '')]
    charId = tonumber(charId)
    if not faction or not faction.config then
        return { ok = false, error = Lp(src, 'fac.only_a_vanilla_faction_can_be_assign') }
    end
    if not charId then return { ok = false, error = Lp(src, 'fac.choose_an_eligible_survivor') } end
    if one('SELECT faction_id FROM bs_faction_members WHERE character_id = ? LIMIT 1', { charId }) then
        return { ok = false, error = Lp(src, 'fac.that_survivor_already_belongs_to_a_f') }
    end
    x("UPDATE bs_faction_members SET rank = ? WHERE faction_id = ? AND rank = 'owner'", { secondRank(faction.id), faction.id })
    x('INSERT INTO bs_faction_members (character_id, faction_id, rank) VALUES (?, ?, ?)', { charId, faction.id, 'owner' })
    x('UPDATE bs_faction_registry SET owner_character_id = ? WHERE faction_id = ?', { charId, faction.id })
    faction.owner = charId
    for source, stateValue in pairs(State) do
        if stateValue and stateValue.cid == charId then
            stateValue.id = faction.id
            stateValue.rank = 'owner'
            stateValue.rep = stateValue.rep or 0
            sync(source)
        elseif stateValue and stateValue.id == faction.id and stateValue.rank == 'owner' then
            stateValue.rank = secondRank(faction.id)
            sync(source)
        end
    end
    return { ok = true }
end
BSB.RegisterCallback('factions:admin:update',function(src,id,text,mark,color)return adminUpdate(src,id,text,mark,color)end)
BSB.RegisterCallback('factions:admin:assignVanilla',function(src,id,charId)return adminAssignVanilla(src,id,charId)end)
BSB.RegisterCallback('factions:admin:list', function(src)
 if not staff(src) then return {ok=false,error=Lp(src, 'fac.not_allowed')} end
 local out={};for _,f in pairs(Registry) do out[#out+1]={faction_id=f.id,label=f.label,short=f.short,is_config=f.config and 1 or 0,owner_character_id=f.owner,members=#members(f.id)} end;return {ok=true,factions=out}
end)
BSB.RegisterCallback('factions:admin:delete', function(src,id)
 if not staff(src) then return {ok=false,error=Lp(src, 'fac.not_allowed')} end;local f=Registry[tostring(id or '')];if not f or f.config then return {ok=false,error=Lp(src, 'fac.faction_cannot_be_deleted')} end
 for source,s in pairs(State) do if s.id==f.id then s.id=nil;s.rank=nil;s.rep=0;sync(source) end end;x('DELETE FROM bs_faction_members WHERE faction_id=?',{f.id});x('DELETE FROM bs_faction_registry WHERE faction_id=?',{f.id});x('DELETE FROM bs_faction_ranks WHERE faction_id=?',{f.id});Ranks[f.id]=nil;Registry[f.id]=nil;return {ok=true}
end)
BSB.RegisterCallback('factions:admin:reset', function(src)
 if not staff(src) then return {ok=false,error=Lp(src, 'fac.not_allowed')} end;local ids={};for id,f in pairs(Registry)do if not f.config then ids[#ids+1]=id end end;for _,id in ipairs(ids)do x('DELETE FROM bs_faction_members WHERE faction_id=?',{id});x('DELETE FROM bs_faction_registry WHERE faction_id=?',{id});x('DELETE FROM bs_faction_ranks WHERE faction_id=?',{id});Ranks[id]=nil;Registry[id]=nil end;for source,s in pairs(State)do if s.id and not Registry[s.id]then s.id=nil;s.rank=nil;s.rep=0;sync(source)end end;return {ok=true,removed=#ids}
end)
AddEventHandler('bs:hook:player:loaded',function(pl)if pl and pl.source then load(pl.source)end end)
AddEventHandler('playerDropped',function()
 local src = source -- FiveM's event source is only valid before a yielding database call.
 if not src then return end
 local previous = State[src]
 State[src] = nil
 Invites[src] = nil
 save(previous)
end)
CreateThread(function()while GetResourceState('oxmysql')~='started'do Wait(250)end;x('CREATE TABLE IF NOT EXISTS bs_faction_banks (faction_id VARCHAR(32) NOT NULL,balance INT NOT NULL DEFAULT 0,PRIMARY KEY(faction_id))');x('CREATE TABLE IF NOT EXISTS bs_faction_bank_log (id INT UNSIGNED NOT NULL AUTO_INCREMENT,faction_id VARCHAR(32) NOT NULL,character_id INT UNSIGNED NULL,direction VARCHAR(16) NOT NULL,amount INT NOT NULL,note VARCHAR(96) NULL,created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(id),KEY(faction_id))');x('CREATE TABLE IF NOT EXISTS bs_faction_registry (faction_id VARCHAR(32) NOT NULL,label VARCHAR(48) NOT NULL,short VARCHAR(8) NOT NULL DEFAULT \'\',owner_character_id INT UNSIGNED NULL,created_by INT UNSIGNED NULL,is_config TINYINT(1) NOT NULL DEFAULT 0,description TEXT NULL,created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(faction_id))');x('CREATE TABLE IF NOT EXISTS bs_faction_rank_perms (faction_id VARCHAR(32) NOT NULL,`rank` VARCHAR(16) NOT NULL,perms_json TEXT NOT NULL,daily_cap INT NOT NULL DEFAULT 0,PRIMARY KEY(faction_id,`rank`))');x('CREATE TABLE IF NOT EXISTS bs_faction_ranks (faction_id VARCHAR(32) NOT NULL,rank_id VARCHAR(16) NOT NULL,label VARCHAR(32) NOT NULL,sort INT NOT NULL DEFAULT 0,perms_json TEXT NOT NULL,daily_cap INT NOT NULL DEFAULT 0,PRIMARY KEY(faction_id,rank_id))');x('CREATE TABLE IF NOT EXISTS bs_faction_bank_daily (faction_id VARCHAR(32) NOT NULL,character_id INT UNSIGNED NOT NULL,day DATE NOT NULL,amount INT NOT NULL DEFAULT 0,PRIMARY KEY(faction_id,character_id,day))');pcall(x,"ALTER TABLE bs_faction_members ADD COLUMN IF NOT EXISTS rank VARCHAR(16) NOT NULL DEFAULT 'member'");pcall(x,"ALTER TABLE bs_faction_registry ADD COLUMN IF NOT EXISTS description TEXT NULL");pcall(x,"ALTER TABLE bs_faction_registry ADD COLUMN IF NOT EXISTS logo VARCHAR(128) NULL");Wait(500);for _,row in ipairs(q('SELECT * FROM bs_faction_registry'))do Registry[row.faction_id]={id=row.faction_id,label=row.label,short=row.short or '',owner=tonumber(row.owner_character_id),config=(row.is_config==true or tonumber(row.is_config)==1),description=row.description or '',logo=row.logo}end;Ready=true;for _,id in ipairs(GetPlayers())do load(tonumber(id))end;print('^2[BeyondSurvival]^7 faction service ready')end)


CreateThread(function()
    while true do
        Wait(1000)
        local zones = GetResourceState('bs_zombies') == 'started' and exports.bs_zombies:SafeZones() or {}
        for _, idText in ipairs(GetPlayers()) do
            local src = tonumber(idText); local ped = GetPlayerPed(src); local inside = false
            if ped and ped ~= 0 then
                local c = GetEntityCoords(ped)
                for _, z in ipairs(zones or {}) do
                    local dx, dy = c.x - z.x, c.y - z.y
                    if (dx * dx + dy * dy) <= (z.radius * z.radius) then inside = true; break end
                end
            end
            Player(src).state:set('bsFactionSafeZone', inside, true)
        end
    end
end)

-- Faction/squad membership never changes PvP. A safe zone protects a player inside it and anyone that player could shoot from inside.
local function inPvpSafeZone(src, zones)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    for _, zone in ipairs(zones) do
        local dx, dy = pos.x - zone.x, pos.y - zone.y
        if dx * dx + dy * dy <= zone.radius * zone.radius then return true end
    end
    return false
end

AddEventHandler('weaponDamageEvent', function(sender, data)
    if GetResourceState('bs_zombies') ~= 'started' then return end
    local attacker = tonumber(sender)
    if not attacker or not GetPlayerName(attacker) then return end
    local targets = data and data.hitGlobalIds
    if type(targets) ~= 'table' or #targets == 0 then
        targets = { data and data.hitGlobalId }
    end
    local victim
    for _, netId in ipairs(targets) do
        if type(netId) == 'number' and netId > 0 then
            local entity = NetworkGetEntityFromNetworkId(netId)
            if entity and entity ~= 0 then
                for _, idText in ipairs(GetPlayers()) do
                    local candidate = tonumber(idText)
                    if candidate ~= attacker and GetPlayerPed(candidate) == entity then
                        victim = candidate
                        break
                    end
                end
            end
        end
        if victim then break end
    end
    if not victim then return end -- Never suppress zombie/world damage.
    local zones = exports.bs_zombies:SafeZones() or {}
    if inPvpSafeZone(attacker, zones) or inPvpSafeZone(victim, zones) then
        CancelEvent()
    end
end)



-- Shared with sv_admin.lua (same resource, same Lua state). Admin tooling only.
FactionsCore = {
 Registry=Registry, State=State, BankBalances=BankBalances, PermCache=PermCache, Ranks=Ranks,
 ranksOf=ranksOf, rankIdx=rankIdx, rankValid=rankValid, rankLabel=rankLabel, rankHas=rankHas,
 lowestRank=lowestRank, secondRank=secondRank, saveRanks=saveAll,
 isAdmin=isAdmin, state=state, sync=sync, save=save, members=members,
 treasury=treasury, creditTreasury=creditTreasury, one=one, q=q, x=x,
 ready=function() return Ready end,
}


-- Vanilla factions (config ones): always open. Joining makes you a Member, leaving starts a
-- cooldown before you can join another vanilla faction, and only an admin can set the Leader
-- (Admin panel -> assign vanilla owner). Player-made factions stay invitation only.
local function isVanillaId(id) return id and Registry[id] and Registry[id].config end

local function cooldownLeft(cid)
    local r = one('SELECT until_ts FROM bs_faction_cooldowns WHERE character_id=? LIMIT 1', { cid })
    local left = (r and tonumber(r.until_ts) or 0) - os.time()
    return left > 0 and left or 0
end

local function joinVanilla(src, id)
    local s = state(src)
    id = tostring(id or '')
    if not s then return { ok = false, error = Lp(src, 'fac.character_not_loaded') } end
    if s.id then return { ok = false, error = Lp(src, 'fac.you_are_already_in_a_faction') } end
    if not isVanillaId(id) then return { ok = false, error = Lp(src, 'fac.that_faction_is_invitation_only') } end
    local left = cooldownLeft(s.cid)
    if left > 0 then
        return { ok = false, error = Lp(src, 'fac.rejoin_wait', { h = left // 3600, m = (left % 3600) // 60 }) }
    end
    local low = lowestRank(id)
    x('INSERT INTO bs_faction_members(character_id,faction_id,rank) VALUES(?,?,?)', { s.cid, id, low })
    local v = one('SELECT reputation FROM bs_faction_reputation WHERE character_id=? AND faction_id=? LIMIT 1', { s.cid, id })
    s.id, s.rank, s.rep = id, low, v and tonumber(v.reputation) or 0
    sync(src)
    return { ok = true, label = Registry[id].label }
end

local function leaveAny(src)
    local s = state(src)
    if s and s.id and isVanillaId(s.id) then
        if sanctioned(s.id, 'leave') then return { ok = false, error = Lp(src, 'fac.your_faction_is_sanctioned_membershi') } end
        if psanctioned(s.cid, 'leave_lock') then return { ok = false, error = Lp(src, 'fac.you_are_sanctioned_you_cannot_leave') } end
        local cd = math.floor(tonumber(Factions.Settings.vanillaJoinCooldown) or 0)
        if cd > 0 then
            x('INSERT INTO bs_faction_cooldowns(character_id,until_ts) VALUES(?,?) ON DUPLICATE KEY UPDATE until_ts=VALUES(until_ts)', { s.cid, os.time() + cd })
        end
        return kickOwnerless(src, s)
    end
    return leave(src)
end

local function panelPlus(src)
    local r = panel(src)
    if type(r) == 'table' and r.ok then
        local list = {}
        for _, id in ipairs(Factions.Order or {}) do
            local f = Registry[id]
            if f and f.config then list[#list + 1] = { id = id, label = f.label, short = f.short } end
        end
        r.vanilla = list
        local s = state(src)
        r.joinCooldown = s and not s.id and cooldownLeft(s.cid) or 0
    end
    return r
end

BSB.RegisterCallback('factions:join', joinVanilla)
-- Used by the first-join faction picker (bs_tutorial).
exports('JoinVanilla', function(src, id) return joinVanilla(src, id) end)
exports('VanillaMemberCounts', function()
    local out = {}
    for _, r in ipairs(q('SELECT faction_id, COUNT(*) AS n FROM bs_faction_members GROUP BY faction_id') or {}) do
        if isVanillaId(r.faction_id) then out[r.faction_id] = tonumber(r.n) or 0 end
    end
    return out
end)
BSB.RegisterCallback('factions:leave', leaveAny)
BSB.RegisterCallback('factions:leave2', leaveAny)
BSB.RegisterCallback('factions:panel', panelPlus)

-- Reputation from gameplay, for the player's own faction (factions are not tied to classes).
AddEventHandler('bs:hook:player:action', function(player, actionId)
    local src = type(player) == 'table' and tonumber(player.source)
    local m = Factions.ActionRewards and Factions.ActionRewards[actionId]
    if not src or not m then return end
    local s = State[src]
    if not s or not s.id then return end
    if m.faction and m.faction ~= s.id then return end
    if psanctioned(s.cid, 'rep_freeze', true) then return end
    s.rep = math.max(0, math.min(Factions.Settings.maxReputation, (s.rep or 0) + math.floor(tonumber(m.rep) or 0)))
    save(s)
    sync(src)
end)

-- Seed the vanilla factions and move members of renamed ones. Runs every boot, safe to repeat.
CreateThread(function()
    while not Ready do Wait(250) end
    x('CREATE TABLE IF NOT EXISTS bs_faction_cooldowns (character_id INT UNSIGNED NOT NULL, until_ts BIGINT NOT NULL DEFAULT 0, PRIMARY KEY(character_id))')
    local cols = q([[SELECT TABLE_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'faction_id' AND TABLE_NAME LIKE 'bs\_faction\_%']])
    for old, new in pairs(Factions.Renamed or {}) do
        for _, c in ipairs(cols) do
            if c.TABLE_NAME ~= 'bs_faction_registry' then
                pcall(x, ('UPDATE IGNORE `%s` SET faction_id=? WHERE faction_id=?'):format(c.TABLE_NAME), { new, old })
            end
        end
    end
    local gone = {}
    for old in pairs(Factions.Renamed or {}) do gone[#gone + 1] = old end
    for _, old in ipairs(Factions.Removed or {}) do gone[#gone + 1] = old end
    for _, old in ipairs(gone) do
        x('DELETE FROM bs_faction_members WHERE faction_id=?', { old })
        x('DELETE FROM bs_faction_registry WHERE faction_id=? AND is_config=1', { old })
        Registry[old] = nil
    end
    for _, id in ipairs(Factions.Order or {}) do
        local def = Factions.List[id]
        if def then
            x('INSERT INTO bs_faction_registry(faction_id,label,short,is_config) VALUES(?,?,?,1) ON DUPLICATE KEY UPDATE label=VALUES(label), short=VALUES(short), is_config=1', { id, def.label, def.short or '' })
            Registry[id] = Registry[id] or { id = id, owner = nil, description = '', logo = nil }
            Registry[id].label, Registry[id].short, Registry[id].config = def.label, def.short or '', true
        end
    end
    -- Move every faction onto the rank list now (old fixed ranks are copied over the first time).
    for fid in pairs(Registry) do ranksOf(fid) end
    for _, v in ipairs(GetPlayers()) do load(tonumber(v)) end
end)
