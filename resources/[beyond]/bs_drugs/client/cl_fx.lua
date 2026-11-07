-- Screen and camera effects while drugs are active. Names/strengths: Drugs.Fx in config.
-- Strongest active drug owns the main timecycle, the next one adds its subtle "extra" layer.

local Fx = Drugs.Fx
local layers = {
    main  = { name = nil, cur = 0.0 },
    extra = { name = nil, cur = 0.0 },
}
local shake = { type = nil, amp = 0.0 }
local nextPulse = {}   -- key -> game timer
local played = {}      -- AnimpostFX names we started, to stop on cleanup

local function setLayer(key, name, v)
    if key == 'main' then
        if name then SetTimecycleModifier(name); SetTimecycleModifierStrength(v) else ClearTimecycleModifier() end
    else
        if name then SetExtraTimecycleModifier(name); SetExtraTimecycleModifierStrength(v) else ClearExtraTimecycleModifier() end
    end
end

-- Move a layer toward (name, target). A name swap fades out first, then fades the new one in.
local function ramp(key, name, target, step)
    local l = layers[key]
    if l.name and l.name ~= name then target = 0.0 end
    if not l.name and name and target > 0 then l.name = name; l.cur = 0.0 end
    if not l.name then return false end
    if l.cur < target then l.cur = math.min(target, l.cur + step)
    elseif l.cur > target then l.cur = math.max(target, l.cur - step) end
    if l.cur <= 0.0 then setLayer(key, nil); l.name = nil; l.cur = 0.0; return false end
    setLayer(key, l.name, l.cur)
    return true
end

local function setShake(sType, amp)
    if amp <= 0.0 or not sType then
        if shake.type then StopGameplayCamShaking(false); shake.type, shake.amp = nil, 0.0 end
        return
    end
    if shake.type ~= sType then
        if shake.type then StopGameplayCamShaking(true) end
        ShakeGameplayCam(sType, amp); shake.type, shake.amp = sType, amp
    elseif math.abs(shake.amp - amp) > 0.001 then
        SetGameplayCamShakeAmplitude(amp); shake.amp = amp
    end
end

local function pulse(key, p, t)
    if not p then return end
    local at = nextPulse[key]
    if not at then nextPulse[key] = t + p.every * 1000; return end   -- first one after a full interval
    if t >= at then
        AnimpostfxPlay(p.fx, p.ms, false); played[p.fx] = true
        nextPulse[key] = t + p.every * 1000
    end
end

local function stopAll()
    for name in pairs(played) do AnimpostfxStop(name) end
    played = {}
    setLayer('main', nil); setLayer('extra', nil)
    layers.main.name, layers.main.cur, layers.extra.name, layers.extra.cur = nil, 0.0, nil, 0.0
    setShake(nil, 0.0)
    nextPulse = {}
end

CreateThread(function()
    local step = Fx.tickMs / Fx.fadeMs
    local wasDead = false
    while true do
        local t = GetGameTimer()
        local ped = PlayerPedId()
        local dead = IsEntityDead(ped)
        if dead and not wasDead then for name in pairs(played) do AnimpostfxStop(name) end; played = {} end
        wasDead = dead

        -- Rank active drugs by effect strength.
        local list = {}
        if not dead and DrugActive then
            for drug, e in pairs(DrugActive) do
                local c = Fx[drug]
                if c and t < e.untilAt then
                    list[#list + 1] = { drug = drug, c = c, s = e.s, bad = e.q == 'bad', w = (c.str or c.extraStr or 0) * e.s }
                end
            end
        end
        table.sort(list, function(a, b) return a.w > b.w end)

        local mainD
        for _, d in ipairs(list) do if d.c.tc then mainD = d; break end end
        local extraD
        for _, d in ipairs(list) do if d ~= mainD and d.c.extra then extraD = d; break end end

        local busy = ramp('main', mainD and mainD.c.tc, mainD and math.min(1.0, mainD.c.str * mainD.s) or 0.0, step)
        busy = ramp('extra', extraD and extraD.c.extra, extraD and math.min(1.0, extraD.c.extraStr * extraD.s) or 0.0, step) or busy

        -- One camera shake: the biggest of drugs and withdrawal.
        local sType, amp = nil, 0.0
        for _, d in ipairs(list) do
            local a = (d.c.shake or 0.0) * d.s
            if a > amp then sType, amp = d.c.shakeType, a end
        end
        local wl = not dead and Drugs.Withdrawal[DrugWithdrawal and DrugWithdrawal() or 0]
        if wl and wl.shake > amp then sType, amp = Drugs.Withdrawal.shakeType, wl.shake end
        setShake(sType, amp)

        -- Pulses; cut drugs glitch now and then.
        local anyBad = false
        local seen = {}
        for _, d in ipairs(list) do
            pulse(d.drug, d.c.pulse, t); seen[d.drug] = true
            if d.bad then anyBad = true end
        end
        if anyBad then pulse('bad', Fx.badGlitch, t); seen.bad = true end
        for k in pairs(nextPulse) do if not seen[k] then nextPulse[k] = nil end end

        Wait((busy or #list > 0) and Fx.tickMs or 500)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stopAll() end
end)
