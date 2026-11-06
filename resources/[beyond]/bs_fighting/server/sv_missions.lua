-- bs_fighting - sparring with trainers and the Mission Log entries (learn a style, then its zombie trial).

local Spar, T = Fighting.Spar, Fighting.Trials
local byId = {}
for _, t in ipairs(Fighting.Trainers) do byId[t.id] = t end

local function trainerPos(t)
    if t.at then return vector3(t.at[1] + 0.0, t.at[2] + 0.0, t.at[3] + 0.0) end
    for _, z in ipairs((Zones and Zones.FactionSafe) or {}) do
        if z.id == t.zone then
            local o = t.offset or { 0.0, 0.0 }
            return vector3(z.coords.x + o[1], z.coords.y + o[2], z.coords.z)
        end
    end
end

local function near(src, t, r)
    local pos = trainerPos(t)
    local ped = GetPlayerPed(src)
    if not pos or not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    return #(vector2(c.x, c.y) - vector2(pos.x, pos.y)) <= r
end

local function teaches(t, style)
    for _, s in ipairs(t.teaches or {}) do if s == style then return true end end
    return false
end

local function notify(src, kind, key, vars)
    TriggerClientEvent('bs:ui:notify', src, { type = kind, message = Lp(src, key, vars), duration = 4000 })
end

RegisterNetEvent('bs:fighting:sparStart', function(tid, style)
    local src = source
    local st = FS[src]
    local t = byId[tostring(tid or '')]
    if not Fighting.Settings.enabled or not st or not t or type(style) ~= 'string' then return end
    local def = Fighting.Styles[style]
    if not def or def.free or not teaches(t, style) then return end
    if st.styles[style] then return notify(src, 'info', 'spar.known') end
    if st.spar then return end
    if not near(src, t, 8.0) then return end
    local ok, lvl = pcall(function() return exports.bs_skills:GetSkillLevel(src, 'fighting') end)
    lvl = ok and tonumber(lvl) or 0
    if lvl < (def.minLevel or 0) then
        return notify(src, 'warn', 'spar.need_level', { need = def.minLevel, have = lvl })
    end
    local need = Fighting.IsAdvanced(style) and Spar.hitsAdvanced or Spar.hits
    st.spar = { tid = t.id, style = style, hits = 0, need = need, started = GetGameTimer(), last = 0 }
    TriggerClientEvent('bs:fighting:sparBegin', src, t.id, style, need, Spar.seconds)
end)

RegisterNetEvent('bs:fighting:sparHit', function(tid)
    local src = source
    local st = FS[src]
    local sp = st and st.spar
    if not sp or sp.tid ~= tid then return end
    local t = byId[sp.tid]
    local now = GetGameTimer()
    if now - sp.started > (Spar.seconds + 5) * 1000 then st.spar = nil; return end
    if now - sp.last < Spar.minGapMs then return end
    if not near(src, t, Spar.range) then return end
    sp.last = now
    sp.hits = sp.hits + 1
    TriggerClientEvent('bs:fighting:sparProgress', src, sp.hits, sp.need)
    if sp.hits >= sp.need then
        st.spar = nil
        FS.Learn(src, sp.style)
        FS.XP(src, Fighting.Settings.xpSpar)
        TriggerClientEvent('bs:fighting:sparResult', src, true, sp.style)
    end
end)

RegisterNetEvent('bs:fighting:sparEnd', function()
    local src = source
    local st = FS[src]
    if not st or not st.spar then return end
    st.spar = nil
    TriggerClientEvent('bs:fighting:sparResult', src, false)
end)

-- Mission Log (bs_inventory)

local function need(style) return Fighting.IsAdvanced(style) and T.advancedKills or T.basicKills end

exports('MissionLogList', function(src)
    local st = FS[src]
    if not st or not Fighting.Settings.enabled then return {} end
    local group = Lp(src, 'mission.group')
    local out = {}
    for _, id in ipairs(Fighting.StyleIds()) do
        local def = Fighting.Styles[id]
        if not def.free then
            local name = Lp(src, 'style.' .. id)
            if not st.styles[id] then
                out[#out + 1] = {
                    id = 'learn:' .. id, group = group, noClaim = true, complete = false,
                    title = Lp(src, 'mission.learn', { style = name }),
                    steps = {
                        { label = Lp(src, def.basic and 'mission.step_find_basic' or 'mission.step_find_hidden'), done = false },
                        { label = Lp(src, 'mission.step_spar', { n = def.basic and Spar.hits or Spar.hitsAdvanced }), done = false },
                    },
                    hint = Lp(src, 'hint.' .. id) .. ((def.minLevel or 0) > 0 and (' ' .. Lp(src, 'mission.min_level', { n = def.minLevel })) or ''),
                }
            else
                local tr = st.trials[id] or { n = 0 }
                local n = need(id)
                out[#out + 1] = {
                    id = 'trial:' .. id, group = group,
                    title = Lp(src, 'mission.trial', { style = name }),
                    steps = {
                        { label = Lp(src, 'mission.step_learned', { style = name }), done = true },
                        { label = Lp(src, 'mission.step_kill', { n = math.min(tr.n or 0, n), need = n, style = name }), done = tr.done == true },
                    },
                    hint = Lp(src, 'mission.trial_hint', { xp = Fighting.Settings.xpTrial, money = T.money }),
                    complete = tr.done == true, claimed = tr.claimed == true,
                }
            end
        end
    end
    return out
end)

exports('MissionLogClaim', function(src, id)
    local st = FS[src]
    local style = type(id) == 'string' and id:match('^trial:(.+)$')
    local tr = st and style and st.trials[style]
    if not tr or not tr.done or tr.claimed then return { ok = false, error = Lp(src, 'mission.cant_claim') } end
    tr.claimed = true
    FS.Save(src)
    if (T.money or 0) > 0 then pcall(function() exports.bs_core:AddMoney(src, 'cash', T.money, 'fighting_trial_' .. style) end) end
    FS.XP(src, Fighting.Settings.xpTrial)
    return { ok = true }
end)

exports('MissionLogAccept', function() return { ok = false } end)

local function registerLog()
    if GetResourceState('bs_inventory') == 'started' then
        pcall(function() exports.bs_inventory:RegisterMissionSource(GetCurrentResourceName()) end)
    end
end
CreateThread(function() Wait(1500); registerLog() end)
AddEventHandler('onResourceStart', function(res) if res == 'bs_inventory' then Wait(1000); registerLog() end end)
