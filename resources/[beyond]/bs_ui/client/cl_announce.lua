-- bs_ui - staff announcement banner. Sent by bs_admin (/ann, /announce, F10) to every client.

RegisterNetEvent('bs:ui:announce', function(data)
    if type(data) ~= 'table' then return end
    local text = tostring(data.text or ''):sub(1, 400)
    if text == '' then return end

    local title = tostring(data.title or ''):sub(1, 60)
    if title == '' then title = L('ui.ann_title') end

    local seconds = math.max(3, math.min(30, math.floor(tonumber(data.duration) or 10)))

    Nui.Send({
        action   = 'announce',
        title    = title,
        text     = text,
        by       = data.by and tostring(data.by):sub(1, 40) or nil,
        duration = seconds * 1000,
    })
end)
