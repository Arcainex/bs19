-- bs_admin - Survivor Link tab. The work is done by bs_survivor_link; run() already checks staff and writes bs_guard_log.
local actions = BSAdmin.actions

function actions.linkTool(src, args)
    if GetResourceState('bs_survivor_link') ~= 'started' then
        return { ok = false, error = Lp(src, 'admin.c.not_running', { res = 'bs_survivor_link' }) }
    end
    if src == 0 then return { ok = false, error = 'in game only' } end
    local ok, result = pcall(function() return exports.bs_survivor_link:AdminTool(src, tostring(args.mode or '')) end)
    if not ok then return { ok = false, error = tostring(result) } end
    return result or { ok = false }
end
