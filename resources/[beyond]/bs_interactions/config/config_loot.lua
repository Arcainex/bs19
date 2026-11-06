-- Container type and explicit model rules determine loot. Nearby locations never change a prop's pool.
Scavenge = {
    difficulty='medium',
    presets={
        easy={rolls=1.5,firearms=1.5,parts=1.2,ammo=1.4,amount=1.25},
        medium={rolls=1.0,firearms=1.0,parts=1.0,ammo=1.0,amount=1.0},
        hard={rolls=.6,firearms=.35,parts=.65,ammo=.7,amount=.75},
    },
    categories={home='urban',shop='urban',kitchen='kitchen',travel='travel',office='office',parcel='parcel',warehouse='warehouse',
        industrial='industrial',medical='medical',vehicle='vehicle',workshop='workshop',fishing='fishing',safe='safe',
        police='police',military='military',weapon_storage='weapon_storage'},
    modelRules={},locations={},
    ground={enabled=false,maxVisible=24,streamDistance=65,respawn=1800,density=1,coverage='curated',points={},
        -- Outdoor placement candidates: terrain/interior/clearance checks run before rendering.
        -- Verify in your installed map before enabling. Expanded sites are opt-in in F1.
        zones={
            {id='mission_row_forecourt',x=440.5,y=-995.0,z=30.7,radius=6,count=4,category='police',coverage='curated'},
            {id='sandy_sheriff_parking',x=1851.0,y=3687.0,z=34.3,radius=6,count=3,category='police',coverage='curated'},
            {id='zancudo_approach',x=-2348.0,y=3266.0,z=32.8,radius=7,count=4,category='military',coverage='curated'},
            {id='sandy_residential',x=1968.0,y=3812.0,z=32.3,radius=35,count=8,category='home',coverage='expanded'},
            {id='grapeseed_storage',x=1704.0,y=4806.0,z=41.8,radius=25,count=6,category='warehouse',coverage='expanded'},
            {id='paleto_homes',x=-283.0,y=6231.0,z=31.5,radius=30,count=6,category='home',coverage='expanded'},
            {id='sandy_industrial',x=1730.0,y=3715.0,z=34.1,radius=25,count=6,category='industrial',coverage='expanded'},
            {id='davis_storage',x=111.0,y=-1940.0,z=20.8,radius=25,count=6,category='warehouse',coverage='expanded'},
        }},
    groundModels={
        ammo_pistol='prop_box_ammo03a',ammo_magnum='prop_box_ammo03a',ammo_rifle='prop_box_ammo07a',ammo_shotgun='prop_box_ammo04a',
        water_bottle='prop_ld_flow_bottle',canned_food='prop_cs_tinned_food_01',medkit='prop_ld_health_pack',bandage='prop_ld_health_pack',
        att_scope='w_at_scope_macro',att_suppressor='w_at_ar_supp_02',att_grip='w_at_ar_afgrip',att_flashlight='w_at_ar_flsh',
        toolbox='prop_tool_box_04',scrap_metal='prop_rub_scrap_03',wood_plank='prop_woodpile_01a',
    },
    fallbackGroundModel='prop_cs_heist_bag_02',
}
