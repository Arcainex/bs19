// icons.js - item icon set. Inline SVG line art (no downloads, no licence), single-weight stencil style, coloured by the surrounding CSS. Loaded across resources as nui://bs_ui/html/js/icons.js.
(function (global) {
    'use strict';

    const OPEN = '<svg viewBox="0 0 24 24" class="bs-icon" aria-hidden="true" ' +
        'fill="none" stroke="currentColor" stroke-width="1.4" ' +
        'stroke-linecap="round" stroke-linejoin="round">';
    const CLOSE = '</svg>';

    // Each entry is the inside of the svg, as raw path data.
    const ART = {
        // boosters
        booster_drone:
            '<rect x="9" y="10" width="6" height="4" rx="1"/><path d="M9 11 5 8M15 11l4-3M9 13l-4 3M15 13l4 3"/>' +
            '<path d="M2.5 8h5M16.5 8h5M2.5 16h5M16.5 16h5"/><circle cx="12" cy="12" r=".6"/>',
        booster_shield:
            '<rect x="6" y="3" width="12" height="18" rx="2"/><rect x="9" y="6" width="6" height="2.5" rx=".5"/><path d="M8 12h8M8 15h8"/>',
        booster_turret:
            '<path d="M6 20h12M8 20l2-5h4l2 5"/><rect x="8" y="9" width="8" height="6" rx="1"/><path d="M16 11.5h5M12 9V6.5"/>',
        booster_medic:
            '<path d="M12 21v-6"/><path d="M8 15h8l-1.2-8.5h-5.6Z"/><path d="M12 9v4M10 11h4"/><path d="M5 5.5l2 1.5M19 5.5 17 7M12 2.5v2"/>',
        booster_decoy:
            '<ellipse cx="12" cy="13.5" rx="5" ry="6.5"/><path d="M4 7a10 10 0 0 1 3-3M20 7a10 10 0 0 0-3-3M2.5 11a12 12 0 0 1 1-3M21.5 11a12 12 0 0 0-1-3"/>',
        booster_adrenaline:
            '<path d="M5 19 15.5 8.5M14 7l3 3M16 5.5l2.5 2.5M17.5 4l2.5 2.5M5 19l-1.5 1.5"/><path d="M7 14l3 3M9 12l3 3"/>',
        _booster:
            '<path d="M12 3.5 19 6v5.5c0 4.2-3 7.4-7 9-4-1.6-7-4.8-7-9V6Z"/><path d="M12 8v6M9 11h6"/>',
        // drugs
        cocaine_bad: '<path d="M4 17.5h16"/><path d="M6 17.5c1.5-2.5 3-3.5 5-3.5s3.5 1 5 3.5"/><path d="M15 8l5-3M17 12h3"/>',
        cocaine: '<path d="M4 17.5h16"/><path d="M6 17.5c1.5-2.5 3-3.5 5-3.5s3.5 1 5 3.5"/><path d="M15 8l5-3M17 12h3"/>',
        cocaine_good: '<path d="M4 17.5h16"/><path d="M6 17.5c1.5-2.5 3-3.5 5-3.5s3.5 1 5 3.5"/><path d="M15 8l5-3M17 12h3"/>',
        morphine_bad: '<path d="M4 20l3-3"/><path d="M6 15.5 15.5 6l2.5 2.5L8.5 18Z"/><path d="M16.5 5l2.5 2.5M18 3.5l2.5 2.5M9 12.5l1.5 1.5M11.5 10l1.5 1.5"/>',
        morphine: '<path d="M4 20l3-3"/><path d="M6 15.5 15.5 6l2.5 2.5L8.5 18Z"/><path d="M16.5 5l2.5 2.5M18 3.5l2.5 2.5M9 12.5l1.5 1.5M11.5 10l1.5 1.5"/>',
        morphine_good: '<path d="M4 20l3-3"/><path d="M6 15.5 15.5 6l2.5 2.5L8.5 18Z"/><path d="M16.5 5l2.5 2.5M18 3.5l2.5 2.5M9 12.5l1.5 1.5M11.5 10l1.5 1.5"/>',
        amphetamine_bad: '<rect x="4" y="9" width="16" height="6" rx="3"/><path d="M12 9v6"/><circle cx="7" cy="5" r="1.2"/><circle cx="17" cy="19" r="1.2"/>',
        amphetamine: '<rect x="4" y="9" width="16" height="6" rx="3"/><path d="M12 9v6"/><circle cx="7" cy="5" r="1.2"/><circle cx="17" cy="19" r="1.2"/>',
        amphetamine_good: '<rect x="4" y="9" width="16" height="6" rx="3"/><path d="M12 9v6"/><circle cx="7" cy="5" r="1.2"/><circle cx="17" cy="19" r="1.2"/>',
        weed_bad: '<path d="M12 21v-8"/><path d="M12 13C9 11 7 7 7 3c3 2 5 5 5 10Z"/><path d="M12 13c3-2 5-6 5-10-3 2-5 5-5 10Z"/><path d="M12 14c-3 0-6-1.5-8-4 3 0 6 1 8 4ZM12 14c3 0 6-1.5 8-4-3 0-6 1-8 4Z"/>',
        weed: '<path d="M12 21v-8"/><path d="M12 13C9 11 7 7 7 3c3 2 5 5 5 10Z"/><path d="M12 13c3-2 5-6 5-10-3 2-5 5-5 10Z"/><path d="M12 14c-3 0-6-1.5-8-4 3 0 6 1 8 4ZM12 14c3 0 6-1.5 8-4-3 0-6 1-8 4Z"/>',
        weed_good: '<path d="M12 21v-8"/><path d="M12 13C9 11 7 7 7 3c3 2 5 5 5 10Z"/><path d="M12 13c3-2 5-6 5-10-3 2-5 5-5 10Z"/><path d="M12 14c-3 0-6-1.5-8-4 3 0 6 1 8 4ZM12 14c3 0 6-1.5 8-4-3 0-6 1-8 4Z"/>',
        cigarette: '<rect x="3" y="13" width="15" height="3" rx=".5"/><path d="M14 13v3"/><path d="M20 16v-3M20 10c0-2 1.5-2 1.5-4"/>',
        lighter: '<rect x="7" y="9" width="9" height="12" rx="1.2"/><path d="M7 12h9M10 9V6.5h4V9"/><path d="M12 4.5c0-1 1-1.5 1-2.5"/>',
        matches: '<rect x="4" y="8" width="16" height="10" rx="1"/><path d="M4 11h16"/><path d="M9 8 7 3M12 8l1-5M15 8l2.5-4.5"/>',
        rehab_kit: '<rect x="4.5" y="7" width="15" height="13" rx="1.5"/><path d="M9 7V5h6v2"/><path d="M8.5 13.5h7M12 10v7"/><path d="M15.5 17.5l2 2"/>',
        _drug: '<rect x="4" y="9" width="16" height="6" rx="3"/><path d="M12 9v6"/><circle cx="7" cy="5" r="1.2"/><circle cx="17" cy="19" r="1.2"/>',
        // medical
        bandage:
            '<path d="M4.6 9.2 9.2 4.6a3.4 3.4 0 0 1 4.8 0l5.4 5.4a3.4 3.4 0 0 1 0 4.8l-4.6 4.6a3.4 3.4 0 0 1-4.8 0L4.6 14a3.4 3.4 0 0 1 0-4.8Z"/>' +
            '<path d="M8.8 8.8 15.2 15.2"/><path d="M11 7.6l1.2 1.2M9 10.4l1.2 1.2M13.6 12.4l1.2 1.2M11.6 15.2l1.2 1.2"/>',
        medkit:
            '<path d="M3.5 8.5h17v10a1.5 1.5 0 0 1-1.5 1.5H5a1.5 1.5 0 0 1-1.5-1.5Z"/>' +
            '<path d="M9 8.5V6a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 6v2.5"/>' +
            '<path d="M12 11.5v5M9.5 14h5"/>',
        antiseptic:
            '<path d="M10 3.5h4v2.2l2.1 2.6a3 3 0 0 1 .7 1.9v8.3a1.5 1.5 0 0 1-1.5 1.5h-6.6a1.5 1.5 0 0 1-1.5-1.5v-8.3a3 3 0 0 1 .7-1.9L10 5.7Z"/>' +
            '<path d="M7.2 13.4h9.6"/><path d="M12 15.2v3M10.5 16.7h3"/>',
        antibiotics:
            '<path d="M8.4 4.6h7.2a1.4 1.4 0 0 1 1.4 1.4v12a1.4 1.4 0 0 1-1.4 1.4H8.4A1.4 1.4 0 0 1 7 18V6a1.4 1.4 0 0 1 1.4-1.4Z"/>' +
            '<path d="M7 9.4h10"/><path d="M12 11.6v4.2M9.9 13.7h4.2"/>',

        rag: '<path d="M4 7c3-2 5 1 8-1s5 1 8-1v10c-3 2-5-1-8 1s-5-1-8 1Z"/><path d="M8 9v7M16 8v7"/>',
        tourniquet: '<path d="M5 12a7 4 0 1 0 14 0a7 4 0 1 0-14 0"/><path d="M10 8.5h4v7h-4z"/><path d="M12 8.5V4"/>',
        splint: '<path d="M7 3h3v18H7zM14 3h3v18h-3z"/><path d="M5 8h14M5 16h14"/>',
        antiviral: '<path d="M4 20l3-3"/><path d="M6 15.5 15.5 6l2.5 2.5L8.5 18Z"/><path d="M16.5 5l2.5 2.5"/><circle cx="18" cy="17" r="2.5"/><path d="M18 13.5v1M18 19.5v1M14.5 17h1M20.5 17h1"/>',
        painkillers: '<rect x="6" y="4" width="12" height="16" rx="2"/><path d="M6 8h12"/><circle cx="10" cy="13" r="1.4"/><circle cx="14" cy="16" r="1.4"/>',
        saline: '<path d="M7 4h10v11a5 5 0 0 1-10 0Z"/><path d="M12 20v2M10 9h4M12 7v4"/>',
        blood_bag: '<path d="M7 4h10v11a5 5 0 0 1-10 0Z"/><path d="M12 20v2"/><path d="M12 8s2.2 2.4 2.2 3.9a2.2 2.2 0 0 1-4.4 0C9.8 10.4 12 8 12 8Z"/>',
        transfusion_kit: '<rect x="3.5" y="8" width="17" height="11" rx="1.5"/><path d="M9 8V6h6v2"/><path d="M7 13.5c2-2 4 2 6 0s3-1 4 0"/>',
        surgical_kit: '<rect x="3.5" y="7" width="17" height="12" rx="1.5"/><path d="M7 15l5-5M10 10l2 0 0 2"/><path d="M14 11l3 3"/>',
        defibrillator: '<rect x="3.5" y="6" width="17" height="13" rx="1.5"/><path d="M5.5 12.5h3l1.5-3 2 6 1.5-3h5"/>',

        // food, drink
        water_bottle:
            '<path d="M10 3.2h4v2l1.3 1.6a2.6 2.6 0 0 1 .6 1.7v10.1a2.4 2.4 0 0 1-2.4 2.4h-3a2.4 2.4 0 0 1-2.4-2.4V8.5a2.6 2.6 0 0 1 .6-1.7L10 5.2Z"/>' +
            '<path d="M8.1 12.4c1.4-.9 2.5-.9 3.9 0s2.5.9 3.9 0"/><path d="M8.1 15.4c1.4-.9 2.5-.9 3.9 0s2.5.9 3.9 0"/>',
        canned_food:
            '<ellipse cx="12" cy="6.4" rx="6" ry="2.4"/>' +
            '<path d="M6 6.4v11.2c0 1.3 2.7 2.4 6 2.4s6-1.1 6-2.4V6.4"/>' +
            '<path d="M8.6 10.8h6.8M8.6 13.6h6.8"/>',

        // weapons
        pistol:
            '<path d="M3.6 8.4h13.2l3.6 1.6v2.4h-4.2l-1.5 2.2H10l-1 4.2a1.4 1.4 0 0 1-1.4 1.1H6.2l1.4-5.3H4.4a1.4 1.4 0 0 1-1.4-1.4Z"/>' +
            '<path d="M15.4 10v2.4"/>',
        revolver:
            '<path d="M3.8 9h11.6l4.4 1.5v2.2h-3.6l-1.3 2H9.6l-.9 3.9a1.3 1.3 0 0 1-1.3 1H5.9L7.2 14.7H4.9A1.1 1.1 0 0 1 3.8 13.6Z"/>' +
            '<circle cx="9.4" cy="11.5" r="1.9"/>',
        smg:
            '<path d="M2.6 8h15.8l3 1v2.6h-4.5l-1 1.9h-3.3l-.9 4.4a1.3 1.3 0 0 1-1.3 1H8.7l1.1-5.4H4.1A1.5 1.5 0 0 1 2.6 12Z"/>' +
            '<path d="M6.6 12.2v5.6"/><path d="M13.5 8v3"/>',
        pump_shotgun:
            '<path d="M2.2 9.6h18.6v2.2H2.2Z"/>' +
            '<path d="M2.2 11.8 6 18.4a1.2 1.2 0 0 0 1 .6h1.3L6.4 11.8"/>' +
            '<path d="M9.6 11.8h4.6v2.2H9.6Z"/><path d="M15.2 9.6V7.8"/>',
        carbine:
            '<path d="M2.4 9h17.2l2 .8v2.4h-4l-1.1 2H12l-1 4.6a1.3 1.3 0 0 1-1.3 1H8.2L9.4 14.2H4A1.6 1.6 0 0 1 2.4 12.6Z"/>' +
            '<path d="M6.4 14.2v4.8"/><path d="M12.8 9V6.6h2.6V9"/><path d="M17 9v-1.6"/>',
        hunting_rifle:
            '<path d="M2 10.4h19.4v1.8H2Z"/>' +
            '<path d="M2 12.2 5.4 18a1.3 1.3 0 0 0 1.1.7h1.2L5.9 12.2"/>' +
            '<path d="M9 10.4V8.2h5.6v2.2"/><path d="M10.4 8.2V6.6h3.2v1.6"/>',
        hunting_knife:
            '<path d="M13.6 3.4 20 9.8l-8.6 8.6-2.6-2.6Z"/>' +
            '<path d="m8.8 15.8-2.4 2.4a1.7 1.7 0 0 1-2.4-2.4l2.4-2.4Z"/>' +
            '<path d="M13.6 3.4 11 12.2"/>',
        machete:
            '<path d="M4.4 4.2c5.6 1.2 10.6 4.4 14 9.2l-2.6 2.2C12.4 11 8.8 7.6 4.4 4.2Z"/>' +
            '<path d="m15.8 15.6 2.6 2.6a1.6 1.6 0 0 1-2.2 2.2l-2.6-2.6Z"/>',
        hatchet:
            '<path d="M13.8 3.4c3.4.4 6 2.8 6.6 6.2-2.8 1.2-5.6 1-8.2-.6-1.4-.9-1.8-3.4 1.6-5.6Z"/>' +
            '<path d="m11.4 9.6-7 8.6a1.5 1.5 0 0 0 2.2 2l7.6-7.8"/>',
        crowbar:
            '<path d="M6.6 20.4 16.2 7.2"/>' +
            '<path d="M16.2 7.2c-.8-1.6-.3-3.2 1.4-3.9 1.7-.7 3.3.2 3.7 1.9"/>' +
            '<path d="M5 19.2l2.8 2"/>',
        reinforced_bat:
            '<path d="M18.4 4.2c1.6 1.6 1.6 4.2-.4 6.2l-7.6 7.6-3.8-3.8 7.6-7.6c2-2 4.6-2 6.2-.4Z"/>' +
            '<path d="m6.6 14.2-2.4 2.4a1.9 1.9 0 0 0 0 2.8 1.9 1.9 0 0 0 2.8 0l2.4-2.4"/>' +
            '<path d="M13.4 7.4l1.6 1.6M11 9.8l1.6 1.6"/>',
        molotov:
            '<path d="M10.2 8.2h3.6l1.8 3.2a5.4 5.4 0 0 1-.6 6.2 4.6 4.6 0 0 1-6 0 5.4 5.4 0 0 1-.6-6.2Z"/>' +
            '<path d="M10.6 8.2V5.4h2.8v2.8"/>' +
            '<path d="M13.6 5.4c1.6-.4 2.6-1.4 2.4-3"/>',

        // ammo
        ammo_pistol:
            '<path d="M8 20.4V11l2-3.4V4.2h4v3.4l2 3.4v9.4Z"/>' +
            '<path d="M8 15.4h8"/><path d="M10 7.6h4"/>',
        ammo_magnum:
            '<path d="M8.4 20.4v-9l1.8-3.6V4.4h3.6v3.4l1.8 3.6v9Z"/>' +
            '<path d="M8.4 14.8h7.2M8.4 17.6h7.2"/>',
        ammo_shotgun:
            '<path d="M7.4 20.2V9.6h9.2v10.6Z"/>' +
            '<path d="M7.4 9.6V5.4a1.2 1.2 0 0 1 1.2-1.2h6.8a1.2 1.2 0 0 1 1.2 1.2v4.2"/>' +
            '<path d="M7.4 12.4h9.2"/>',
        ammo_rifle:
            '<path d="M8.2 20.4v-8.2l1.8-4V4.4h4v3.8l1.8 4v8.2Z"/>' +
            '<path d="M8.2 16h7.6"/><path d="M10 8.2h4"/>',

        // attachments
        att_suppressor:
            '<rect x="3.6" y="8.6" width="14.4" height="6.8" rx="1.6"/>' +
            '<path d="M18 10.4h2.4v3.2H18"/>' +
            '<path d="M7 8.6v6.8M10.4 8.6v6.8M13.8 8.6v6.8"/>',
        att_scope:
            '<rect x="3" y="8.4" width="18" height="7.2" rx="1.4"/>' +
            '<path d="M7.6 8.4v7.2M16.4 8.4v7.2"/>' +
            '<path d="M12 9.8v4.4M9.8 12h4.4"/><path d="M8.4 17.4h7.2v1.8H8.4Z"/>',
        att_grip:
            '<path d="M4.4 5.4h15.2v3.2H4.4Z"/>' +
            '<path d="M9.6 8.6v6.8a2.4 2.4 0 0 0 4.8 0V8.6"/>' +
            '<path d="M9.6 12h4.8"/>',
        flashlight:
            '<path d="M8 3.8h8v4H8Z"/>' +
            '<path d="M9.4 7.8v12a1.2 1.2 0 0 0 1.2 1.2h2.8a1.2 1.2 0 0 0 1.2-1.2v-12"/>' +
            '<path d="M12 11v2.6"/>',
        att_flashlight:
            '<rect x="4" y="9" width="11" height="6" rx="1.2"/>' +
            '<path d="M15 10.2 20 7.4v9.2L15 13.8Z"/>' +
            '<path d="M7 15v3.4h4V15"/>',
        att_extmag:
            '<path d="M8 4.6h8l1.4 12.2a2.4 2.4 0 0 1-2.4 2.6H9a2.4 2.4 0 0 1-2.4-2.6Z"/>' +
            '<path d="M7.4 9h9.2M7.8 12.4h8.4M8.2 15.8h7.6"/>',

        // gear, materials
        armour_plate:
            '<path d="M12 3.4 20 6v6.4c0 4-3.2 7-8 8.2-4.8-1.2-8-4.2-8-8.2V6Z"/>' +
            '<path d="M12 6.6v11"/><path d="M6.6 8.4h10.8"/>',
        toolbox:
            '<path d="M3.4 9h17.2v9.6a1.4 1.4 0 0 1-1.4 1.4H4.8a1.4 1.4 0 0 1-1.4-1.4Z"/>' +
            '<path d="M9 9V6.8a1.4 1.4 0 0 1 1.4-1.4h3.2A1.4 1.4 0 0 1 15 6.8V9"/>' +
            '<path d="M3.4 13.2h17.2"/><path d="M10.4 11.8h3.2v3h-3.2Z"/>',
        scrap_metal:
            '<path d="m3.6 13.4 5-7.6 4.6 4-2 3.4 6.4-2 3.2 5.4-9.6 3.2Z"/>' +
            '<path d="m8.6 5.8 2.4 8.4"/>',
        cloth:
            '<path d="M4.2 6.4c2.6 2 5.2 2 7.8 0s5.2-2 7.8 0v11.2c-2.6-2-5.2-2-7.8 0s-5.2 2-7.8 0Z"/>' +
            '<path d="M4.2 12c2.6 2 5.2 2 7.8 0s5.2-2 7.8 0"/>',
        wood_plank:
            '<path d="M2.6 7.4h18.8v9.2H2.6Z"/>' +
            '<path d="M7.4 7.4v9.2M16.6 7.4v9.2"/>' +
            '<path d="M9.6 10c1.6.8 3.2.8 4.8 0M9.6 14c1.6-.8 3.2-.8 4.8 0"/>',
        zombie_teeth:
            '<path d="M4.4 6.6h15.2v3.8c0 1-.8 1.8-1.8 1.8H6.2c-1 0-1.8-.8-1.8-1.8Z"/>' +
            '<path d="m7 12.2 1.4 4.6L9.8 12.2M12 12.2l1.4 5.8 1.4-5.8"/>',

        // vehicle parts
        fuel_can:
            '<path d="M5.4 6.6h9.2v13.2a1 1 0 0 1-1 1H6.4a1 1 0 0 1-1-1Z"/>' +
            '<path d="M7.4 6.6V4.8h5.2v1.8"/>' +
            '<path d="M14.6 9.4h2.8a1.6 1.6 0 0 1 1.6 1.6v6"/>' +
            '<path d="M7.6 10.2h4.8v3.4H7.6Z"/>',
        engine_part:
            '<path d="M3.4 10.2h3.2V7.8h5.6v2.4h3l2.4 2.4h2.8v4.8h-3l-2.2 2.2H6.6v-2.4H3.4Z"/>' +
            '<path d="M8.2 4.6h3.6v3.2H8.2Z"/><path d="M9 13.4h4.4"/>',
        battery:
            '<path d="M3.6 8.6h16.8v9.2a1.2 1.2 0 0 1-1.2 1.2H4.8a1.2 1.2 0 0 1-1.2-1.2Z"/>' +
            '<path d="M6.6 8.6V6.4h2.8v2.2M14.6 8.6V6.4h2.8v2.2"/>' +
            '<path d="M7.2 13.6h3M8.7 12.1v3M14 13.6h3"/>',
        spark_plug:
            '<path d="M10.6 2.6h2.8v2.2h-2.8Z"/><path d="M9.6 4.8h4.8v6.4H9.6Z"/>' +
            '<path d="M9.6 6.8h4.8M9.6 8.8h4.8"/><path d="M8.2 11.2h7.6v3H8.2Z"/>' +
            '<path d="M9.4 14.2h5.2v4.4H9.4ZM9.4 15.8l5.2-.8M9.4 17.4l5.2-.8"/>' +
            '<path d="M12 18.6v1.8M13.8 18.6v2.8h-1.8"/>',
        fuel_tank:
            '<path d="M3.6 8.4a1.6 1.6 0 0 1 1.6-1.6h13.6a1.6 1.6 0 0 1 1.6 1.6v8.4a1.6 1.6 0 0 1-1.6 1.6H5.2a1.6 1.6 0 0 1-1.6-1.6Z"/>' +
            '<path d="M6.4 4.6h3v2.2h-3Z"/><path d="M9.6 6.8v11.6M14.4 6.8v11.6"/>' +
            '<path d="M6 18.4v1.6M18 18.4v1.6"/>',
        brake_pads:
            '<circle cx="12" cy="12" r="7.6"/><circle cx="12" cy="12" r="2.6"/>' +
            '<path d="M12 4.4v3M12 16.6v3M4.4 12h3M16.6 12h3"/>',
        tyre:
            '<circle cx="12" cy="12" r="8.4"/><circle cx="12" cy="12" r="3.6"/>' +
            '<path d="M12 3.6v4.8M12 15.6v4.8M3.6 12h4.8M15.6 12h4.8"/>',
        repair_kit:
            '<path d="M3.6 8.8h16.8v9.6a1.3 1.3 0 0 1-1.3 1.3H4.9a1.3 1.3 0 0 1-1.3-1.3Z"/>' +
            '<path d="M9 8.8V6.6a1.3 1.3 0 0 1 1.3-1.3h3.4A1.3 1.3 0 0 1 15 6.6v2.2"/>' +
            '<path d="m9.6 15.4 4.8-4.8M9.6 10.6l4.8 4.8"/>',
        lockpick:
            '<path d="M3.4 14.6 13 5"/><path d="m3.4 14.6 1.4 3.2 3.2 1.4 1.6-1.6-3-1.4-1.6-3Z"/>' +
            '<path d="M13 5a3.4 3.4 0 0 1 4.8 0 3.4 3.4 0 0 1 0 4.8l-2 2-4.8-4.8Z"/>',
        _vehicle:
            '<path d="M3.4 14.4h17.2v3.2a1 1 0 0 1-1 1h-1.4v1.2h-2.6v-1.2H9.4v1.2H6.8v-1.2H4.4a1 1 0 0 1-1-1Z"/>' +
            '<path d="m5.4 14.4 2-5a2 2 0 0 1 1.9-1.3h5.4a2 2 0 0 1 1.9 1.3l2 5"/>' +
            '<path d="M6.6 16.4h2M15.4 16.4h2"/>',

        // Struck coin drawn in the same line-art style as the rest of the set.
        vip_coin:
            '<circle cx="12" cy="12" r="8.4"/><circle cx="12" cy="12" r="6"/>' +
            '<path d="M12 8.6l1.05 2.4 2.55.25-1.92 1.75.55 2.55L12 14.3l-2.23 1.25.55-2.55L8.4 11.25l2.55-.25Z"/>',

        // categories and misc
        _weapon:
            '<path d="M3 9.2h14.4l3.6 1.4v2.4h-4.2l-1.4 2H11l-1 4.4a1.3 1.3 0 0 1-1.3 1H7.2l1.3-5.4H4.4A1.4 1.4 0 0 1 3 13.2Z"/>',
        _medical:
            '<path d="M3.6 8.6h16.8v10.2a1.4 1.4 0 0 1-1.4 1.4H5a1.4 1.4 0 0 1-1.4-1.4Z"/>' +
            '<path d="M12 11.4v5.4M9.4 14.1h5.2"/><path d="M9 8.6V6.2a1.4 1.4 0 0 1 1.4-1.4h3.2A1.4 1.4 0 0 1 15 6.2v2.4"/>',
        _food:
            '<path d="M6.6 4.2v7.2a2.6 2.6 0 0 0 5.2 0V4.2"/><path d="M9.2 11.4v8.4"/>' +
            '<path d="M17 4.2c1.8 1 2.6 3 2.4 5.4-.2 2-1 3-2.4 3.2v7"/>',
        _drink:
            '<path d="M7.4 4.6h9.2l-1.2 14a1.6 1.6 0 0 1-1.6 1.4h-3.6a1.6 1.6 0 0 1-1.6-1.4Z"/>' +
            '<path d="M7.9 10.4h8.2"/>',
        _ammo:
            '<path d="M8 20.4V11l2-3.4V4.2h4v3.4l2 3.4v9.4Z"/><path d="M8 15.4h8"/>',
        _material:
            '<path d="m12 3.6 8 4.4v8l-8 4.4-8-4.4v-8Z"/><path d="m12 12.4 8-4.4M12 12.4v8M12 12.4 4 8"/>',
        _tool:
            '<path d="M14.6 3.6a4.8 4.8 0 0 0-4 7.4L4 17.6a1.9 1.9 0 0 0 2.6 2.6l6.6-6.6a4.8 4.8 0 0 0 6-6.4l-2.8 2.8-2.6-.6-.6-2.6Z"/>',
        _attachment:
            '<rect x="3.6" y="9" width="13.8" height="6" rx="1.4"/><path d="M17.4 10.6h3v2.8h-3"/>' +
            '<path d="M7 9v6M10.6 9v6"/>',
        _trophy:
            '<path d="M8 4.4h8v4.2a4 4 0 0 1-8 0Z"/><path d="M8 5.6H5.2v1.6a2.8 2.8 0 0 0 2.8 2.8M16 5.6h2.8v1.6a2.8 2.8 0 0 1-2.8 2.8"/>' +
            '<path d="M12 12.6v4.2M9 19.6h6"/>',
        _gear:
            '<path d="M12 3.4 20 6v6.4c0 4-3.2 7-8 8.2-4.8-1.2-8-4.2-8-8.2V6Z"/>',
        // Clothing: collar notch and sleeve points keep it readable as a shirt at 24px.
        _clothing:
            '<path d="M9 3.6 6 5 3.4 7.4l2 2.6 1.6-1.2v11.6h10V8.8l1.6 1.2 2-2.6L18 5l-3-1.4"/>' +
            '<path d="M9 3.6a3 3 0 0 0 6 0"/>',
        _misc:
            '<path d="M3.6 7.6 12 4.2l8.4 3.4v8.8L12 19.8 3.6 16.4Z"/>' +
            '<path d="M3.6 7.6 12 11m0 0 8.4-3.4M12 11v8.8"/>',
    };

    const CATEGORY_KEY = {
        weapon: '_weapon', medical: '_medical', food: '_food', drink: '_drink',
        ammo: '_ammo', material: '_material', tool: '_tool',
        attachment: '_attachment', trophy: '_trophy', gear: '_gear',
        clothing: '_clothing',
        booster: '_booster',
        gadget: '_booster',
        drug: '_drug',
        vehicle: '_vehicle',
    };

    // Painted art: real raster icons, one file per item, served from bs_ui's img/ folder via the nui:// path. The line-art SVGs above are the fallback for anything without an entry here. Two subfolders so sources do not overwrite each other: img/weapons/ (IconPack, GTA V weapon-class art) and img/items/.
    const IMG_BASE = 'nui://bs_ui/html/img/';

    const IMG = {
        // weapons/ (old IconPack). Filenames do not describe the art: assault_rifle_01.png is a break-action long gun, so the mapping follows the pictures, not the names.
        pistol:         'weapons/handgun_01.png',
        revolver:       'weapons/handgun_09.png',
        smg:            'weapons/submachine_gun_09.png',
        pump_shotgun:   'weapons/shotgun_01.png',
        carbine:        'weapons/submachine_gun_09.png',
        hunting_rifle:  'weapons/sniper_09.png',
        hunting_knife:  'weapons/short_bladed_melee_01.png',
        machete:        'weapons/long_bladed_melee_09.png',
        reinforced_bat: 'weapons/blunt_melee_01.png',
        molotov:        'weapons/explosives_throwable_01.png',

        // Admin-menu weapons that gained inventory items. They reuse the closest sprite in the same pack.
        combat_pistol:  'weapons/handgun_01.png',
        sawn_off:       'weapons/shotgun_01.png',
        // assault_rifle_01.png is a break-action, not a rifle, so the automatic sprite is used here.
        assault_rifle:  'weapons/submachine_gun_09.png',
        marksman:       'weapons/sniper_09.png',
        hammer:         'weapons/blunt_melee_09.png',

        // items/ - SwisserDev fivem-inventory-icons (CC0-1.0)
        crowbar:        'items/crowbar.png',
        armour_plate:   'items/armor.png',
        bandage:        'items/bandage.png',
        cloth:          'items/cloth.png',
        att_extmag:     'items/extended_magazine.png',
        att_flashlight: 'items/flashlight_attachment.png',
        att_grip:       'items/grip_attachment.png',
        fuel_can:       'items/jerry_can.png',
        lockpick:       'items/lockpick.png',
        medkit:         'items/medkit.png',
        scrap_metal:    'items/metalscrap.png',
        ammo_pistol:    'items/pistol_ammo.png',
        repair_kit:     'items/repairkit.png',
        ammo_rifle:     'items/rifle_ammo.png',
        ammo_shotgun:   'items/shotgun_ammo.png',
        att_scope:      'items/smallscope_attachment.png',
        att_suppressor: 'items/suppressor_attachment.png',
        toolbox:        'items/toolbox.png',
        brake_pads:     'items/veh_brakes.png',
        engine_part:    'items/veh_engine.png',
        tyre:           'items/veh_wheels.png',
        water_bottle:   'items/water_bottle.png',
        wood_plank:     'items/wood_plank.png',
    };


    Object.assign(IMG, {
        bandage: 'xanderp/items/bandage.png', medkit: 'xanderp/items/medkit.png',
        water_bottle: 'xanderp/items/water_bottle.png', canned_food: 'xanderp/items/canned_food.png',
        antiseptic: 'xanderp/items/antiseptic.png', antibiotics: 'xanderp/items/antibiotics.png',
        armour_plate: 'xanderp/items/armour_plate.png', zombie_teeth: 'xanderp/items/zombie_teeth.png',
        scrap_metal: 'xanderp/items/scrap_metal.png', cloth: 'xanderp/items/cloth.png',
        wood_plank: 'xanderp/items/wood_plank.png', copper: 'xanderp/items/copper.png',
        electrical_wire: 'xanderp/items/electrical_wire.png', toolbox: 'xanderp/items/toolbox.png',
        vip_coin: 'xanderp/items/vip_coin.png'
    });


    Object.assign(IMG, {
        // Garment icons for the clothing items.
        hiking_pack:'xanderp/clothing/hiking_pack.png', armour_plate:'xanderp/clothing/armour_plate.png',
        // Backpack tiers and vests reuse the pack / vest art until they get their own.
        pack_small:'xanderp/clothing/hiking_pack.png', pack_medium:'xanderp/clothing/hiking_pack.png',
        pack_large:'xanderp/clothing/hiking_pack.png', pack_military:'xanderp/clothing/hiking_pack.png',
        vest_tactical:'xanderp/clothing/plain_vest.png', vest_plate:'xanderp/clothing/armour_plate.png'
    });

    Object.assign(IMG, {
        hunting_knife: 'xanderp/weapons/hunting_knife.png',
        machete: 'xanderp/weapons/machete.png',
        hatchet: 'xanderp/weapons/hatchet.png',
        reinforced_bat: 'xanderp/weapons/reinforced_bat.png',
        crowbar: 'xanderp/weapons/crowbar.png',
        pistol: 'xanderp/weapons/pistol.png',
        combat_pistol: 'xanderp/weapons/combat_pistol.png',
        revolver: 'xanderp/weapons/revolver.png',
        smg: 'xanderp/weapons/smg.png',
        pump_shotgun: 'xanderp/weapons/pump_shotgun.png',
        sawn_off: 'xanderp/weapons/sawn_off.png',
        carbine: 'xanderp/weapons/carbine.png',
        assault_rifle: 'xanderp/weapons/assault_rifle.png',
        marksman: 'xanderp/weapons/marksman.png',
        hunting_rifle: 'xanderp/weapons/hunting_rifle.png',
        hammer: 'xanderp/weapons/hammer.png'
    });

    Object.assign(IMG, {
        booster_drone: 'xanderp/items/booster_drone.png',
        booster_shield: 'xanderp/items/booster_shield.png',
        booster_turret: 'xanderp/items/booster_turret.png',
        booster_medic: 'xanderp/items/booster_medic.png',
        booster_decoy: 'xanderp/items/booster_decoy.png',
        booster_adrenaline: 'xanderp/items/booster_adrenaline.png',
        cocaine_bad: 'xanderp/items/cocaine_bad.png',
        cocaine: 'xanderp/items/cocaine.png',
        cocaine_good: 'xanderp/items/cocaine_good.png',
        morphine_bad: 'xanderp/items/morphine_bad.png',
        morphine: 'xanderp/items/morphine.png',
        morphine_good: 'xanderp/items/morphine_good.png',
        amphetamine_bad: 'xanderp/items/amphetamine_bad.png',
        amphetamine: 'xanderp/items/amphetamine.png',
        amphetamine_good: 'xanderp/items/amphetamine_good.png',
        weed_bad: 'xanderp/items/weed_bad.png',
        weed: 'xanderp/items/weed.png',
        weed_good: 'xanderp/items/weed_good.png',
        cigarette: 'xanderp/items/cigarette.png',
        lighter: 'xanderp/items/lighter.png',
        matches: 'xanderp/items/matches.png',
        rehab_kit: 'xanderp/items/rehab_kit.png',
        ammo_magnum: 'xanderp/items/ammo_magnum.png',
        att_laser: 'xanderp/items/att_laser.png',
        battery: 'xanderp/items/battery.png',
        empty_bottle: 'xanderp/items/empty_bottle.png',
        shovel: 'xanderp/items/shovel.png',
        pickaxe: 'xanderp/items/pickaxe.png',
        faction_flag: 'xanderp/items/faction_flag.png',
        molotov: 'xanderp/weapons/molotov.png'
    });

    Object.assign(IMG, {
        booster_focus: 'xanderp/items/booster_focus.png',
        booster_regen: 'xanderp/items/booster_regen.png',
        booster_fortify: 'xanderp/items/booster_fortify.png',
        fishing_rod: 'xanderp/items/fishing_rod.png',
        ammo_casing: 'xanderp/items/ammo_casing.png',
        angle_grinder: 'xanderp/items/angle_grinder.png',
        antibiotics_improved: 'xanderp/items/antibiotics_improved.png',
        bait: 'xanderp/items/bait.png',
        beacon_battery: 'xanderp/items/beacon_battery.png',
        bear_trap: 'xanderp/items/bear_trap.png',
        berries: 'xanderp/items/berries.png',
        big_fish: 'xanderp/items/big_fish.png',
        bird_meat: 'xanderp/items/bird_meat.png',
        boar_hide: 'xanderp/items/boar_hide.png',
        boar_meat: 'xanderp/items/boar_meat.png',
        bone: 'xanderp/items/bone.png',
        boombox: 'xanderp/items/boombox.png',
        coyote_pelt: 'xanderp/items/coyote_pelt.png',
        mtlion_pelt: 'xanderp/items/mtlion_pelt.png',
        burnt_meat: 'xanderp/items/burnt_meat.png',
        cassette: 'xanderp/items/cassette.png',
        cassette_blue: 'xanderp/items/cassette_blue.png',
        cassette_green: 'xanderp/items/cassette_green.png',
        cassette_red: 'xanderp/items/cassette_red.png',
        charcoal: 'xanderp/items/charcoal.png',
        contraband: 'xanderp/items/contraband.png',
        cooked_fish: 'xanderp/items/cooked_fish.png',
        cooked_meat: 'xanderp/items/cooked_meat.png',
        decoy_battery: 'xanderp/items/decoy_battery.png',
        deer_hide: 'xanderp/items/deer_hide.png',
        deer_meat: 'xanderp/items/deer_meat.png',
        dirty_water: 'xanderp/items/dirty_water.png',
        dog_food: 'xanderp/items/dog_food.png',
        dog_saddlebag: 'xanderp/items/dog_saddlebag.png',
        drone_battery: 'xanderp/items/drone_battery.png',
        electronics: 'xanderp/items/electronics.png',
        faction_xp_token: 'xanderp/items/faction_xp_token.png',
        fertilizer: 'xanderp/items/fertilizer.png',
        fish_bass: 'xanderp/items/fish_bass.png',
        fish_catfish: 'xanderp/items/fish_catfish.png',
        fish_mackerel: 'xanderp/items/fish_mackerel.png',
        fish_salmon: 'xanderp/items/fish_salmon.png',
        fish_trout: 'xanderp/items/fish_trout.png',
        gas_filter: 'xanderp/items/gas_filter.png',
        gas_mask: 'xanderp/items/gas_mask.png',
        glue: 'xanderp/items/glue.png',
        gun_parts: 'xanderp/items/gun_parts.png',
        gunpowder: 'xanderp/items/gunpowder.png',
        head_sack: 'xanderp/items/head_sack.png',
        herb_seeds: 'xanderp/items/herb_seeds.png',
        herbs: 'xanderp/items/herbs.png',
        infected_blood: 'xanderp/items/infected_blood.png',
        iron_ore: 'xanderp/items/iron_ore.png',
        journal: 'xanderp/items/journal.png',
        junk_battery: 'xanderp/items/junk_battery.png',
        junk_cables: 'xanderp/items/junk_cables.png',
        junk_camera: 'xanderp/items/junk_camera.png',
        junk_cans: 'xanderp/items/junk_cans.png',
        junk_chain: 'xanderp/items/junk_chain.png',
        junk_clock: 'xanderp/items/junk_clock.png',
        junk_fan: 'xanderp/items/junk_fan.png',
        junk_gears: 'xanderp/items/junk_gears.png',
        junk_glue: 'xanderp/items/junk_glue.png',
        junk_hairdryer: 'xanderp/items/junk_hairdryer.png',
        junk_kettle: 'xanderp/items/junk_kettle.png',
        junk_lamp: 'xanderp/items/junk_lamp.png',
        junk_laptop: 'xanderp/items/junk_laptop.png',
        junk_phone: 'xanderp/items/junk_phone.png',
        junk_pipe: 'xanderp/items/junk_pipe.png',
        junk_radio: 'xanderp/items/junk_radio.png',
        junk_remote: 'xanderp/items/junk_remote.png',
        junk_shoes: 'xanderp/items/junk_shoes.png',
        junk_spraycan: 'xanderp/items/junk_spraycan.png',
        junk_tape: 'xanderp/items/junk_tape.png',
        junk_toaster: 'xanderp/items/junk_toaster.png',
        lead: 'xanderp/items/lead.png',
        log: 'xanderp/items/log.png',
        meat_stew: 'xanderp/items/meat_stew.png',
        metal_pipe: 'xanderp/items/metal_pipe.png',
        nails: 'xanderp/items/nails.png',
        photo: 'xanderp/items/photo.png',
        plastic: 'xanderp/items/plastic.png',
        potato: 'xanderp/items/potato.png',
        potato_seeds: 'xanderp/items/potato_seeds.png',
        purification_tablet: 'xanderp/items/purification_tablet.png',
        rabbit_meat: 'xanderp/items/rabbit_meat.png',
        rabbit_pelt: 'xanderp/items/rabbit_pelt.png',
        rags: 'xanderp/items/rags.png',
        raw_meat: 'xanderp/items/raw_meat.png',
        rotten_flesh: 'xanderp/items/rotten_flesh.png',
        rubber: 'xanderp/items/rubber.png',
        safezone_flag: 'xanderp/items/safezone_flag.png',
        screwdriver: 'xanderp/items/screwdriver.png',
        screws: 'xanderp/items/screws.png',
        siphon_hose: 'xanderp/items/siphon_hose.png',
        sledgehammer: 'xanderp/items/sledgehammer.png',
        stone: 'xanderp/items/stone.png',
        sulfur: 'xanderp/items/sulfur.png',
        supply_crate: 'xanderp/items/supply_crate.png',
        tape: 'xanderp/items/tape.png',
        tripwire_alarm: 'xanderp/items/tripwire_alarm.png',
        turret_battery: 'xanderp/items/turret_battery.png',
        vaccine: 'xanderp/items/vaccine.png',
        veggie_stew: 'xanderp/items/veggie_stew.png',
        vehicle_armour_plate: 'xanderp/items/vehicle_armour_plate.png',
        vehicle_plough: 'xanderp/items/vehicle_plough.png',
        vehicle_ram_bar: 'xanderp/items/vehicle_ram_bar.png',
        vehicle_roof_rack: 'xanderp/items/vehicle_roof_rack.png',
        vehicle_spotlight: 'xanderp/items/vehicle_spotlight.png',
        vehicle_trunk_expansion: 'xanderp/items/vehicle_trunk_expansion.png',
        vehicle_window_grate: 'xanderp/items/vehicle_window_grate.png',
        wires: 'xanderp/items/wires.png',
        wrench: 'xanderp/items/wrench.png',
        zip_ties: 'xanderp/items/zip_ties.png',
        zombie_bait: 'xanderp/items/zombie_bait.png',
        fish_bait: 'xanderp/items/fish_bait.png',
        raw_fish: 'xanderp/items/raw_fish.png',
        leather: 'xanderp/items/leather.png',
        duct_tape: 'xanderp/items/duct_tape.png',
        fuel_tank: 'xanderp/items/vehicle_fuel_tank.png',
        spark_plug: 'xanderp/items/spark_plug.png',
        jumper_cables: 'xanderp/items/jumper_cables.png',
        contract_board: 'xanderp/items/contract_board.png'
    });

    // The raw path data for an item, falling back to its category.
    function art(item, category) {
        if (item && ART[item]) return ART[item];
        const key = CATEGORY_KEY[category];
        if (key && ART[key]) return ART[key];
        return ART._misc;
    }

    const Icons = {
        // A complete element for an item: a painted <img> if IMG has art for it, otherwise the line-art <svg>.
        get(item, category) {
            if (item && IMG[item]) {
                return '<img class="bs-icon bs-icon--art" alt="" draggable="false" src="'
                    + IMG_BASE + IMG[item] + '">';
            }
            return OPEN + art(item, category) + CLOSE;
        },

        // Inner markup only, for use inside your own <svg> wrapper. Line-art only; raster images have none.
        paths(item, category) { return art(item, category); },

        // True when this item has its own art (painted or line-art) rather than a fallback.
        has(item) { return !!(item && (IMG[item] || ART[item])); },

        /** Register art at runtime - used by resources that add their own items. */
        register(item, markup) { if (item && markup) ART[item] = markup; },

        /** Every item key that has its own drawing. For the icon audit. */
        keys() {
            return Array.from(new Set(Object.keys(ART).filter((k) => k[0] !== '_').concat(Object.keys(IMG))));
        },
    };

    global.BSIcons = Icons;
})(window);
