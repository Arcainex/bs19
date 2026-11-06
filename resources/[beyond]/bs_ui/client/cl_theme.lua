-- Theme pack for NUI pages: every page asks for it through this callback (see html/shared/theme.js).
RegisterNUICallback('themeGet', function(_, cb)
    local t = GlobalState.bsUiTheme
    cb({ theme = (t and t.theme) or 'classic', rev = (t and t.rev) or 0 })
end)
