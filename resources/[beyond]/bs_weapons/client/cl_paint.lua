-- Experimental full-colour weapon paint (see config_paint.lua for the limits).
-- Each painted texture part gets a small DUI page that draws the paint; its runtime texture replaces the weapon's
-- own diffuse texture on this client through AddReplaceTexture.
local P=Weapons.Paint or {}
local RES=GetCurrentResourceName()
local slots,replaced,partsCache,names={}, {}, {}, {}
local preview
for weapon in pairs(P.models or {})do names[GetHashKey(weapon)]=weapon end

local function modelName(weapon)
    local m=P.models and P.models[weapon]
    if not m then return nil end
    if GetHashKey(m)~=GetWeapontypeModel(GetHashKey(weapon))then return nil end
    return m
end
local function textureExists(txd,txn)
    local ok,res=pcall(GetTextureResolution,txd,txn)
    return ok and res and res.x and res.x>4.0
end
local function candidates(m)
    local b=m:gsub('^w_%a%a_','')
    local out,seen={}, {}
    for _,pattern in ipairs(P.probe or {})do
        local txn=pattern:gsub('%%m',m):gsub('%%b',b)
        if not seen[txn]then seen[txn]=true;out[#out+1]=txn end
    end
    return out
end
local function loadDict(m)
    if HasStreamedTextureDictLoaded(m)then return true end
    RequestStreamedTextureDict(m,false)
    local deadline=GetGameTimer()+1500
    while not HasStreamedTextureDictLoaded(m)and GetGameTimer()<deadline do Wait(20)end
    return HasStreamedTextureDictLoaded(m)
end
local function labelFor(txn,index)
    if txn:find('mag')then return 'Magazine'end
    if index==1 then return 'Body'end
    return 'Detail '..index
end
-- Texture parts that can be painted on this weapon: configured list first, else a probe of common names.
function Weapons.PaintParts(weapon)
    if partsCache[weapon]~=nil then return partsCache[weapon]or {}end
    local m=modelName(weapon)
    if not P.enabled or not m then partsCache[weapon]=false;return {}end
    local list={}
    local known=P.textures and (P.textures[m]or P.textures[weapon])
    if known then
        for _,t in ipairs(known)do list[#list+1]={id=t.txn,label=t.label or labelFor(t.txn,#list+1)}end
    else
        loadDict(m)
        for _,txn in ipairs(candidates(m))do
            if textureExists(m,txn)then list[#list+1]={id=txn,label=labelFor(txn,#list+1)}end
            if #list>=(P.maxParts or 4)then break end
        end
    end
    partsCache[weapon]=#list>0 and list or false
    return list
end

local function createSlot(i)
    local size=math.floor(math.max(128,math.min(1024,P.textureSize or 512)))
    local s={txdName='bs_paint_'..i,rev=0,size=size}
    s.txd=CreateRuntimeTxd(s.txdName)
    s.dui=CreateDui(('https://cfx-nui-%s/html/paint.html?resource=%s&slot=%d&size=%d'):format(RES,RES,i,size),size,size)
    s.texture=CreateRuntimeTextureFromDuiHandle(s.txd,'paint',GetDuiHandle(s.dui))
    slots[i]=s
    return s
end
local function release(key)
    local i=replaced[key];if not i then return end
    local s=slots[i]
    if s and s.model then RemoveReplaceTexture(s.model,s.txn)end
    if s then s.key,s.model,s.txn,s.sig,s.live=nil,nil,nil,nil,false end
    replaced[key]=nil
end
local function send(i)
    local s=slots[i]
    if not s or not s.ready or not s.part then return end
    s.rev=s.rev+1
    SendDuiMessage(s.dui,json.encode({slot=i,rev=s.rev,part=s.part,seed=s.key}))
end
local function show(model,txn,part)
    local key=model..':'..txn
    local sig=json.encode(part)
    local i=replaced[key]
    if i and slots[i].sig==sig then return end
    if not i then
        for n=1,(P.maxSlots or 6)do if not slots[n]or not slots[n].key then i=n;break end end
        if not i then return end
        if not slots[i]then createSlot(i)end
        replaced[key]=i
    end
    local s=slots[i]
    s.key,s.model,s.txn,s.sig,s.part=key,model,txn,sig,part
    send(i)
end
RegisterNUICallback('paintPageReady',function(data,cb)
    local i=tonumber(data and data.slot);local s=i and slots[i]
    if s then s.ready=true;send(i)end
    cb({ok=true})
end)
RegisterNUICallback('paintPainted',function(data,cb)
    local i=tonumber(data and data.slot);local s=i and slots[i]
    -- Swap only after the first frame is painted, so the gun never flashes blank.
    if s and s.key and not s.live and tonumber(data.rev)==s.rev then
        AddReplaceTexture(s.model,s.txn,s.txdName,'paint');s.live=true
    end
    cb({ok=true})
end)

-- Which paint each nearby model should show. A model is painted only when every nearby copy carries the same paint.
local function desired()
    local want,holders={}, {}
    local studio=Weapons.InspectionObject and Weapons.InspectionObject()
    if preview and studio then
        local m=modelName(preview.weapon)
        if m and preview.paint then want[m]=preview.paint elseif m then want[m]=false end
    end
    local origin=GetEntityCoords(PlayerPedId())
    for _,player in ipairs(GetActivePlayers())do
        local ped=GetPlayerPed(player)
        if ped~=0 and DoesEntityExist(ped)and not IsEntityDead(ped)and #(GetEntityCoords(ped)-origin)<=(P.applyDistance or 30.0)then
            local weapon=names[GetSelectedPedWeapon(ped)]
            local m=weapon and modelName(weapon)
            if m and want[m]==nil then
                local st=Player(GetPlayerServerId(player)).state.bsWeaponPaint
                local paint=st and st.weapon==weapon and Weapons.ValidPaint(st.paint)or nil
                holders[m]=holders[m]or {}
                holders[m][#holders[m]+1]={paint=paint,sig=paint and json.encode(paint)or ''}
            end
        end
    end
    for m,list in pairs(holders)do
        local same=true
        for _,h in ipairs(list)do if h.sig~=list[1].sig then same=false end end
        if same and list[1].paint then want[m]=list[1].paint end
    end
    return want
end
local function update()
    if not P.enabled then
        for key in pairs(replaced)do release(key)end
        return
    end
    local want=desired()
    local keep={}
    for m,paint in pairs(want)do
        if paint then for txn,part in pairs(paint.parts or {})do keep[m..':'..txn]=true;show(m,txn,part)end end
    end
    for key in pairs(replaced)do if not keep[key]then release(key)end end
end
CreateThread(function()
    while true do
        Wait((preview or next(replaced))and 250 or 600)
        local ok,err=pcall(update)
        if not ok then print('[bs_weapons] paint: '..tostring(err))end
    end
end)

-- Workbench preview: nil clears it.
function Weapons.PreviewPaint(weapon,paint)
    if paint==nil then preview=nil
    else
        local clean=paint==false and false or Weapons.ValidPaint(paint)
        if paint~=false and not clean then return false end
        preview={weapon=weapon,paint=clean or false}
    end
    pcall(update)
    return true
end

-- /weaponpaintprobe [extra texture names...]: which texture names of the held weapon's model can be painted.
RegisterCommand('weaponpaintprobe',function(_,args)
    CreateThread(function()
        local hash=GetSelectedPedWeapon(PlayerPedId())
        local weapon=names[hash]
        if not weapon then print('[bs_weapons] paint probe: this weapon has no model line in config_paint.lua');return end
        local m=P.models[weapon]
        print(('[bs_weapons] paint probe %s -> model %s (%s)'):format(weapon,m,modelName(weapon)and 'matches the game'or 'DOES NOT match the game'))
        loadDict(m)
        local list=candidates(m)
        for _,a in ipairs(args)do list[#list+1]=a end
        for _,txn in ipairs(list)do
            local ok,res=pcall(GetTextureResolution,m,txn)
            print(('  %-34s %s'):format(txn,ok and res and res.x>4.0 and ('FOUND %dx%d'):format(math.floor(res.x),math.floor(res.y))or 'no'))
        end
        partsCache[weapon]=nil
        print('  Add found names to Weapons.Paint.textures.'..m..' = { {txn=\'name\', label=\'Body\'} }')
    end)
end,false)

AddEventHandler('onResourceStop',function(name)
    if name~=RES then return end
    for key in pairs(replaced)do release(key)end
    for _,s in pairs(slots)do if s.dui then DestroyDui(s.dui)end end
end)
