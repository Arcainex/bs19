-- bs_pause graphics and audio presets. Only what natives can do from a script; resolution and textures stay in GTA settings.
-- Saved per player in KVP and applied on start.

PausePresets = { gfx = 'balanced', audio = 'default', distantLights = true }

local KVP = 'bs_pause:presets'
local GFX = {
    performance = { lod = 0.8,  budget = true,  shadows = 0.7 },
    balanced    = { lod = 1.0,  budget = false, shadows = 1.0 },
    quality     = { lod = 1.15, budget = false, shadows = 1.0 },
}

local function try(fn, ...) pcall(fn, ...) end

local function applyGfx()
    local p = GFX[PausePresets.gfx] or GFX.balanced
    try(SetReducePedModelBudget, p.budget)
    try(SetReduceVehicleModelBudget, p.budget)
    try(CascadeShadowsSetCascadeBoundsScale, p.shadows)
    try(DisableVehicleDistantlights, not PausePresets.distantLights)
end

local function applyAudio()
    local immersive = PausePresets.audio == 'immersive'
    try(SetAudioFlag, 'DisableFlightMusic', immersive)
    try(SetUserRadioControlEnabled, not immersive)
end

function PausePresets.Apply()
    applyGfx(); applyAudio()
end

function PausePresets.Set(patch)
    if type(patch) ~= 'table' then return end
    if GFX[patch.gfx] then PausePresets.gfx = patch.gfx end
    if patch.audio == 'default' or patch.audio == 'immersive' then PausePresets.audio = patch.audio end
    if patch.distantLights ~= nil then PausePresets.distantLights = patch.distantLights == true end
    -- Encode the plain values only: PausePresets also holds functions, which json.encode rejects (that error used to kill the NUI callback, so no button did anything).
    SetResourceKvp(KVP, json.encode(PausePresets.Get()))
    PausePresets.Apply()
end

function PausePresets.Get()
    return { gfx = PausePresets.gfx, audio = PausePresets.audio, distantLights = PausePresets.distantLights }
end

CreateThread(function()
    local raw = GetResourceKvpString(KVP)
    local ok, saved = pcall(json.decode, raw or '')
    if ok and type(saved) == 'table' then
        PausePresets.gfx = GFX[saved.gfx] and saved.gfx or 'balanced'
        PausePresets.audio = saved.audio == 'immersive' and 'immersive' or 'default'
        PausePresets.distantLights = saved.distantLights ~= false
    end
    PausePresets.Apply()

    -- LOD scale and the radio need refreshing every frame / vehicle.
    while true do
        local p = GFX[PausePresets.gfx] or GFX.balanced
        if p.lod ~= 1.0 then
            OverrideLodscaleThisFrame(p.lod)
            Wait(0)
        else
            Wait(500)
        end
        if PausePresets.audio == 'immersive' then
            local veh = GetVehiclePedIsIn(PlayerPedId(), false)
            if veh ~= 0 and GetPlayerRadioStationName() ~= nil then SetVehRadioStation(veh, 'OFF') end
        end
    end
end)
