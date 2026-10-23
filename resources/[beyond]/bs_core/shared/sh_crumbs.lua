-- Crumb(tag, fmt, ...) -> bs_core breadcrumb log (client only, no-op on server).
-- The string is only formatted when crumbs are on.
local isServer = IsDuplicityVersion()
local enabled, checkedAt = false, -1

function Crumb(tag, fmt, ...)
    if isServer then return end
    local now = GetGameTimer()
    if now - checkedAt > 10000 or checkedAt < 0 then
        checkedAt = now
        local ok, v = pcall(function() return exports.bs_core:CrumbsOn() end)
        enabled = ok and v == true
    end
    if not enabled then return end
    local msg = fmt
    if select('#', ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        msg = ok and s or fmt
    end
    pcall(function() exports.bs_core:Crumb(tag, msg) end)
end
