-- Crash breadcrumbs. Keeps the last N events in memory, flushes to KVP every couple of seconds and prints the previous session's list on start.
-- Other resources call Crumb(tag, fmt, ...) from @bs_core/shared/sh_crumbs.lua.

local cfg = Config.Crumbs or {}
local KEY = 'bs_crumbs'
local keep = cfg.keep or 40
local ring, head, dirty = {}, 0, false

local function on() return cfg.enabled ~= false end

local function add(tag, msg)
    if not on() then return end
    head = head % keep + 1
    ring[head] = ('%d %s %s'):format(GetGameTimer(), tostring(tag), tostring(msg or ''))
    dirty = true
end

BS.Crumb = add
exports('Crumb', add)
exports('CrumbsOn', on)

-- newest last
local function list()
    local out = {}
    for i = 1, keep do
        local e = ring[(head + i - 1) % keep + 1]
        if e then out[#out + 1] = e end
    end
    return out
end
exports('Crumbs', list)

CreateThread(function()
    local last = GetResourceKvpString(KEY)
    if last and last ~= '' then
        print('^3[crumbs] last session:^7\n' .. last)
    end
    if not on() then return end
    SetResourceKvp(KEY, '')
    add('session', 'start')
    while true do
        Wait(cfg.saveMs or 2000)
        if dirty then
            dirty = false
            SetResourceKvpNoSync(KEY, table.concat(list(), '\n'))
        end
    end
end)

RegisterCommand('bs_crumbs', function()
    print('^3[crumbs] this session:^7\n' .. table.concat(list(), '\n'))
end, false)
