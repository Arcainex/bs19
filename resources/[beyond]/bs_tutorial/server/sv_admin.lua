-- bs_tutorial F1 page (bs_config ext): edit chapter text per language, set camera points from where you stand, disable or preview chapters.
-- Saved to data/overrides.json on top of the config and locale files.

local RES = GetCurrentResourceName()
local FILE = 'data/overrides.json'

local function isStaff(src)
    if src == 0 then return true end
    if GetResourceState('bs_admin') == 'started' then
        local ok, yes = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        return ok and yes == true
    end
    return IsPlayerAceAllowed(src, 'bs.admin')
end

local function loadFile()
    local raw = LoadResourceFile(RES, FILE)
    local ok, v = pcall(json.decode, raw or '')
    TutorialOverrides.chapters = (ok and type(v) == 'table' and type(v.chapters) == 'table') and v.chapters or {}
end

local function saveFile()
    SaveResourceFile(RES, FILE, json.encode({ chapters = TutorialOverrides.chapters }, { indent = true }), -1)
    TriggerClientEvent('bs:tutorial:overrides', -1, TutorialOverrides.chapters)
end

local function findChapter(id)
    for _, c in ipairs(Tutorial.Chapters) do if c.id == id then return c, true end end
    for _, c in ipairs(Tutorial.CustomChapters or {}) do if c.id == id then return c, false end end
end

local function defaultText(c, builtin, lang)
    if builtin then
        local lines = {}
        for i = 1, 3 do lines[i] = BSLocale.T(lang, ('ch.%s.%d'):format(c.id, i)) end
        return BSLocale.T(lang, ('ch.%s.t'):format(c.id)), lines
    end
    return c.title or c.id, c.lines or {}
end

local function vec(v) return v and { x = v.x, y = v.y, z = v.z } or nil end

local function state(lang)
    lang = BSLocale.IsValid(lang) and lang or 'en'
    local out = {}
    local function add(c, builtin)
        local o = TutorialOverrides.chapters[c.id] or {}
        local title, lines = defaultText(c, builtin, lang)
        local t = o.text and o.text[lang]
        local cam = {}
        for i = 1, 2 do
            local p = (o.cam and o.cam[i]) or (c.cam and c.cam[i] and { pos = vec(c.cam[i].pos), look = vec(c.cam[i].look) })
            cam[i] = p
        end
        out[#out + 1] = { id = c.id, builtin = builtin, disabled = o.disabled == true, title = t and t.title or title,
            lines = t and t.lines or lines, edited = t ~= nil, camEdited = o.cam ~= nil, cam = cam }
    end
    for _, c in ipairs(Tutorial.Chapters) do add(c, true) end
    for _, c in ipairs(Tutorial.CustomChapters or {}) do add(c, false) end
    return { ok = true, lang = lang, langs = BSLocale.Languages, chapters = out }
end

local function entry(id)
    TutorialOverrides.chapters[id] = TutorialOverrides.chapters[id] or {}
    return TutorialOverrides.chapters[id]
end

exports('ConfigExt', function(src, action, a)
    if not isStaff(src) then return { ok = false, error = 'Staff only.' } end
    a = type(a) == 'table' and a or { id = a }
    local lang = a.lang
    if action == 'state' then return state(lang) end

    local c = findChapter(tostring(a.id or ''))
    if not c then return { ok = false, error = 'No such chapter.' } end

    if action == 'saveText' then
        if not BSLocale.IsValid(lang) then return { ok = false, error = 'Bad language.' } end
        local lines = {}
        for i = 1, 3 do
            local s = type(a.lines) == 'table' and a.lines[i]
            lines[i] = type(s) == 'string' and s:sub(1, 400) or ''
        end
        local e = entry(c.id)
        e.text = e.text or {}
        e.text[lang] = { title = tostring(a.title or ''):sub(1, 60), lines = lines }
        TutorialLog(src, ('edited tutorial text %s (%s)'):format(c.id, lang))
    elseif action == 'resetText' then
        local e = entry(c.id)
        if e.text then e.text[lang] = nil end
    elseif action == 'camHere' then
        if src <= 0 then return { ok = false, error = 'Run it in game.' } end
        local idx = tonumber(a.idx) == 2 and 2 or 1
        local cam = BSB.AwaitClient(src, 'tutorial:camNow', 5000)
        if type(cam) ~= 'table' or not cam.pos then return { ok = false, error = 'No camera answer.' } end
        local e = entry(c.id)
        if not e.cam then
            e.cam = {}
            for i = 1, 2 do e.cam[i] = c.cam and c.cam[i] and { pos = vec(c.cam[i].pos), look = vec(c.cam[i].look) } or cam end
        end
        e.cam[idx] = cam
        TutorialLog(src, ('set tutorial camera %d for %s'):format(idx, c.id))
    elseif action == 'resetCam' then
        entry(c.id).cam = nil
    elseif action == 'toggle' then
        local e = entry(c.id)
        e.disabled = not e.disabled
        TutorialLog(src, ('%s tutorial chapter %s'):format(e.disabled and 'disabled' or 'enabled', c.id))
    elseif action == 'preview' then
        if src > 0 then TutorialMarkForced(src); TriggerClientEvent('bs:tutorial:force', src, c.id) end
        return state(lang)
    else
        return { ok = false, error = 'Unknown action.' }
    end
    saveFile()
    return state(lang)
end)

BSB.RegisterCallback('tutorial:overrides', function() return TutorialOverrides.chapters end)

loadFile()
