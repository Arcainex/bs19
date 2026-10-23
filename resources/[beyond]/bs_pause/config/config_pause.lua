-- bs_pause config. Text values that match a locale key are translated, anything else is shown as written.
Pause = {}

Pause.Settings = {
    enabled   = true,     -- off = the normal GTA pause menu comes back
    devlog    = true,     -- show the Devlog tab (the page loads only when the tab is opened)
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
    { label = 'k.inventory',  cmd = 'inventory',       key = 'I' },
    { label = 'k.menu',       cmd = 'survivorwheel',   key = 'F5' },
    { label = 'k.faction',    cmd = 'factionmenu',     key = 'U' },
    { label = 'k.craft',      cmd = 'craftmenu_y',     key = 'Y' },
    { label = 'k.map',        cmd = 'bs_fieldmap',     key = 'M' },
    { label = 'k.scoreboard', cmd = '+scoreboard',     key = 'F9' },
    { label = 'k.weapons',    cmd = 'weaponwheel',     key = 'O' },
    { label = 'k.vehicle',    cmd = 'bs_vehiclewheel', key = 'G' },
    { label = 'k.emotes',     cmd = 'emotemenu',       key = 'F6' },
    { label = 'k.needs',      cmd = 'needswheel',      key = 'N' },
    { label = 'k.chat',       cmd = 'bs_chat_open',    key = 'T' },
    { label = 'k.handsup',    cmd = 'bs_handsup',      key = 'X' },
    { label = 'k.point',      cmd = 'bs_point',        key = 'B' },
    { label = 'k.prone',      cmd = 'bs_prone',        key = 'Z' },
    { label = 'k.crouch',     cmd = 'bs_stance_crouch',key = 'K' },
    { label = 'k.whistle',    cmd = 'bs_whistle',      key = 'H' },
    { label = 'k.holster',    cmd = 'bs_holster',      key = 'J' },
}
