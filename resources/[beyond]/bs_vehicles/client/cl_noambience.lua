-- bs_vehicles - no ambient music or radio emitters anywhere (shops, interiors, map areas).

local EMITTERS = {
    'LOS_SANTOS_AMMUNATION_GUN_RANGE', 'SE_DLC_HEIST_ELYSIAN_ISLAND_MUSIC',
    'SE_Script_Placed_Prop_Emitter_Boombox', 'SE_dlc_ch_apartment_rear_big_speaker_L',
    'SE_dlc_ch_apartment_rear_big_speaker_R', 'SE_DLC_Apartment_Speaker',
    'SE_Script_Placed_Prop_Emitter_Speaker', 'SE_DLC_BIKER_CLUBHOUSE_RADIO',
    'SE_DLC_BIKER_CLUBHOUSE_DANCE_FLOOR', 'SE_DLC_BATTLE_CLUB_SPEAKERS',
    'SE_DLC_GR_BUNKER_RADIO', 'SE_DLC_SMUG_HANGAR_RADIO', 'SE_DLC_ARENA_SPEAKERS',
    'SE_DLC_CASINO_MAIN_FLOOR', 'SE_DLC_CASINO_PENTHOUSE_RADIO', 'SE_DLC_NIGHTCLUB_MAIN_ROOM',
    'SE_DLC_TUNER_CAR_MEET', 'SE_DLC_FIXER_OFFICE_RADIO',
    'SE_MP_STUDIO_RADIO', 'SE_LR_BAR_RADIO', 'SE_LR_BAHAMA_MAMAS_RADIO',
    'SE_STRIP_CLUB_MAIN', 'SE_Ammunation_Radio', 'SE_ARMENIAN_BARBER_RADIO',
    'SE_BARBER_SHOP_RADIO', 'SE_CLOTHES_SHOP_RADIO', 'SE_TATTOO_SHOP_RADIO',
    'SE_LIQUOR_STORE_RADIO', 'SE_VANILLA_UNICORN_MAIN_ROOM', 'SE_FIB_BUILDING_RADIO',
    'SE_SWEATSHOP_RADIO', 'SE_FAIRGROUND_MUSIC', 'SE_PIER_MUSIC',
    'SE_CARNIVAL_MUSIC', 'SE_STADIUM_MUSIC', 'SE_COUNTRY_BAR_RADIO',
}
local ZONES = {
    'AZL_DLC_Hei4_Island_Disabled_Zones', 'AZL_DLC_Hei4_Island_Zones',
    'AZL_DLC_CASINO_MUSIC', 'AZL_DLC_NIGHTCLUB_MUSIC',
}

CreateThread(function()
    -- unknown names are ignored by the native
    for i = 1, #EMITTERS do SetStaticEmitterEnabled(EMITTERS[i], false) end
    for i = 1, #ZONES do SetAmbientZoneListStatePersistent(ZONES[i], false, false) end
    SetAudioFlag('PoliceScannerDisabled', true)
    SetAudioFlag('DisableFlightMusic', true)
    SetAudioFlag('WantedMusicDisabled', true)
    SetAudioFlag('AllowScoreAndRadio', false)
    StartAudioScene('MP_LEADERBOARD_SCENE')
    StopAudioScene('MP_LEADERBOARD_SCENE')
    while true do
        -- static radio emitters are re-enabled by interior streaming
        for i = 1, #EMITTERS do SetStaticEmitterEnabled(EMITTERS[i], false) end
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) == 0 then
            SetRadioToStationName('OFF')
        end
        Wait(2000)
    end
end)

CreateThread(function()
    while true do
        SetAudioFlag('PoliceScannerDisabled', true)
        SetAudioFlag('WantedMusicDisabled', true)
        TriggerMusicEvent('MP_MC_STOP')
        Wait(5000)
    end
end)
