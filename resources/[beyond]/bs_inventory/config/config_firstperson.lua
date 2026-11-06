-- Optional on-foot camera. Vanilla remains the default for every player.
FirstPerson = {
    enabled = false,
    leanDistance = 0.22,
    leanRoll = 5.0,
    highSkillRecoil = 0.45,
    -- First authored weapon-only presentation. Other weapons keep their native fallback.
    viewmodel = {
        enabled=true, weapon='WEAPON_ASSAULTRIFLE', side=.19, forward=.46, height=-.22,
        showBody=true, eyeForward=.20,
        components={'COMPONENT_AT_AR_SUPP_02','COMPONENT_AT_AR_AFGRIP','COMPONENT_AT_AR_FLSH','COMPONENT_AT_SCOPE_MACRO','COMPONENT_ASSAULTRIFLE_CLIP_02','COMPONENT_ASSAULTRIFLE_CLIP_03'},
        classes={
            pistol={side=.18,forward=.38,height=-.20},
            smg={side=.19,forward=.42,height=-.22},
            rifle={side=.19,forward=.46,height=-.22},
            mg={side=.20,forward=.48,height=-.24},
            shotgun={side=.19,forward=.45,height=-.23},
            sniper={side=.19,forward=.52,height=-.24},
            heavy={side=.23,forward=.57,height=-.28},
            melee={side=.20,forward=.40,height=-.23},
        },
    },
    groups = {
        pistol={forward=0.015,height=0.0}, smg={forward=0.01,height=0.0},
        rifle={forward=0.0,height=0.005}, mg={forward=-0.01,height=0.005},
        shotgun={forward=-0.01,height=0.0}, sniper={forward=-0.015,height=0.0},
        heavy={forward=-0.02,height=0.01}, melee={forward=0.0,height=0.0},
        other={forward=0.0,height=0.0},
    },
    -- Native aiming is always available. Set enabled=false for incompatible models.
    weapons = {},
}
