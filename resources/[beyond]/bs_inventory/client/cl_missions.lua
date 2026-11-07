-- Mission Log tab: asks the server for the list and forwards "Finish mission".
local KEYS = { 'ui.missions', 'mlog.empty', 'mlog.finish', 'mlog.active', 'mlog.complete', 'mlog.claimed', 'mlog.anywhere', 'mlog.reward',
    'mlog.all', 'mlog.sum.active', 'mlog.sum.ready', 'mlog.sum.done', 'mlog.st.active', 'mlog.st.ready', 'mlog.st.done', 'mlog.sort', 'mlog.sort.default', 'mlog.sort.near', 'mlog.sort.reward', 'mlog.search', 'mlog.pin', 'mlog.unpin', 'mlog.pinned', 'mlog.nomatch', 'mlog.dens.compact', 'mlog.dens.comfy' }

local function strings()
    local d = {}
    for _, k in ipairs(KEYS) do d[k] = L(k) end
    return d
end

RegisterNUICallback('missionsList', function(_, cb)
    local list = BSB.Await('inventory:missions', 8000)
    for _, m in ipairs(type(list) == 'table' and list or {}) do
        for _, rw in ipairs(m.reward or {}) do rw.label = ItemLabel and ItemLabel(rw.item) or rw.item end
    end
    cb({ list = type(list) == 'table' and list or {}, dict = strings() })
end)

RegisterNUICallback('missionClaim', function(data, cb)
    if type(data) ~= 'table' then return cb({ ok = false }) end
    local r = BSB.Await('inventory:missionClaim', 8000, data.source, data.id)
    if r and not r.ok and r.error then TriggerEvent('bs:ui:notify', { type = 'warn', message = r.error }) end
    cb(r or { ok = false })
end)
