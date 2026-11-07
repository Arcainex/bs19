-- BeyondSurvival - basic animation cancel.
-- X is intentionally reserved only for cancelling the current animation/action.

local function stopCurrentAnimation()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    ClearPedTasks(ped)
    ClearPedSecondaryTask(ped)
    TriggerEvent('bs:emotes:cancelRequested')
end

RegisterCommand('bs_cancelanim', stopCurrentAnimation, false)
RegisterKeyMapping('bs_cancelanim', 'Aktuelle Animation abbrechen', 'keyboard', 'X')
