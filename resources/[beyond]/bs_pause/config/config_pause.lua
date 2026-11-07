-- bs_pause config. Text values that match a locale key are translated, anything else is shown as written.
Pause = {}

Pause.Settings = {
    enabled   = true,     -- off = the normal GTA pause menu comes back
    devlog    = false,     -- show the Devlog tab (the page loads only when the tab is opened)
    devlogUrl = 'https://bs19.org/devlog',
    discord   = 'discord.gg/aBkCNgmDZ',
    website   = 'bs19.org',
    blur      = true,
}

-- Server rules, top to bottom. Locale keys or plain text.
Pause.Rules = { 'rule.1', 'rule.2', 'rule.3', 'rule.4', 'rule.5' }

-- News cards, newest first. { date, title, text } - locale keys or plain text.
Pause.News = {
    { date = '2026-10-15', title = 'news.1.t', text = 'news.1.b' },
}

-- Keys shown in Settings > Key bindings. The real binding is read from the game, `key` is only the default.
Pause.Keybinds = {
    { label = 'k.inventory', cmd = 'inventory_tab', key = 'TAB' },
    { label = 'Baumenü', cmd = 'buildmenu_u', key = 'U' },
    { label = 'Squad Menü', cmd = 'squadconsole', key = 'F3' },
    
    { label = 'Hände hoch', cmd = 'bs_handsup_h', key = 'H' },
    { label = 'Animation abbrechen', cmd = 'bs_cancelanim', key = 'X' },
    { label = 'Mit Finger zeigen', cmd = 'bs_point', key = 'B' },
}
