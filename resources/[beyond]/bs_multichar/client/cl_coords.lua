RegisterCommand('coords', function()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local coords = string.format(
        'vector4(%.2f, %.2f, %.2f, %.2f)',
        pos.x, pos.y, pos.z, heading
    )

    print('BS19 COORDS: ' .. coords)

    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 100 },
        args = { 'BS19', coords }
    })
end, false)