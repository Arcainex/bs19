-- bs_fighting - walker swing escape. bs_zombies counts a swing as missed while bs_skills says we are dodging,
-- so a good guard asks bs_skills for a short evade window (GrantEvade) instead of touching the zombie code.

local G = Fighting.Grab

local function grantEvade(ms)
    local ok = pcall(function() exports.bs_skills:GrantEvade(ms) end)
    return ok
end

local function windowMs()
    local st = Fight.StyleDef()
    local w = G.baseWindowMs + (Fight.level or 0) * G.perLevelMs
    w = w * (st.grab or 1.0)
    if Fight.Has('grp_escape') then w = w * 1.3 end
    if Fight.Has('fight_grab_breaker') then w = w * 1.5 end
    return math.min(G.maxWindowMs, w)
end

local function stamina()
    local ok, n = pcall(function() return exports.bs_core:GetNeeds() end)
    return (ok and type(n) == 'table' and tonumber(n.stamina)) or 100.0
end

local function shove()
    local t = Fight.Targets(2.2, 90.0, false, false)[1]
    if not t or t.kind ~= 'zombie' then return end
    local me = PlayerPedId()
    local a = FightAnim.Play(me, 'shove', { flag = 48 })
    FightAnim.Guard(a)
    local f = GetEntityForwardVector(me)
    FightReact.Request(t.ped, 'down', 5.0, f.x, f.y)
    FightHud.Impact(0.6)
    if Fight.Has('fight_grab_breaker') then
        local _, w = Fight.WeaponClass(me)
        TriggerServerEvent('bs:z:dmg', t.id, 'torso', 0, w, t.dist)
    end
end

local function escaped(kind)
    pcall(function() exports.bs_core:AdjustStamina(-G.staminaCost) end)
    grantEvade(G.evadeMs)
    FightHud.Flash(kind)
    Fight.counterUntil = GetGameTimer() + Fighting.Settings.counterWindowMs
    TriggerServerEvent('bs:fighting:escaped')
    shove()
end

CreateThread(function()
    local was = false
    while true do
        local wait = 60
        if Fighting.Settings.enabled and Fighting.Zombies.grabEscape and GetResourceState('bs_zombies') == 'started' then
            local ok, attacked = pcall(function() return exports.bs_zombies:IsBeingAttacked() end)
            attacked = ok and attacked == true
            if attacked and not was then
                local t0 = GetGameTimer()
                local me = PlayerPedId()
                if Fight.CanFight(me) and stamina() >= G.staminaCost then
                    if Fight.blocking and t0 - Fight.blockAt > 150 then
                        -- just holding the guard: a chance, better with skill
                        local chance = math.min(G.guardMax, G.guardChance + (Fight.level or 0) * G.guardPerLevel)
                        if math.random() < chance then escaped('block') end
                    else
                        local w = windowMs()
                        while GetGameTimer() - t0 <= w do
                            if Fight.blocking and Fight.blockAt >= t0 - 120 then escaped('escape') break end
                            Wait(0)
                        end
                    end
                end
            end
            was = attacked
            if attacked then wait = 0 end
        end
        Wait(wait)
    end
end)
