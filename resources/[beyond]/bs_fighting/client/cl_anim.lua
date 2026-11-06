-- bs_fighting - playing clips so they finish cleanly: known length, timed stop, blend out, watchdog.

FightAnim = { dur = {} }
local active = {}
local retryAt,warming,warmAt={},{},{}
local function owns(a) return a and active[a.ped] and active[a.ped][a.dict .. "/" .. a.clip] == a end

local function loadDict(dict)
    if not dict or dict == '' or not DoesAnimDictExist(dict) then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(0) end
    return HasAnimDictLoaded(dict)
end
FightAnim.Load = loadDict

local function clipOf(id)
    local c = Fighting.CustomAnims
    if c and c.enabled and type(c.map) == 'table' and c.map[id] and c.map[id].dict then
        return c.map[id].dict, c.map[id].clip, true
    end
    local m = Fighting.Moves[id]
    if m and m.clip then return m.clip[1], m.clip[2] end
    local p = Fighting.Poses[id]
    if p then return p[1], p[2] end
end
FightAnim.ClipOf = clipOf

-- Length in ms, cached. 0 = missing.
function FightAnim.Length(dict, clip)
    local key = dict .. '/' .. clip
    if FightAnim.dur[key] and FightAnim.dur[key]>0 then return FightAnim.dur[key] end
    if GetGameTimer()<(retryAt[key]or 0)then return 0 end
    if not loadDict(dict) then retryAt[key]=GetGameTimer()+1000;return 0 end
    local ok, d = pcall(GetAnimDuration, dict, clip)
    local ms = (ok and type(d) == 'number') and math.floor(d * 1000) or 0
    FightAnim.dur[key] = ms
    retryAt[key]=ms>0 and nil or GetGameTimer()+1000
    return ms
end

-- Do not take native weapon melee away while its replacement clips are still streaming.
function FightAnim.WeaponReady(style,class)
    local ids={Fighting.MoveFor(style,class,'light',1),Fighting.MoveFor(style,class,'heavy')}
    local ready=true
    for _,id in ipairs(ids)do
        local dict,clip=clipOf(id)
        if not dict or (FightAnim.dur[dict..'/'..clip]or 0)<=0 then ready=false end
    end
    if ready then return true end
    local key=tostring(style)..':'..tostring(class)
    if not warming[key]and GetGameTimer()>=(warmAt[key]or 0)then
        warming[key]=true;warmAt[key]=GetGameTimer()+1500
        CreateThread(function()
            local ok,err=pcall(function()
                for _,id in ipairs(ids)do local dict,clip=clipOf(id);if dict then FightAnim.Length(dict,clip)end end
            end)
            warming[key]=nil
            if not ok then print('[bs_fighting] melee animation load: '..tostring(err))end
        end)
    end
    return false
end

-- Preload everything once so the first swing doesn't hitch.
CreateThread(function()
    Wait(3000)
    for id in pairs(Fighting.Moves) do
        local d, c = clipOf(id)
        if d then FightAnim.Length(d, c) end
        Wait(0)
    end
    for id in pairs(Fighting.Poses) do
        local d, c = clipOf(id)
        if d then FightAnim.Length(d, c) end
    end
end)

-- Plays a move or pose. Returns { dict, clip, ms } (ms = how long it plays) or nil if the clip is missing.
-- flag 0 = full body, committed. 48 = upper body, you keep walking. 49 = upper body loop.
function FightAnim.Play(ped, id, opts)
    opts = opts or {}
    local dict, clip = clipOf(id)
    if not dict then return nil end
    local len = FightAnim.Length(dict, clip)
    if len <= 0 then return nil end
    local move = Fighting.Moves[id] or {}
    local speed = opts.speed or 1.0
    local portion = opts.portion or move.portion or 1.0
    local flag = opts.flag or 0
    local ms = opts.loop and -1 or math.floor(len * portion / speed)
    TaskPlayAnim(ped, dict, clip, opts.blendIn or 6.0, opts.blendOut or 4.0, ms, flag, opts.start or 0.0, false, false, false)
    local a = { dict = dict, clip = clip, ms = ms, len = len, speed = speed, ped = ped }
    active[ped] = active[ped] or {}
    active[ped][dict .. "/" .. clip] = a
    if speed ~= 1.0 then
        CreateThread(function()
            Wait(0)
            if owns(a) and IsEntityPlayingAnim(ped, dict, clip, 3) then SetEntityAnimSpeed(ped, dict, clip, speed) end
        end)
    end
    return a
end

-- Hit-stop: freeze the clip for a moment, then carry on at its speed.
function FightAnim.Freeze(a, ms)
    if not owns(a) or ms <= 0 then return end
    if not IsEntityPlayingAnim(a.ped, a.dict, a.clip, 3) then return end
    SetEntityAnimSpeed(a.ped, a.dict, a.clip, 0.02)
    SetTimeout(ms, function()
        if owns(a) and DoesEntityExist(a.ped) and IsEntityPlayingAnim(a.ped, a.dict, a.clip, 3) then
            SetEntityAnimSpeed(a.ped, a.dict, a.clip, a.speed or 1.0)
        end
    end)
end

function FightAnim.Stop(a, blend)
    if not owns(a) then return end
    active[a.ped][a.dict .. "/" .. a.clip] = nil
    if DoesEntityExist(a.ped) and IsEntityPlayingAnim(a.ped, a.dict, a.clip, 3) then
        StopAnimTask(a.ped, a.dict, a.clip, blend or 4.0)
    end
end

-- Watchdog: if a clip is still on after its time (frozen, interrupted speed), take it off.
function FightAnim.Guard(a, extraMs)
    if not a or not a.ms or a.ms < 0 then return end
    SetTimeout(a.ms + (extraMs or 350), function() FightAnim.Stop(a, 8.0) end)
end

-- /fightanims (staff): loads every dict and clip in the config and prints what is missing.
RegisterNetEvent('bs:fighting:animCheck', function()
    CreateThread(function()
        local bad, total = {}, 0
        local function check(id)
            local d, c = clipOf(id)
            if not d then return end
            total = total + 1
            FightAnim.dur[d .. '/' .. c] = nil
            if not DoesAnimDictExist(d) then bad[#bad + 1] = id .. ': dict missing ' .. d
            elseif FightAnim.Length(d, c) <= 0 then bad[#bad + 1] = id .. ': clip missing ' .. d .. ' / ' .. c end
        end
        for id in pairs(Fighting.Moves) do check(id) end
        for id in pairs(Fighting.Poses) do check(id) end
        print(('[bs_fighting] anim check: %d clips, %d missing'):format(total, #bad))
        for _, line in ipairs(bad) do print('  MISSING ' .. line) end
        TriggerEvent('bs:ui:notify', { type = #bad == 0 and 'success' or 'warn',
            message = L('fight.anim_check', { n = total, bad = #bad }), duration = 6000 })
    end)
end)

-- Debug menu (bs_fpdebug): move slots per style, play one in place, list clips that fail to load.
exports('DebugData', function()
    local styles, extra = {}, {}
    for id, st in pairs(Fighting.Styles) do
        local slots = {}
        for i, m in ipairs(st.chain or {}) do slots[#slots + 1] = { 'light' .. i, m } end
        slots[#slots + 1] = { 'heavy', st.heavy }
        slots[#slots + 1] = { 'kick', st.kick }
        if st.parryDo and st.parryDo ~= 'none' and st.parryDo ~= 'disarm' then slots[#slots + 1] = { 'parry', st.parryDo } end
        slots[#slots + 1] = { 'stomp', 'stomp' }
        slots[#slots + 1] = { 'takedown', 'takedown' }
        styles[#styles + 1] = { id = id, order = st.order or 0, slots = slots }
    end
    table.sort(styles, function(a, b) return a.order < b.order end)
    for id in pairs(Fighting.Moves) do if id:sub(1, 1) == 'w' and id:sub(3, 3) == '_' then extra[#extra + 1] = id end end
    table.sort(extra)
    local bad = {}
    for id in pairs(Fighting.Moves) do
        local d, c = clipOf(id)
        if d and FightAnim.Length(d, c) <= 0 then bad[#bad + 1] = id .. ' ' .. d .. '/' .. c end
    end
    table.sort(bad)
    return { styles = styles, weapon = extra, failed = bad }
end)

exports('DebugPlay', function(id)
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    local a = FightAnim.Play(ped, id, { flag = 0 })
    if a then FightAnim.Guard(a, 600) end
    return a ~= nil
end)
