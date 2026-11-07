-- Interface language: per account in bs_users.language, published on the player state bag 'bs_lang'.
-- An empty value means the player follows the server default (GlobalState.bs_defaultLang).

BS.Locale = {}

local function publishDefault()
    local d = BSConfigGet and BSConfigGet('Global.defaultLanguage', nil) or nil
    if not BSLocale.IsValid(d) then d = GetConvar('bs_defaultLanguage', 'en') end
    if not BSLocale.IsValid(d) then d = 'en' end
    if GlobalState.bs_defaultLang ~= d then GlobalState.bs_defaultLang = d end
end
publishDefault()
AddEventHandler('bs_config:changed:bs_core', publishDefault)

-- Called whenever an account row is bound to a source.
function BS.Locale.Apply(src, user)
    if not src or not user then return end
    local lang = BSLocale.IsValid(user.language) and user.language or ''
    Player(src).state:set('bs_lang', lang, true)
end

RegisterNetEvent('bs_core:setLanguage', function(lang)
    local src = source
    if not BSLocale.IsValid(lang) then return end
    local identifier = BS.Identity.GetPrimary(src)
    if not identifier then return end
    BS.DB.Update('UPDATE `bs_users` SET `language` = ? WHERE `identifier` = ?', { lang, identifier })
    Player(src).state:set('bs_lang', lang, true)
end)

exports('GetLanguage', function(src) return BSLocale.LangOf(src) end)
-- Lets other resources translate one of bs_core's keys for a player.
exports('Tr', function(src, key, vars) return Lp(src, key, vars) end)
