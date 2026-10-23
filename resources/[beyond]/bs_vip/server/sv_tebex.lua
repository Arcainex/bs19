-- bs_vip - Tebex hook. Stub, off by default (Vip.Tebex.enabled).
-- Setup (docs/VIP.md): add a Tebex game server command `tebex_grant {license} supporter 30` (tier: patron / legend or 1-3), then set Vip.Tebex.enabled = true.
-- Optional HTTP route: POST /bs_vip/tebex with header X-BS-Secret (convar bs_vip_tebex_secret) and body {"identifier":"license:...","tier":"patron","days":30}. Refused while the convar is empty.

local T = Vip.Tebex or {}

local function grant(identifier, tier, days, source)
    if not T.enabled or Vip.Disabled() then
        print('^3[bs_vip]^7 tebex: disabled in config, ignored')
        return false
    end
    if type(identifier) ~= 'string' or not identifier:find(':') then
        print('^1[bs_vip]^7 tebex: bad identifier ' .. tostring(identifier))
        return false
    end

    -- A package id can stand in for the tier.
    local pkg = T.packages and T.packages[tostring(tier)]
    if pkg then tier, days = pkg.tier, days or pkg.days end

    if identifier:find('^license2:') then identifier = identifier:gsub('^license2:', 'license:') end

    local ok = exports.bs_vip:GrantVIP(identifier, tier, tonumber(days) or 0)
    print(('[bs_vip] tebex (%s): %s -> %s %sd = %s'):format(source, identifier, tostring(tier),
        tostring(days or 0), ok and 'ok' or 'FAILED'))
    return ok
end

-- Console only: tebex_grant <identifier> <tier> <days>
RegisterCommand(T.command or 'tebex_grant', function(src, args)
    if src ~= 0 then return end
    grant(args[1], args[2], args[3], 'console')
end, true)

SetHttpHandler(function(req, res)
    if req.path ~= '/tebex' or req.method ~= 'POST' then
        res.writeHead(404); return res.send('')
    end
    local secret = GetConvar('bs_vip_tebex_secret', '')
    local given = req.headers and (req.headers['X-BS-Secret'] or req.headers['x-bs-secret'])
    if not T.enabled or Vip.Disabled() or secret == '' or given ~= secret then
        res.writeHead(403); return res.send('forbidden')
    end
    req.setDataHandler(function(body)
        local ok, data = pcall(json.decode, body or '')
        if not ok or type(data) ~= 'table' then
            res.writeHead(400); return res.send('bad json')
        end
        local done = grant(data.identifier, data.tier, data.days, 'http')
        res.writeHead(done and 200 or 422)
        res.send(done and 'ok' or 'failed')
    end)
end)
