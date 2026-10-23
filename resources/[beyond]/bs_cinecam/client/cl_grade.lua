-- BeyondSurvival - bs_cinecam grade. Filter presets (grain, vignette, tint, timecycle) belong to bs_ui (UI.Filters, cl_filter.lua); this file only borrows them so the look never drifts from Settings.

CineGrade = { held = false }

local function ui()
    return GetResourceState('bs_ui') == 'started'
end

-- Presets for the menu. Empty when bs_ui is not running, in which case the page hides the control.
function CineGrade.Presets()
    if not ui() then return {} end
    local ok, list = pcall(function() return exports.bs_ui:FilterPresets() end)
    return ok and list or {}
end

-- Puts the shoot's grade on or off. Runs on entering the camera and on every settings change, so it must be repeat-safe: the suspend is guarded by `held` to avoid leaving the player's own filter off after landing.
function CineGrade.Set(settings)
    if not ui() then return end

    local id = settings and settings.filter or ''
    local strength = settings and settings.filterStrength or 0.8

    if id == nil or id == '' then
        -- No preset: give the player their own look back.
        if CineGrade.held then
            CineGrade.held = false
            pcall(function() exports.bs_ui:SuspendFilter(false) end)
        end
        return
    end

    if not CineGrade.held then
        CineGrade.held = true
        pcall(function() exports.bs_ui:SuspendFilter(true) end)
    end

    -- Order matters: SuspendFilter clears the screen and remembers it, then ApplyFilter paints the shoot's grade. Reversed, the suspend would wipe it.
    pcall(function() exports.bs_ui:ApplyFilter(id, strength) end)
end

-- Landing. Unconditional, so a player never leaves a shoot stuck in the wrong grade.
function CineGrade.Release()
    if not ui() then
        CineGrade.held = false
        return
    end

    if CineGrade.held then
        pcall(function() exports.bs_ui:ApplyFilter('off', 0) end)
    end

    CineGrade.held = false
    pcall(function() exports.bs_ui:SuspendFilter(false) end)
end

-- A restart mid-flight would leave the player suspended with nothing to resume them. Same reasoning as the weapon un-hide in bs_interactions.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CineGrade.Release()
end)
