-- bs_economy - vendor windows, gathering prompts and loot interactions. Scaffolded.
-- Cross-resource rule: register plain data with bs_core and react to 'bs:hook:*' events; tables containing functions don't survive exports.

exports.bs_core:RegisterModule('economy', { side = 'client', version = '0.1.0', ready = true })

AddEventHandler('bs:hook:core:ready', function()
    print('^5[BeyondSurvival]^7 bs_economy (client) ready')
end)
