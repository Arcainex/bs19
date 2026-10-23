-- bs_cinecam - answers whether a player may fly the camera. A free camera sees through walls, so the check is server-side. It can't stop a client injecting its own camera.

local function mayUse(src)
    if not Cine.Settings.requirePermission then return true end

    for _, ace in ipairs(Cine.Settings.aces) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end

    -- bs_admin may use aces this resource doesn't know about; asking it keeps one place to add staff. Optional.
    if GetResourceState('bs_admin') == 'started' then
        local ok, answer = pcall(function()
            return exports.bs_admin:IsAdmin(src)
        end)
        if ok and answer then return true end
    end

    return false
end

BSB.RegisterCallback('cinecam:mayuse', function(src)
    return mayUse(src)
end)

-- Console diagnostic that prints why access was denied.
RegisterCommand('cinewho', function(src, args)
    local target = tonumber(args[1]) or src
    if src ~= 0 and not IsPlayerAceAllowed(src, 'bs.admin') then
        print(('[bs_cinecam] %s asked about %s and is not staff'):format(src, target))
        return
    end

    local lines = { ('[bs_cinecam] permission report for %s'):format(target) }
    lines[#lines + 1] = ('  requirePermission = %s'):format(tostring(Cine.Settings.requirePermission))

    for _, ace in ipairs(Cine.Settings.aces) do
        lines[#lines + 1] = ('  ace %-16s %s'):format(ace, tostring(IsPlayerAceAllowed(target, ace)))
    end

    lines[#lines + 1] = ('  bs_admin        %s'):format(GetResourceState('bs_admin'))
    lines[#lines + 1] = ('  VERDICT         %s'):format(tostring(mayUse(target)))

    print(table.concat(lines, '\n'))
end, false)
