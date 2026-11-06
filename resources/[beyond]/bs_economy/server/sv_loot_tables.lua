local function validInteger(n,lo,hi) return type(n)=='number' and n==n and n%1==0 and n>=lo and n<=hi end
local function validate(tbl)
    if type(tbl)~='table' or type(tbl.rolls)~='table' or not validInteger(tbl.rolls.min,0,20) or not validInteger(tbl.rolls.max,tbl.rolls.min,20) or type(tbl.entries)~='table' or #tbl.entries>128 then return false end
    for _,e in ipairs(tbl.entries) do
        if type(e)~='table' or type(e.item)~='string' or not exports.bs_inventory:GetItem(e.item) or not validInteger(e.weight,1,10000) or type(e.amount)~='table' or not validInteger(e.amount[1],1,100) or not validInteger(e.amount[2],e.amount[1],100) then return false end
    end
    return #tbl.entries>0
end
Economy.LootTables.shop=Economy.LootTables.shop or Economy.LootTables.urban
Economy.LootTables.police=Economy.LootTables.police or {rolls={min=0,max=2},entries={
    {item='bandage',amount={1,2},weight=35},{item='scrap_metal',amount={1,3},weight=35},
    {item='armour_plate',amount={1,1},weight=10},{item='att_flashlight',amount={1,1},weight=5},
}}
local custom={}
CreateThread(function()
    while GetResourceState('bs_inventory')~='started' do Wait(500) end
    local raw=LoadResourceFile(GetCurrentResourceName(),'data/loot_tables.json')
    if raw then local ok,v=pcall(json.decode,raw);if ok and type(v)=='table' then for id,t in pairs(v) do if type(id)=='string' and id:match('^[%w_]+$') and validate(t) then custom[id]=t;Economy.LootTables[id]=t end end end end
end)
exports('LootCatalogue',function() local out={};for id,t in pairs(Economy.LootTables) do out[#out+1]={id=id,rolls=t.rolls,entries=t.entries} end;table.sort(out,function(a,b)return a.id<b.id end);return out end)
exports('ConfigExt',function(src,action,payload)
    if not IsPlayerAceAllowed(src,'bs.admin') and not IsPlayerAceAllowed(src,'bs.superadmin') then return {ok=false,error='Not allowed'} end
    if action=='get' then
        local items={};for id,d in pairs(exports.bs_inventory:GetItems()) do items[#items+1]={id=id,label=d.label or id} end
        table.sort(items,function(a,b)return a.id<b.id end)
        return {ok=true,tables=exports.bs_economy:LootCatalogue(),items=items}
    end
    if action=='save' and type(payload)=='table' and type(payload.id)=='string' and #payload.id<=64 and payload.id:match('^[%w_]+$') and validate(payload.table) then
        local nextCustom={};for k,v in pairs(custom) do nextCustom[k]=v end;nextCustom[payload.id]=payload.table
        if not SaveResourceFile(GetCurrentResourceName(),'data/loot_tables.json',json.encode(nextCustom),-1) then return {ok=false,error='Unable to save loot table'} end
        custom=nextCustom;Economy.LootTables[payload.id]=payload.table;return {ok=true}
    end
    return {ok=false,error='Check item names, roll limits and positive weights'}
end)
