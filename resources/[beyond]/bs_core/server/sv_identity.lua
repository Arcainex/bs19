-- Resolves a connecting player to a persistent account row (bs_users).

BS.Identity = {}
local I = BS.Identity

--- Returns a map of identifier type -> value for a source.
function I.GetIdentifiers(src)
    local out = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        local kind, value = id:match('^(%w+):(.+)$')
        if kind then out[kind] = value end
    end
    return out
end

-- Primary key for accounts. license2 is preferred (tied to the Rockstar account), license is the fallback.
function I.GetPrimary(src)
    local ids = I.GetIdentifiers(src)
    local primary = ids.license2 or ids.license
    if not primary then return nil, ids end
    return ('license:%s'):format(primary), ids
end

--- Finds or creates the bs_users row. Returns the users table row.
function I.Resolve(src)
    local identifier, ids = I.GetPrimary(src)
    if not identifier then return nil, 'no license identifier' end

    local user = BS.DB.Single('SELECT * FROM `bs_users` WHERE `identifier` = ? LIMIT 1', { identifier })

    if not user then
        BS.DB.Insert([[
            INSERT INTO `bs_users` (`identifier`, `steam`, `discord`, `fivem`, `ip`, `name`, `last_seen`)
            VALUES (?, ?, ?, ?, ?, ?, NOW())
        ]], {
            identifier, ids.steam, ids.discord, ids.fivem, ids.ip, GetPlayerName(src)
        })
        user = BS.DB.Single('SELECT * FROM `bs_users` WHERE `identifier` = ? LIMIT 1', { identifier })
        BS.Log.info('identity', ('created account for %s (%s)'):format(GetPlayerName(src), identifier))
    else
        BS.DB.Update([[
            UPDATE `bs_users`
               SET `name` = ?, `ip` = ?, `discord` = COALESCE(?, `discord`), `last_seen` = NOW()
             WHERE `id` = ?
        ]], { GetPlayerName(src), ids.ip, ids.discord, user.id })
    end

    return user
end

--- True when the account row carries an active ban.
function I.CheckBan(userId)
    local ban = BS.DB.Single([[
        SELECT * FROM `bs_bans`
         WHERE `user_id` = ? AND (`expires_at` IS NULL OR `expires_at` > NOW())
         ORDER BY `id` DESC LIMIT 1
    ]], { userId })
    return ban
end
