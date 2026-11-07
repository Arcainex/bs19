Config = Config or {}
Config.Clothing = {
    interactDistance = 1.8,
    drawDistance = 12.0,
    locations = {
        { coords = vector3(1733.17, 3314.39, 41.22), label = 'Umkleide' },
    }
}


-- Alpha-Z Clothing Editor
Config.Clothing.editor = {
    enabled = true,
    -- false = jeder kann den Editor öffnen (für Einrichtung/Test).
    -- Später true setzen und ACE "bs.clothing.admin" vergeben.
    restricted = false,
    ace = 'bs.clothing.admin',
    -- Linkes ALT: Editor-Fokus temporär lösen und Charakter frei steuern.
    freeMoveWithAlt = true,
    -- H startet im ALT-Freimodus eine Hände-hoch-Animation; X bricht Animationen ab.
    freeMoveHandsUp = true
}
