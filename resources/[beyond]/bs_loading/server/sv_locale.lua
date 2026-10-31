-- The standard FiveM connection handover is available before gameplay client scripts.
-- Do not defer/finish connections or read account language; bs_core owns that lifecycle.
AddEventHandler('playerConnecting', function(_, _, deferrals)
    deferrals.handover({ bsLoading = { language = BSLocale.Default() } })
end)
