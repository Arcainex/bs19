-- Trials: chains of steps given by trainers, tracked in the Mission Log (bs_inventory) and paid on claim.
-- Per character KVP document: { active = { id, step, progress }, done = { [id] = time }, ready = { [id] = true }, pending = { [id] = true } }

local Docs = {}
local MAX_BYTES = 32768

local function key(cid) return ('parkour_trials_%s'):format(cid) end

local function load(cid)
    if Docs[cid] then return Docs[cid] end
    local raw = GetResourceKvpString(key(cid))
    local doc
    if raw and #raw <= MAX_BYTES then
        local ok, d = pcall(json.decode, raw)
        if ok and type(d) == 'table' then doc = d end
    end
    doc = doc or {}
    doc.done, doc.ready, doc.pending = doc.done or {}, doc.ready or {}, doc.pending or {}
    Docs[cid] = doc
    return doc
end

local function save(cid)
    local doc = Docs[cid]
    if not doc then return false end
    local ok, raw = pcall(json.encode, doc)
    if not ok or #raw > MAX_BYTES then return false end
    SetResourceKvp(key(cid), raw)
    return GetResourceKvpString(key(cid)) == raw
end

local function docOf(src)
    local cid = PKS.CharId(src)
    if not cid then return nil end
    return load(cid), cid
end

function PKS.TrialDone(src, id)
    local doc = docOf(src)
    return doc ~= nil and doc.done[id] ~= nil
end

local function stepLabel(src, s)
    if s.type == 'move' then return Lp(src, 'pk.step.move', { n = s.count or 1, move = Lp(src, 'pk.move.' .. tostring(s.kind)) }) end
    if s.type == 'escape' then return Lp(src, 'pk.step.escape', { n = s.count or 1 }) end
    if s.type == 'goto' then return Lp(src, 'pk.step.goto', { place = s.place or '' }) end
    return s.type
end

local function lockReason(src, doc, c, id)
    if c.needsPerk and not PKS.HasPerk(src, c.needsPerk) then
        return Lp(src, c.tier == 'advanced' and 'pk.need_advanced' or 'pk.need_basics')
    end
    if c.requires and not doc.done[c.requires] then return Lp(src, 'pk.need_trial', { title = Lp(src, 'ch.' .. c.requires .. '.t') }) end
    if doc.ready[id] or doc.pending[id] then return Lp(src, 'pk.claim_first') end
    if c.once and doc.done[id] then return Lp(src, 'pk.trial_done') end
    local last = doc.done[id]
    if last and (c.cooldownHours or 0) > 0 and os.time() - last < c.cooldownHours * 3600 then
        return Lp(src, 'pk.trial_cd', { h = math.ceil((c.cooldownHours * 3600 - (os.time() - last)) / 3600) })
    end
    return nil
end

BSB.RegisterCallback('parkour:accept', function(src, trainerId, chainId)
    if not Parkour.Settings.enabled then return { ok = false, msg = Lp(src, 'pk.off') } end
    local t = PKS.Trainer(tostring(trainerId))
    if not PKS.NearTrainer(src, t) then return { ok = false, msg = Lp(src, 'pk.too_far') } end
    chainId = tostring(chainId)
    local offered = false
    for _, cid in ipairs(t.chains or {}) do if cid == chainId then offered = true end end
    local c = Parkour.Chains[chainId]
    if not offered or not c then return { ok = false } end
    local doc, cid = docOf(src)
    if not doc then return { ok = false } end
    if doc.active then
        if doc.active.id == chainId then return { ok = false, msg = Lp(src, 'pk.trial_active') } end
        return { ok = false, msg = Lp(src, 'pk.trial_busy') }
    end
    local why = lockReason(src, doc, c, chainId)
    if why then return { ok = false, msg = why } end
    doc.active = { id = chainId, step = 1, progress = 0 }
    if not save(cid) then doc.active = nil return { ok = false, msg = Lp(src, 'pk.save_failed') } end
    return { ok = true, msg = Lp(src, 'pk.trial_started', { title = Lp(src, 'ch.' .. chainId .. '.t') }) }
end)

local function advance(src, doc, cid)
    local a = doc.active
    local c = Parkour.Chains[a.id]
    local s = c.steps[a.step]
    if a.progress < (s.count or 1) then
        save(cid)
        return
    end
    if a.step >= #c.steps then
        doc.ready[a.id] = true
        doc.active = nil
        save(cid)
        PKS.Notify(src, 'success', 'pk.trial_complete', { title = Lp(src, 'ch.' .. a.id .. '.t') })
        return
    end
    a.step, a.progress = a.step + 1, 0
    save(cid)
    PKS.Notify(src, 'info', 'pk.trial_step', { n = a.step, total = #c.steps, step = stepLabel(src, c.steps[a.step]) })
end

-- Called by sv_main after a move or escape passed its checks
function PKS.Progress(src, kind, move)
    local doc, cid = docOf(src)
    if not doc or not doc.active then return end
    local c = Parkour.Chains[doc.active.id]
    if not c then doc.active = nil save(cid) return end
    local s = c.steps[doc.active.step]
    if not s or s.type ~= kind then return end
    if kind == 'move' and s.kind ~= move then return end
    doc.active.progress = doc.active.progress + 1
    advance(src, doc, cid)
end

-- goto steps are checked here from the server's own position
CreateThread(function()
    while true do
        Wait(2000)
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local cid = PKS.CharId(src)
            local doc = cid and Docs[cid]
            local a = doc and doc.active
            local c = a and Parkour.Chains[a.id]
            local s = c and c.steps[a.step]
            if s and s.type == 'goto' then
                local p = GetEntityCoords(GetPlayerPed(src))
                if #(p - vector3(s.x, s.y, s.z)) <= (s.radius or 10.0) and p.z >= (s.minZ or -1000.0) then
                    a.progress = (s.count or 1)
                    advance(src, doc, cid)
                end
            end
        end
    end
end)

-- Mission Log provider
exports('MissionLogList', function(src)
    local doc = docOf(src)
    if not doc then return {} end
    local out = {}
    local group = Lp(src, 'pk.group')
    local function entry(id, active, complete, claimed)
        local c = Parkour.Chains[id]
        if not c then return end
        local steps = {}
        for i, s in ipairs(c.steps) do
            local done = complete or (active and i < active.step) or false
            local label = stepLabel(src, s)
            if active and i == active.step then label = ('%s (%d/%d)'):format(label, active.progress, s.count or 1) end
            steps[i] = { label = label, done = done }
        end
        local r = c.reward or {}
        local reward = {}
        for _, it in ipairs(r.items or {}) do reward[#reward + 1] = { item = it.item, amount = it.amount } end
        out[#out + 1] = {
            id = id, title = Lp(src, 'ch.' .. id .. '.t'), group = group, steps = steps,
            complete = complete, claimed = claimed, reward = reward,
            noClaim = doc.pending[id] == true,
            hint = doc.pending[id] and Lp(src, 'pk.claim_review') or Lp(src, 'pk.reward_hint', { skill = r.skillXp or 0, xp = r.xp or 0, money = r.money or 0 }),
        }
    end
    if doc.active then entry(doc.active.id, doc.active, false, false) end
    for id in pairs(doc.ready) do entry(id, nil, true, false) end
    for id in pairs(doc.pending) do if not doc.ready[id] then entry(id, nil, true, false) end end
    for id in pairs(doc.done) do
        if not doc.ready[id] and not doc.pending[id] and (not doc.active or doc.active.id ~= id) then entry(id, nil, true, true) end
    end
    return out
end)

-- Reward is reserved before anything is paid, so a crash cannot pay twice
exports('MissionLogClaim', function(src, id)
    local doc, cid = docOf(src)
    if not doc or not doc.ready[id] or doc.pending[id] then return { ok = false, error = Lp(src, 'pk.no_reward') } end
    local c = Parkour.Chains[id]
    if not c then return { ok = false } end
    doc.pending[id], doc.ready[id] = true, nil
    if not save(cid) then doc.pending[id], doc.ready[id] = nil, true return { ok = false, error = Lp(src, 'pk.save_failed') } end
    local r = c.reward or {}
    if (r.skillXp or 0) > 0 then PKS.Grant(src, r.skillXp, true) end
    if (r.xp or 0) > 0 then pcall(function() exports.bs_core:AddXP(src, r.xp, 'parkour_trial_' .. id) end) end
    if (r.money or 0) > 0 then pcall(function() exports.bs_core:AddMoney(src, 'cash', r.money, 'parkour_trial_' .. id) end) end
    for _, it in ipairs(r.items or {}) do pcall(function() exports.bs_inventory:GiveItem(src, it.item, it.amount or 1) end) end
    doc.pending[id] = nil
    doc.done[id] = os.time()
    save(cid)
    return { ok = true }
end)

-- Players drop their current trial with /parkourquit
RegisterCommand('parkourquit', function(src)
    if src == 0 then return end
    local doc, cid = docOf(src)
    if not doc or not doc.active then return end
    doc.active = nil
    save(cid)
    PKS.Notify(src, 'info', 'pk.trial_dropped')
end, false)

-- Admin: /parkourtrialreset <playerId> clears every trial record (pending claims included)
RegisterCommand('parkourtrialreset', function(src, args)
    if not PKS.IsAdmin(src) then return end
    local target = tonumber(args[1])
    local cid = target and PKS.CharId(target)
    if not cid then return print('usage: parkourtrialreset <playerId>') end
    Docs[cid] = { done = {}, ready = {}, pending = {} }
    save(cid)
    print(('[bs_parkour] trials reset for %d'):format(target))
end, false)

AddEventHandler('bs:hook:player:unloaded', function(player)
    if player and player.charId then Docs[player.charId] = nil end
end)

local function register() pcall(function() exports.bs_inventory:RegisterMissionSource(GetCurrentResourceName()) end) end
AddEventHandler('onResourceStart', function(name) if name == GetCurrentResourceName() or name == 'bs_inventory' then register() end end)
CreateThread(function() Wait(2000) register() end)
