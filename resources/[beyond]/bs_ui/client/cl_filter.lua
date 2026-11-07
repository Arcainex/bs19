-- bs_ui - player screen filter.
-- A filter chosen in Settings, stored on the character and rendered only on
-- that client. See the note on UI.Filters in config_ui.lua for why it uses two
-- mechanisms.
-- A filter must never be an advantage: it may darken or tint, never brighten,
-- cut fog or add night vision.
-- Timecycle names fail silently, so each preset is probed once: set it, then
-- check GetTimecycleModifierIndex (-1 = not found), cache and print the result.

local current = nil          -- resolved preset id currently applied
local resolved = {}          -- [presetId] = timecycle name | false
local suspended = false      -- something else owns the screen (see below)

local function send(p) SendNUIMessage(p) end

local function presetById(id)
    for _, preset in ipairs(UI.Filters or {}) do
        if preset.id == id then return preset end
    end
    return nil
end

-- Resolving the grade

-- Which of a preset's candidate timecycle names exists here. Returns the name or
-- nil. The probe sets the modifier, so ClearTimecycleModifier runs on every miss.
local function resolveGrade(preset)
    if resolved[preset.id] ~= nil then
        return resolved[preset.id] or nil
    end

    for _, name in ipairs(preset.tc or {}) do
        SetTimecycleModifier(name)
        if GetTimecycleModifierIndex() ~= -1 then
            resolved[preset.id] = name
            return name
        end
    end

    ClearTimecycleModifier()
    resolved[preset.id] = false

    if preset.tc and #preset.tc > 0 then
        print(('^3[BeyondSurvival]^7 (ui) filter "%s": none of its timecycle names '
            .. 'exist on this build - it will render as overlay only')
            :format(preset.id))
    end

    return nil
end

-- Applying

local function clearEngine()
    ClearTimecycleModifier()
    ClearExtraTimecycleModifier()

    -- The engine's film grain. Wrapped because the natives keep Rockstar's
    -- original spelling ("Overide"); the overlay grain does the visible work anyway.
    pcall(function()
        SetNoiseOveride(false)
        SetNoisinessOveride(0.0)
    end)
end

-- Put a preset on screen. `strength` is the player's own 0-1 master, applied on
-- top of the preset. Called on every settings change and on spawn, so it must be
-- safe to repeat.
function FilterApply(id, strength)
    strength = math.max(0.0, math.min(1.0, tonumber(strength) or 1.0))

    local preset = presetById(id or 'off')
    if not preset or preset.id == 'off' then
        current = nil
        clearEngine()
        send({ action = 'filter', filter = nil })
        return
    end

    current = preset.id

    if suspended then return end

    clearEngine()

    local grade = resolveGrade(preset)
    if grade then
        SetTimecycleModifier(grade)
        SetTimecycleModifierStrength((preset.strength or 1.0) * strength)
    end

    local grain = (preset.grain or 0.0) * strength
    if grain > 0.01 then
        pcall(function()
            SetNoiseOveride(true)
            -- Halved before it reaches the engine: its scale is much stronger than the
            -- overlay's and the two stack.
            SetNoisinessOveride(math.min(1.0, grain * 0.5))
        end)
    end

    send({
        action = 'filter',
        filter = {
            id = preset.id,
            grain = grain,
            vignette = (preset.vignette or 0.0) * strength,
            scanlines = (preset.scanlines or 0.0) * strength,
            tint = preset.tint and {
                r = preset.tint.r, g = preset.tint.g, b = preset.tint.b,
                a = (preset.tint.a or 0.0) * strength,
            } or nil,
        },
    })
end

-- The list the pickers are built from (Settings and the cinematic camera).
-- Copied rather than shared, so consumers never get the live table.
exports('FilterPresets', function()
    local out = {}
    for _, preset in ipairs(UI.Filters or {}) do
        out[#out + 1] = { id = preset.id, label = preset.label, note = preset.note }
    end
    return out
end)

exports('ApplyFilter', function(id, strength) return FilterApply(id, strength) end)

-- Restore the saved gameplay look after a menu camera releases its own grade.
exports('RestoreFilter', function()
    if suspended then return end
    local settings = HudGetSettings and HudGetSettings() or {}
    FilterApply(current or settings.filter, settings.filterStrength)
end)

-- The filter is a persistent preference. When another system clears the grade,
-- restore only if the screen is otherwise unowned. A valid non-filter grade
-- (injury, cinematic) keeps priority.
CreateThread(function()
    while true do
        Wait(500)
        if current and not suspended and GetTimecycleModifierIndex() == -1 then
            local settings = HudGetSettings and HudGetSettings() or {}
            FilterApply(current or settings.filter, settings.filterStrength)
        end
    end
end)

-- Suspend, for anything that owns the screen briefly (death fade, cutscene,
-- character select). Drops the filter and remembers it so resume needs no
-- arguments. Not reference-counted: failing toward 'filter off' is safer than
-- a stuck filter.
exports('SuspendFilter', function(state)
    suspended = state and true or false
    if suspended then
        clearEngine()
        send({ action = 'filter', filter = nil })
    else
        local settings = HudGetSettings and HudGetSettings() or {}
        FilterApply(current or settings.filter, settings.filterStrength)
    end
end)

-- Safety

-- The timecycle is engine state, not resource state, so a restart leaves the
-- grade applied. Clear it on stop.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearEngine()
end)

AddEventHandler('bs:hook:player:unloaded', function()
    current = nil
    clearEngine()
    send({ action = 'filter', filter = nil })
end)
