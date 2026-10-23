-- bs_guard - rate counter for client to server net events

local G = GuardCore
local counts = {}   -- [src][name] = { start, n }
local hooked = {}

local function hook(name)
    if hooked[name] then return end
    hooked[name] = true
    RegisterNetEvent(name)
    AddEventHandler(name, function()
        local E = Guard.Events
        if not (Guard.Settings.enabled and E.enabled) then return end
        local src = tonumber(source)
        if not src or src <= 0 then return end
        local t = GetGameTimer()
        counts[src] = counts[src] or {}
        local c = counts[src][name]
        if not c or t - c.start > (E.windowMs or 10000) then c = { start = t, n = 0 }; counts[src][name] = c end
        c.n = c.n + 1
        local limit = (E.watch or {})[name] or E.defaultLimit or 40
        if c.n == limit + 1 and not G.isExempt(src) then
            G.Flag(src, 'eventspam', ('%s: >%d calls in %ds'):format(name, limit, math.floor((E.windowMs or 10000) / 1000)),
                70)
        end
    end)
end

for name in pairs(Guard.Events.watch or {}) do hook(name) end

--- Other resources can add their own event to the watch list at runtime.
exports('WatchEvent', function(name, limit)
    if type(name) ~= 'string' or name == '' then return false end
    Guard.Events.watch[name] = tonumber(limit) or Guard.Events.watch[name] or Guard.Events.defaultLimit
    hook(name)
    return true
end)

G.onDrop[#G.onDrop + 1] = function(src) counts[src] = nil end
