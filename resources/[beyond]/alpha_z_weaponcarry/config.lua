Carry = {}
Carry.Range = 90.0
Carry.RefreshMs = 1000
-- Adminrechte: exakt die ACE-Stufen aus bs_core/config/config.lua.
-- Damit dürfen bestehende BeyondSurvival-Admins den Editor verwenden,
-- auch ohne eine separate alpha_z.weaponcarry.edit-Berechtigung.
-- Es wird NICHT für normale Spieler freigeschaltet.
-- These permissions are intentionally separate. The general tester editor ACE
-- MUST NEVER grant global writes to positions.json.
Carry.GlobalEditorAces = {'bs.admin','bs.superadmin','command.zombiemenu'}
Carry.PersonalEditorAces = {'alpha_z.weaponcarry.edit','alpha_z.tester'}
Carry.EditorAces = {
 'alpha_z.weaponcarry.edit', -- gezielte Freigabe für den Waffen-Editor
 'bs.admin',                 -- BeyondSurvival Admin
 'bs.superadmin',            -- BeyondSurvival Superadmin
 'command.zombiemenu',      -- von bs_core als Admin-ACE anerkannt
}
-- Only real GTA V ped bones may be selected. The client additionally checks
-- GetPedBoneIndex on the current character before showing the option.
-- IDs based on CitizenFX's Ped Bone enum. UI names can be changed freely.
Carry.Bones = {
 {id=11816, label='Becken / Hüfte (SKEL_Pelvis)'},
 {id=57597, label='Wirbelsäulenwurzel (SKEL_Spine_Root)'},
 {id=23553, label='Wirbelsäule unten (SKEL_Spine0)'},
 {id=24816, label='Wirbelsäule Mitte (SKEL_Spine1)'},
 {id=24817, label='Wirbelsäule oben (SKEL_Spine2)'},
 {id=24818, label='Brust / Rücken (SKEL_Spine3)'},
 {id=64729, label='Schlüsselbein links (SKEL_L_Clavicle)'},
 {id=10706, label='Schlüsselbein rechts (SKEL_R_Clavicle)'},
 {id=45509, label='Oberarm links (SKEL_L_UpperArm)'},
 {id=40269, label='Oberarm rechts (SKEL_R_UpperArm)'},
 {id=61163, label='Unterarm links (SKEL_L_Forearm)'},
 {id=28252, label='Unterarm rechts (SKEL_R_Forearm)'},
 {id=18905, label='Hand links (SKEL_L_Hand)'},
 {id=57005, label='Hand rechts (SKEL_R_Hand)'},
 {id=58271, label='Oberschenkel links (SKEL_L_Thigh)'},
 {id=51826, label='Oberschenkel rechts (SKEL_R_Thigh)'},
 {id=39317, label='Hals (SKEL_Neck_1)'},
 {id=31086, label='Kopf (SKEL_Head)'},
}

Carry.Slots = {
 rifle = { bone=24818, pos={0.16,-0.18,0.06}, rot={0.0,165.0,0.0} },
 melee = { bone=24818, pos={-0.19,-0.20,-0.07}, rot={0.0,170.0,15.0} },
 left = { bone=11816, pos={-0.18,-0.08,0.01}, rot={0.0,90.0,10.0} },
 right = { bone=11816, pos={0.18,-0.08,0.01}, rot={0.0,-90.0,-10.0} },
}
-- Classification is per inventory item, not per weapon hash (crossbow uses sniper hash).
-- Second value indicates the default position when editing an ITEM.
-- The actual prop position is always taken from the equipped hotbar slot.
Carry.Items = {
 hunting_knife={'WEAPON_KNIFE','left'},
 reinforced_bat={'WEAPON_BAT','melee','Einhornkuss'},
 pistol={'WEAPON_PISTOL','right'}, revolver={'WEAPON_REVOLVER','right'},
 combat_pistol={'WEAPON_COMBATPISTOL','right'},
 smg={'WEAPON_SMG','rifle'}, pump_shotgun={'WEAPON_PUMPSHOTGUN','rifle'},
 sawn_off={'WEAPON_SAWNOFFSHOTGUN','rifle'}, assault_rifle={'WEAPON_ASSAULTRIFLE','rifle'},
 marksman={'WEAPON_MARKSMANRIFLE','rifle'}, carbine={'WEAPON_CARBINERIFLE','rifle'},
 hunting_rifle={'WEAPON_HEAVYSNIPER','rifle'}, crossbow={'WEAPON_SNIPERRIFLE','rifle'},
 hammer={'WEAPON_HAMMER','left','Fleischklopfer'},
 weapon_bottle={'WEAPON_BOTTLE','left'},
 weapon_poolcue={'WEAPON_BARBEDBAT','melee','Barbed Wire Bat'},
 weapon_golfclub={'WEAPON_GOLFCLUB','melee','Golfschläger'},
 weapon_stone_hatchet={'WEAPON_STONE_HATCHET','left'},
 machete={'WEAPON_MACHETE','left'},
 crowbar={'WEAPON_CROWBAR','melee','Schädelbrecher'},
 zombie_arm={'WEAPON_ZOMBIEARM','melee'},
 flashlight={'WEAPON_FLASHLIGHT','left'},
 hatchet={'WEAPON_HATCHET','left'},
 axe={'WEAPON_BATTLEAXE','left'}, wrench={'WEAPON_WRENCH','left'},
 spiked_bat={'WEAPON_BAT','left'},
 pipe_pistol={'WEAPON_SNSPISTOL','right'},
 pipe_shotgun={'WEAPON_DBSHOTGUN','rifle'},
 molotov={'WEAPON_MOLOTOV','left'},
 starter_poolcue={'WEAPON_POOLCUE','left'}
}
-- Explicit model overrides for custom streamed weapons.
-- The inventory key 'weapon_poolcue' is retained for database/hotbar compatibility.
-- Its actual weapon is WEAPON_BARBEDBAT with the streamed model below.
Carry.Models = { weapon_poolcue = 'w_me_barbedbat' }

