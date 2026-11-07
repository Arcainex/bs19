-- BS19 dynamic books, alongside legacy Config.Books PNG books.
-- DB access uses oxmysql's await exports, only server callbacks are exposed.
local function validId(s) return type(s)=='string' and #s>0 and #s<=60 and s:match('^[a-z0-9_]+$')~=nil end
local function trim(s,max) if type(s)~='string' then return '' end return s:sub(1,max) end
local function image(s)
 if type(s)~='string' then return nil end
 if s=='' then return s end
 if #s<=500 and s:match('^https://') and not s:find('[%s<>]') then return s end
 if #s<=650000 and s:match('^data:image/jpeg;base64,[A-Za-z0-9+/=]+$') then return s end
 return nil
end
local function staff(src)
 if GetResourceState('bs_admin')~='started' then return false end
 local ok,allowed=pcall(function()return exports.bs_admin:IsAdmin(src) end)
 return ok and allowed == true
end
local function query(sql,params) return exports.oxmysql:query_async(sql,params or {}) end
local function rows(id) return query('SELECT id,title,author,description,cover,pages FROM bs_books_custom WHERE id=? LIMIT 1',{id}) end
local function decode(row)
 if not row then return nil end
 local ok,p=pcall(json.decode,row.pages or '[]');row.pages=ok and type(p)=='table' and p or {};return row
end
local function validate(b)
 if type(b)~='table' or not validId(b.id) then return nil,'Ungültige Buch-ID' end
 if Config.Books[b.id] then return nil,'ID ist für ein klassisches Buch reserviert' end
 local title=trim(b.title,100);if title=='' then return nil,'Titel fehlt' end
 local cover=image(b.cover);if not cover then return nil,'Cover muss ein HTTPS-Link oder hochgeladenes Bild sein' end
 local layout=({standard=true,clean=true,rusty=true,torn=true})[b.layout] and b.layout or 'standard'
 local background=image(b.background);if not background then return nil,'Ungültiger Seitenhintergrund' end
 if type(b.pages)~='table' or #b.pages<1 or #b.pages>80 then return nil,'1–80 Seiten erlaubt' end
 local pages={}
 for i,p in ipairs(b.pages) do
  if type(p)~='table' then return nil,'Ungültige Seite' end
  local url=image(p.image);if not url then return nil,'Seitenbild ungültig (JPEG max. ca. 480 KB oder HTTPS)' end
  local color=type(p.color)=='string' and p.color:match('^#[0-9a-fA-F]+$') and #p.color==7 and p.color or '#352719'
  pages[i]={source='dynamic',text=trim(p.text,4500),image=url,font=({small=true,normal=true,large=true})[p.font] and p.font or 'normal',fontFamily=({georgia=true,arial=true,courier=true,caveat=true,kalam=true,cinzel=true})[p.fontFamily] and p.fontFamily or 'georgia',fontSize=math.max(12,math.min(24,math.floor(tonumber(p.fontSize) or ({small=13,normal=17,large=23})[p.font] or 17))),align=({left=true,center=true,right=true})[p.align] and p.align or 'left',color=color,layout=layout,background=i==1 and background or ''}
 end
 return {id=b.id,title=title,author=trim(b.author,100),description=trim(b.description,600),cover=cover,pages=pages}
end
CreateThread(function()
 local ok,err=pcall(function()query([[CREATE TABLE IF NOT EXISTS bs_books_custom (
 id VARCHAR(60) NOT NULL PRIMARY KEY, title VARCHAR(100) NOT NULL,
 author VARCHAR(100) NOT NULL DEFAULT '', description VARCHAR(600) NOT NULL DEFAULT '',
 cover LONGTEXT NOT NULL, pages LONGTEXT NOT NULL
 ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]) end)
 if ok then pcall(function()query('ALTER TABLE bs_books_custom MODIFY COLUMN cover LONGTEXT NOT NULL',{}) end) end
 if not ok then print('^1[BS BOOKS] Datenbankfehler: '..tostring(err)..'^7') end
end)
BSB.RegisterCallback('books:admin',function(src,action,args)
 if not staff(src) then return {ok=false,error='Keine Adminrechte'} end
 args=type(args)=='table' and args or {}
 if action=='list' then
  local r=query('SELECT id,title,author FROM bs_books_custom ORDER BY title',{})
  return {ok=true,books=r or {}}
 elseif action=='get' then
  if not validId(args.id) then return {ok=false,error='Ungültige ID'} end
  local r=rows(args.id);local b=decode(r and r[1]);return b and {ok=true,book=b} or {ok=false,error='Buch nicht gefunden'}
 elseif action=='save' then
  local b,err=validate(args.book);if not b then return {ok=false,error=err} end
  query([[INSERT INTO bs_books_custom (id,title,author,description,cover,pages) VALUES (?,?,?,?,?,?)
  ON DUPLICATE KEY UPDATE title=VALUES(title),author=VALUES(author),description=VALUES(description),cover=VALUES(cover),pages=VALUES(pages)]],
  {b.id,b.title,b.author,b.description,b.cover,json.encode(b.pages)})
  print(('[BS BOOKS] Admin %s saved %s'):format(src,b.id))
  return {ok=true}
 elseif action=='delete' then
  if not validId(args.id) then return {ok=false,error='Ungültige ID'} end
  query('DELETE FROM bs_books_custom WHERE id=?',{args.id})
  print(('[BS BOOKS] Admin %s deleted %s'):format(src,args.id))
  return {ok=true}
 elseif action=='give' then
  local target=tonumber(args.target)
  if not validId(args.id) or not target or not GetPlayerName(target) then return {ok=false,error='Buch/Spieler ungültig'} end
  local r=rows(args.id);if not r or not r[1] then return {ok=false,error='Buch existiert nicht'} end
  local ok,result=pcall(function()return exports.bs_inventory:GiveItem(target,'book',1,{bookId=args.id, bookTitle=r[1].title}) end)
  if not ok or result==false then return {ok=false,error='Inventar konnte Buch nicht vergeben'} end
  print(('[BS BOOKS] Admin %s gave %s to %s'):format(src,args.id,target))
  return {ok=true}
 end
 return {ok=false,error='Unbekannte Aktion'}
end)
-- Triggered by the validated inventory use callback, never exposed as network event.
AddEventHandler('bs:books:use',function(src,itemName,slot)
 src=tonumber(src);slot=tonumber(slot)
 if not src or not GetPlayerName(src) or GetResourceState('bs_inventory')~='started' then return end
 if Config.Books[itemName] then
  TriggerClientEvent('bs_books:client:open',src,itemName)
  return
 end
 if itemName~='book' or not slot then return end
 local entries=exports.bs_inventory:ItemMetaList(src,'book')
 for _,e in ipairs(entries or {}) do
  if tonumber(e.slot)==slot then
   local id=e.metadata and e.metadata.bookId
   if not validId(id) then return end
   local r=rows(id);local b=decode(r and r[1]);if not b then return end
   TriggerClientEvent('bs_books:client:open',src,id,{title=b.title,prop='book',size={width=800,height=600},pages=b.pages})
   return
  end
 end
end)
