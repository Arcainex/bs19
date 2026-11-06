// icons.js - item icon set. Inline SVG line art (no downloads, no licence), single-weight stencil style, coloured by the surrounding CSS. Loaded across resources as nui://bs_ui/html/js/icons.js.
(function (global) {
    'use strict';

    const OPEN = '<svg viewBox="0 0 24 24" class="bs-icon" aria-hidden="true" ' +
        'fill="none" stroke="currentColor" stroke-width="1.4" ' +
        'stroke-linecap="round" stroke-linejoin="round">';
    const CLOSE = '</svg>';

    // Each entry is the inside of the svg, as raw path data.
    const ART = {
        sticks: '<path d="M5 20 16 4M10 13l-5-4M12 10l7 1M9 19l11-9"/>',
        leaves: '<path d="M5 20C3 8 10 3 21 3c0 12-5 18-16 17ZM5 20 17 7M9 15l-1-5M12 12l5 1"/>',
        cranberries: '<circle cx="8" cy="14" r="4"/><circle cx="16" cy="14" r="4"/><circle cx="12" cy="19" r="3"/><path d="M12 10V4M12 7c-4 0-6-2-6-4 4 0 6 1 6 4ZM12 7c4 0 6-2 6-4-4 0-6 1-6 4Z"/>',
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

    function sidearmArt(barrel, magazine, sight) {
        return '<path d="M3 8.5h' + barrel + 'l2 1v2.6h-3l-1.5 2H10l-1 5H6.5l1-5H4.5L3 12Z"/>' +
            (magazine ? '<path d="M8 14.2 7.1 20h3l1.2-5.8"/>' : '') +
            (sight ? '<path d="M9 8.5V6.8h5v1.7M11 5.8h1"/>' : '<path d="M5 7.4v1.1M14 7.4v1.1"/>');
    }

    function longGunArt(stock, magazine, sight, muzzle) {
        return '<path d="M2.2 9h18.6v2.3H2.2Z"/>' +
            (stock ? '<path d="M2.2 11.3 4.4 17h3l-1.3-5.7"/>' : '<path d="M2.2 11.3v3.5h3v-3.5"/>') +
            (magazine ? '<path d="M10 11.3 9.5 17.8h3l1.2-6.5"/>' : '<path d="M10.2 11.3v2.2h4v-2.2"/>') +
            (sight ? '<path d="M10.1 9V6.9h5.1V9M11.2 6.9V5.5h2.7v1.4"/>' : '<path d="M16.3 7.5V9"/>') +
            (muzzle ? '<path d="M20.8 8.2H23v4h-2.2"/>' : '<path d="M20.8 8.4v3.5"/>');
    }

    function heavyGunArt(box, bipod, sight) {
        return '<path d="M2 8.2h19.6v3.2H2Z"/><path d="M2 11.4 4.3 18h3.3l-1.5-6.6"/>' +
            (box ? '<path d="M9 11.4h5.4v6.2H9Z"/><path d="M10 13h3.4M10 15h3.4"/>' : '<path d="M10 11.4 9.3 18h3.1l1.4-6.6"/>') +
            (bipod ? '<path d="m18.5 11.4-2 7M18.5 11.4l3 7"/>' : '<path d="M17 11.4v2.1"/>') +
            (sight ? '<path d="M10 8.2V6h6v2.2"/>' : '<path d="M15.5 7v1.2"/>');
    }

    Object.assign(ART, {
        ap_pistol: sidearmArt(14, true, false) + '<path d="M12 12.1h3"/>',
        heavy_pistol: sidearmArt(16, false, false) + '<path d="M4 10h8"/>',
        vintage_pistol: sidearmArt(13, false, false) + '<path d="M4.5 12h4"/>',
        pistol_50: sidearmArt(17, false, true) + '<path d="M16 10h2"/>',
        pistol_mk2: sidearmArt(15, true, true) + '<path d="M4 10h6"/>',
        sns_pistol_mk2: sidearmArt(12, false, true) + '<path d="M4 10h3"/>',
        revolver_mk2: sidearmArt(15, false, true) + '<circle cx="9.5" cy="11" r="1.8"/>',
        micro_smg: sidearmArt(17, true, false) + '<path d="M5 14v4"/>',
        assault_smg: sidearmArt(19, true, true) + '<path d="M5 14v4"/>',
        machine_pistol: sidearmArt(18, true, false) + '<path d="M15 12v3"/>',
        advanced_rifle: longGunArt(true, true, true, true) + '<path d="M7 10.2h2"/>',
        special_carbine: longGunArt(true, true, true, false) + '<path d="M17 9h2"/>',
        bullpup_rifle: longGunArt(true, false, true, true) + '<path d="M7 13h2"/>',
        compact_rifle: longGunArt(false, true, false, true) + '<path d="M6 9v2.3"/>',
        military_rifle: longGunArt(true, true, true, true) + '<path d="M15.9 9v2.3"/>',
        combat_pdw: longGunArt(false, true, true, false) + '<path d="M6 11.3v3"/>',
        gusenberg: longGunArt(true, false, false, true) + '<circle cx="12" cy="14.7" r="2.2"/>',
        assault_rifle_mk2: longGunArt(true, true, true, true) + '<path d="M17 7.7V9"/>',
        carbine_mk2: longGunArt(true, true, true, false) + '<path d="M7.2 9v2.3"/>',
        special_carbine_mk2: longGunArt(true, true, true, true) + '<path d="M17 9h2"/>',
        bullpup_rifle_mk2: longGunArt(true, false, true, true) + '<path d="M7 13h2M17 7.7V9"/>',
        smg_mk2: longGunArt(false, true, true, true) + '<path d="M5 11.3v3"/>',
        assault_shotgun: longGunArt(true, false, false, true) + '<path d="M14 12h3"/>',
        bullpup_shotgun: longGunArt(false, false, true, true) + '<path d="M6 11.3v4"/>',
        heavy_shotgun: heavyGunArt(false, false, false) + '<path d="M20 7v1.2"/>',
        pump_shotgun_mk2: longGunArt(true, false, true, false) + '<path d="M14 12h4"/>',
        musket: '<path d="M2 10h20v1.5H2Z"/><path d="M2 11.5 5 18h2l-1.3-6.5"/><path d="M17 8v2M19.4 8v2"/>',
        heavy_sniper: heavyGunArt(false, true, true) + '<path d="M19 7.2v1"/>',
        heavy_sniper_mk2: heavyGunArt(false, true, true) + '<path d="M18 6.3v1.9M20 7.2v1"/>',
        marksman_mk2: longGunArt(true, false, true, true) + '<path d="M17 11.3v4"/>',
        mg: heavyGunArt(true, true, false) + '<path d="M5 9.5h3"/>',
        combat_mg: heavyGunArt(true, true, true) + '<path d="M5 9.5h3"/>',
        combat_mg_mk2: heavyGunArt(true, true, true) + '<path d="M5 9.5h3M18 7v1.2"/>',
        att_muzzle_brake: '<path d="M3 9h18v6H3Z"/><path d="M7 9v6M12 9v6M17 9v6M20 10.5h2M20 13.5h2"/>',
        att_reflex: '<path d="M4 18h16v2H4Z"/><path d="M7 18v-8a5 5 0 0 1 10 0v8"/><path d="M12 10v5M9.5 12.5h5"/>',
        att_scope_long: '<path d="M2 9h20v6H2Z"/><path d="M5 9v6M19 9v6M9 15v3h6v-3M12 10v4M10 12h4"/>',
    });

    Object.assign(ART, {
        axe: '<path d="M11 3v18h2V3Z"/><path d="M11 5C7 4 4 6 2 9c2 2 5 3 9 2M13 5c4-1 7 1 9 4-2 2-5 3-9 2"/>',
        c4: '<rect x="3" y="5" width="18" height="14" rx="1"/><path d="M6 9h5v6H6zM14 8h4v3h-4zM14 14h4M5 19v2M19 19v2"/>',
        copper: '<path d="M4 16l4-8 9-3 3 9-6 5-9 1Z"/><path d="m8 8 4 7 8-1M12 15l2 4"/>',
        pipe_bomb: '<path d="M5 8h14v9H5zM3 10h2v5H3zM19 10h2v5h-2zM9 8V5h5l2-2M8 12h8M8 15h5"/>',
        pipe_pistol: sidearmArt(13, false, false) + '<path d="M4 9h11M13 8v4M16 12h4"/>',
        pipe_shotgun: longGunArt(true, false, false, false) + '<path d="M4 9h17M18 8v4M12 11v4"/>',
        spiked_bat: '<path d="m5 19 12-15 3 3L8 22zM12 8l-2-4M16 7l1-4M17 11l4-1M13 13l3 2"/>',
    });

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

    // Painted art: real raster icons, one file per item, served from bs_ui's img/ folder via the nui:// path.
    const IMG_BASE = 'nui://bs_ui/html/img/';

    const IMG = {
        // weapons/ (old IconPack): filenames do not describe the art: assault_rifle_01.png is a break-action long gun
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
        hiking_pack:'xanderp/clothing/hiking_pack-bs19-20261026.png', armour_plate:'xanderp/clothing/armour_plate.png',
        // Keep retired pack icons for saved inventories and staff item lists.
        pack_small:'xanderp/clothing/pack_civilian.png', pack_medium:'xanderp/clothing/pack_hiking.png',
        pack_large:'xanderp/clothing/pack_survival.png', pack_military:'xanderp/clothing/pack_field_military.png',
        pack_civilian:'xanderp/clothing/pack_civilian.png', pack_hiking:'xanderp/clothing/pack_hiking.png',
        pack_survival:'xanderp/clothing/pack_survival.png', pack_field_military:'xanderp/clothing/pack_field_military.png',
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
        compact_rifle: 'xanderp/weapons/compact_rifle.png',
        advanced_rifle: 'xanderp/weapons/advanced_rifle.png',
        ap_pistol: 'xanderp/weapons/ap_pistol.png',
        assault_rifle_mk2: 'xanderp/weapons/assault_rifle_mk2.png',
        assault_shotgun: 'xanderp/weapons/assault_shotgun.png',
        assault_smg: 'xanderp/weapons/assault_smg.png',
        bullpup_rifle: 'xanderp/weapons/bullpup_rifle.png',
        bullpup_rifle_mk2: 'xanderp/weapons/bullpup_rifle_mk2.png',
        bullpup_shotgun: 'xanderp/weapons/bullpup_shotgun.png',
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
        vehicle_inverter: 'xanderp/items/electronics.png',
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

    Object.assign(IMG, {radio:'xanderp/items/radio-bs19-20261026.png',radio_advanced:'xanderp/items/radio_advanced-bs19-20261026.png',radio_military:'xanderp/items/radio_military-bs19-20261026.png',portable_antenna:'xanderp/items/portable_antenna-bs19-20261026.png'});

    // Dark Zone items (bs_darkzone): tinted copies of existing art.
    Object.assign(IMG, {
        dz_flare: 'xanderp/items/dz_flare.png',
        dz_intel: 'xanderp/items/dz_intel.png',
        dz_sample: 'xanderp/items/dz_sample.png',
        dz_pdw_warden: 'xanderp/items/dz_pdw_warden.png',
        dz_rifle_revenant: 'xanderp/items/dz_rifle_revenant.png',
        dz_shotgun_breacher: 'xanderp/items/dz_shotgun_breacher.png',
        booster_dz_overdrive: 'xanderp/items/booster_dz_overdrive.png',
        booster_dz_ironhide: 'xanderp/items/booster_dz_ironhide.png',
        booster_dz_sentry: 'xanderp/items/booster_dz_sentry.png'
    });

    Object.assign(IMG, {
        "flashlight": "xanderp/items/flashlight-bs19-20261026.png",
        "transfusion_kit": "xanderp/items/transfusion_kit-bs19-20261026.png",
        "saline": "xanderp/items/saline-bs19-20261026.png",
        "tourniquet": "xanderp/items/tourniquet-bs19-20261026.png",
        "splint": "xanderp/items/splint-bs19-20261026.png",
        "antiviral": "xanderp/items/antiviral-bs19-20261026.png",
        "leaves": "xanderp/items/leaves-bs19-20261026.png",
        "sticks": "xanderp/items/sticks-bs19-20261026.png",
        "rag": "xanderp/items/rag-bs19-20261026.png",
        "painkillers": "xanderp/items/painkillers-bs19-20261026.png",
        "cranberries": "xanderp/items/cranberries-bs19-20261026.png",
        "surgical_kit": "xanderp/items/surgical_kit-bs19-20261026.png",
        "defibrillator": "xanderp/items/defibrillator-bs19-20261026.png",
        "blood_bag": "xanderp/items/blood_bag-bs19-20261026.png",
        "pipe_pistol": "xanderp/items/pipe_pistol-bs19-20261026.png",
        "pipe_shotgun": "xanderp/items/pipe_shotgun-bs19-20261026.png",
        "axe": "xanderp/items/axe-bs19-20261026.png",
        "spiked_bat": "xanderp/items/spiked_bat-bs19-20261026.png",
        "pipe_bomb": "xanderp/items/pipe_bomb-bs19-20261026.png",
        "c4": "xanderp/items/c4-bs19-20261026.png"
});

    Object.assign(IMG,{
        att_custom_supp_scrap:'custom_attachments/att_custom_supp_scrap.png',
        att_custom_light_salvage:'custom_attachments/att_custom_light_salvage.png',
        att_custom_bayonet_mount:'custom_attachments/att_custom_bayonet_mount.png',
        att_custom_supp_compact:'custom_attachments/att_custom_supp_compact.png',
        att_custom_supp_long:'custom_attachments/att_custom_supp_long.png',
        att_custom_brake_ported:'custom_attachments/att_custom_brake_ported.png',
        att_custom_hider_cage:'custom_attachments/att_custom_hider_cage.png',
        att_custom_grip_angled:'custom_attachments/att_custom_grip_angled.png',
        att_custom_grip_wrap:'custom_attachments/att_custom_grip_wrap.png',
        att_custom_optic_micro:'custom_attachments/att_custom_optic_micro.png',
        att_custom_rail_offset:'custom_attachments/att_custom_rail_offset.png',
        att_custom_stock_brace:'custom_attachments/att_custom_stock_brace.png',
        att_custom_shroud_wire:'custom_attachments/att_custom_shroud_wire.png',
        att_factory_bipod_folded_03:'custom_attachments/att_factory_bipod_folded_03.png',
        att_factory_brake_radial_03:'custom_attachments/att_factory_brake_radial_03.png',
        att_factory_brake_threeport_03:'custom_attachments/att_factory_brake_threeport_03.png',
        att_factory_compensator_linear_03:'custom_attachments/att_factory_compensator_linear_03.png',
        att_factory_grip_stubby_03:'custom_attachments/att_factory_grip_stubby_03.png',
        att_factory_grip_swept_03:'custom_attachments/att_factory_grip_swept_03.png',
        att_factory_grip_vertical_03:'custom_attachments/att_factory_grip_vertical_03.png',
        att_factory_handguard_quad_03:'custom_attachments/att_factory_handguard_quad_03.png',
        att_factory_handguard_vented_03:'custom_attachments/att_factory_handguard_vented_03.png',
        att_factory_handstop_hook_03:'custom_attachments/att_factory_handstop_hook_03.png',
        att_factory_hider_closed_03:'custom_attachments/att_factory_hider_closed_03.png',
        att_factory_laser_compact_03:'custom_attachments/att_factory_laser_compact_03.png',
        att_factory_light_compact_03:'custom_attachments/att_factory_light_compact_03.png',
        att_factory_optic_holo_03:'custom_attachments/att_factory_optic_holo_03.png',
        att_factory_optic_precision_03:'custom_attachments/att_factory_optic_precision_03.png',
        att_factory_optic_prism_03:'custom_attachments/att_factory_optic_prism_03.png',
        att_factory_optic_reflex_03:'custom_attachments/att_factory_optic_reflex_03.png',
        att_factory_rail_bridge_03:'custom_attachments/att_factory_rail_bridge_03.png',
        att_factory_stock_precision_03:'custom_attachments/att_factory_stock_precision_03.png',
        att_factory_stock_telescopic_03:'custom_attachments/att_factory_stock_telescopic_03.png',
        att_factory_suppressor_integral_03:'custom_attachments/att_factory_suppressor_integral_03.png',
        att_factory_suppressor_qd_03:'custom_attachments/att_factory_suppressor_qd_03.png',
        att_factory_suppressor_rect_03:'custom_attachments/att_factory_suppressor_rect_03.png',
        att_factory_suppressor_slim_03:'custom_attachments/att_factory_suppressor_slim_03.png'
    });

    for (const id of Object.keys(IMG)) {
        if (id.startsWith('att_factory_') && id.endsWith('_03')) {
            IMG[id.slice(0, -3)] = IMG[id];
        }
    }

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

        /* Register art at runtime - used by resources that add their own items. */
        register(item, markup) { if (item && markup) ART[item] = markup; },

        /* Every item key that has its own drawing. For the icon audit. */
        keys() {
            return Array.from(new Set(Object.keys(ART).filter((k) => k[0] !== '_').concat(Object.keys(IMG))));
        },
    };

    global.BSIcons = Icons;
})(window);
