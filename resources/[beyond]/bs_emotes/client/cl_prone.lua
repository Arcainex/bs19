-- bs_emotes - prone.
-- GTA V has no real prone state, so this drives the crawl animation set manually with forward/backward movement.
-- The weapon animation overrides the crawl pose when aiming. config allowAiming decides whether aiming is allowed while down (false forces standing up first).

Prone = { active = false, moving = false }

local cfg = Emotes.Prone

local function loadDict()
    if HasAnimDictLoaded(cfg.dict) then return true end
    if not HasAnimDictLoaded(cfg.dict) then RequestAnimDict(cfg.dict) end
    local waited = 0
    while not HasAnimDictLoaded(cfg.dict) and waited < 3000 do Wait(10); waited = waited + 10 end
    return HasAnimDictLoaded(cfg.dict)
end

local function canProne()
    local ped = PlayerPedId()
    if not exports.bs_core:IsLoaded() then return false end
    if IsEntityDead(ped) then return false end
    if IsPedInAnyVehicle(ped, false) then return false end
    if IsPedFalling(ped) or IsPedRagdoll(ped) then return false end
    return true
end

-- Crawl speed, scaled by the Survival skill.
function Prone.Speed()
    local base = cfg.speed or 0.22
    local level = 0

    if GetResourceState('bs_skills') == 'started' then
        local ok, value = pcall(function() return exports.bs_skills:GetSkillLevel('survival') end)
        if ok and type(value) == 'number' then level = value end
    end

    local scaled = base * (1.0 + level * (cfg.speedPerSkillLevel or 0.0))
    return math.min(scaled, cfg.maxSpeed or 0.6)
end

-- move_crawl has no idle clip (the config idle is the forward crawl, which has root motion), so lying still would drift. The animation is frozen when there is no input; the manual translation below does the actual movement.
local function playCrawl(clip, speed)
    local ped = PlayerPedId()

    if not IsEntityPlayingAnim(ped, cfg.dict, clip, 3) then
        TaskPlayAnim(ped, cfg.dict, clip, 2.0, 2.0, -1, 1, 0, false, false, false)
    end

    SetEntityAnimSpeed(ped, cfg.dict, clip, speed or 1.0)
end

function Prone.Set(state)
    local ped = PlayerPedId()

    -- Standing up must always work: never refused, never gated on canProne, regardless of ped state.
    if not state then
        Prone.active = false
        Prone.moving = false

        ClearPedTasksImmediately(ped)
        StopAnimTask(ped, cfg.dict, cfg.idle, 3.0)
        StopAnimTask(ped, cfg.dict, cfg.forward, 3.0)
        StopAnimTask(ped, cfg.dict, cfg.backward, 3.0)
        ResetPedMovementClipset(ped, 0.4)
        SetPedCanRagdoll(ped, true)
        ClearPedSecondaryTask(ped)

        TriggerEvent('bs:emotes:prone', false)
        return true
    end

    if not canProne() then return false end
    if not loadDict() then return false end

    Prone.active = true
    SetPedCanRagdoll(ped, false)
    playCrawl(cfg.idle, 0.0)

    TriggerEvent('bs:emotes:prone', true)
    return true
end

RegisterCommand('bs_prone', function()
    if LocalPlayer.state.bsDrone then return end -- flying the drone
    if Prone.active then
        Prone.Set(false)
    elseif not Prone.Set(true) then
        TriggerEvent('bs:ui:notify', { type = 'warn', message = L('emote.not_here'), duration = 1500 })
    end
end, false)

-- Redundant safety so the player can never be stuck down.
RegisterCommand('standup', function() Prone.Set(false) end, false)
RegisterKeyMapping('bs_prone', L('emote.key_prone'), 'keyboard', Emotes.Keys.prone)

-- W crawls forward, S backward, mouse turns.
CreateThread(function()
    while true do
        if Prone.active then
            Wait(0)
            local ped = PlayerPedId()

            if not Prone.active then goto continue end

            if not canProne() then
                Prone.Set(false)
                goto continue
            end

            -- Jump also stands you up, as an escape if another resource eats the keybind.
            if IsControlJustPressed(0, 22) then
                Prone.Set(false)
                goto continue
            end

            -- Block standing, jumping, sprinting and vaulting while down.
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 36, true)   -- duck
            DisableControlAction(0, 44, true)   -- cover

            if not cfg.allowAiming then
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisablePlayerFiring(PlayerId(), true)
            end

            local forward = IsControlPressed(0, 32)
            local back    = IsControlPressed(0, 33)

            if forward or back then
                Prone.moving = true
                playCrawl(forward and cfg.forward or cfg.backward, 1.0)

                local heading = GetEntityHeading(ped)
                local rad = math.rad(heading)
                local dir = forward and 1.0 or -1.0
                local speed = Prone.Speed() * dir * 0.02

                local coords = GetEntityCoords(ped)
                SetEntityCoordsNoOffset(ped,
                    coords.x - math.sin(rad) * speed,
                    coords.y + math.cos(rad) * speed,
                    coords.z, true, true, true)
            else
                -- Frozen every frame; the engine restores the anim rate whenever the task refreshes.
                Prone.moving = false
                playCrawl(cfg.idle, 0.0)
            end

            -- Mouse X rotates the body while flat.
            local turn = GetDisabledControlNormal(0, 1)
            if math.abs(turn) > 0.02 then
                SetEntityHeading(ped, GetEntityHeading(ped) - turn * 3.0)
            end
        else
            Wait(200)
        end
        ::continue::
    end
end)

AddEventHandler('bs:hook:player:unloaded', function() Prone.Set(false) end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and Prone.active then Prone.Set(false) end
end)

exports('IsProne', function() return Prone.active end)
