local lastAt = 0
local enabled, volume = true, 0.7
local soundIndex = 0

AddEventHandler('bs:combatfx:options', function(options)
    if type(options) ~= 'table' then return end
    enabled = options.zombieImpactFx ~= false
    volume = math.max(0, math.min(1, tonumber(options.zombieImpactVolume) or 0.7))
end)

local function bloodAt(point, headshot)
    if not Zombies.CombatEffects or Zombies.CombatEffects.blood == false then return end
    if not HasNamedPtfxAssetLoaded('core') then
        RequestNamedPtfxAsset('core')
        return
    end
    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord('blood_stab', point.x, point.y, point.z,
        0.0, 0.0, 0.0, headshot and 0.75 or 0.45, false, false, false)
end

AddEventHandler('bs:z:localImpact', function(id, headshot, melee, hit)
    if not enabled or not Zombies.CombatEffects or Zombies.CombatEffects.enabled == false then return end
    local now = GetGameTimer()
    if now - lastAt < 95 then return end
    local walker = Zed and Zed.live and Zed.live[id]
    local ped = walker and walker.ped
    if not ped or not DoesEntityExist(ped) then return end
    local player = PlayerPedId()
    local playerPos, targetPos = GetEntityCoords(player), GetEntityCoords(ped)
    local distance = #(targetPos - playerPos)
    if distance > 70 then return end
    lastAt = now
    local point = GetPedBoneCoords(ped, headshot and 31086 or 24818, 0.0, 0.0, 0.0)
    if hit and hit.x and hit.y and hit.z then
        local impact = vector3(hit.x, hit.y, hit.z)
        if #(impact - targetPos) < 2.0 then point = impact end
    end
    bloodAt(point, headshot)
    if volume <= 0 or GetResourceState('bs_ui') ~= 'started' then return end
    soundIndex = soundIndex % 3 + 1
    local file = ('z_impact_%d.wav'):format(soundIndex)
    pcall(function()
        exports.bs_ui:PlaySoundAt(file, {x = point.x, y = point.y, z = point.z}, {
            volume = volume * (melee and 0.9 or 0.65), maxDistance = 34,
            rate = 0.94 + math.random() * 0.12, priority = 'feedback',
        })
    end)
end)

CreateThread(function()
    RequestNamedPtfxAsset('core')
end)
