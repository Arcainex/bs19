-- Alpha-Z HUD compatibility bridge.
-- Registers the HUD exports before inventory/pause can ask for them.
local pending = {}
local fallback = {
    hudMode='full', hudAnchor='left', hudOpacity=1.0, hideWhenFull=false,
    xpPosition='bottom', xpOpacity=1.0, xpPopups=false,
    hudStyle='slim', menuPalette='default', dodge=true
}

exports('GetHudSettings', function()
    if HudGetSettings then
        local ok, value = pcall(HudGetSettings)
        if ok and type(value) == 'table' then return value end
    end
    return fallback
end)

exports('ApplyHudSettings', function(patch, persist)
    if HudApplySettings then
        local ok, value = pcall(HudApplySettings, patch, persist)
        if ok then return value end
    end
    if type(patch) == 'table' then
        for k,v in pairs(patch) do fallback[k]=v end
    end
    pending[#pending+1] = { patch=patch, persist=persist }
    return fallback
end)

CreateThread(function()
    for _=1,100 do
        Wait(100)
        if HudApplySettings then
            for _, item in ipairs(pending) do
                pcall(HudApplySettings, item.patch, item.persist)
            end
            pending = {}
            return
        end
    end
end)
