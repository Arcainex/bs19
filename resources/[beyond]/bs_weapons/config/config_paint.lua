-- Experimental full-colour weapon paint.
-- GTA weapon finishes are a fixed tint palette, so real RGB paint swaps the weapon's diffuse texture on each client
-- with a generated one (AddReplaceTexture). That swap is per client and per texture, so it changes EVERY copy of
-- that weapon model the client can see. The client therefore paints a model only when one paint owns it nearby
-- (see applyDistance); with two differently painted copies of the same model in view, both show the factory look.
Weapons.Paint = {
    enabled = true,
    textureSize = 512,
    -- Generated textures alive at once (one per painted texture part).
    maxSlots = 6,
    -- Other holders of the same model inside this radius decide whether a paint can be shown.
    applyDistance = 30.0,
    maxParts = 4,
    maxStrokes = 40,
    maxPoints = 2400,
    -- Weapon id -> model name. Checked against the game at runtime; a wrong line just disables paint for it.
    models = {
        WEAPON_PISTOL='w_pi_pistol', WEAPON_COMBATPISTOL='w_pi_combatpistol', WEAPON_APPISTOL='w_pi_appistol',
        WEAPON_HEAVYPISTOL='w_pi_heavypistol', WEAPON_PISTOL50='w_pi_pistol50', WEAPON_SNSPISTOL='w_pi_sns_pistol',
        WEAPON_MICROSMG='w_sb_microsmg', WEAPON_SMG='w_sb_smg', WEAPON_ASSAULTSMG='w_sb_assaultsmg', WEAPON_COMBATPDW='w_sb_pdw',
        WEAPON_ASSAULTRIFLE='w_ar_assaultrifle', WEAPON_CARBINERIFLE='w_ar_carbinerifle', WEAPON_ADVANCEDRIFLE='w_ar_advancedrifle',
        WEAPON_SPECIALCARBINE='w_ar_specialcarbine', WEAPON_BULLPUPRIFLE='w_ar_bullpuprifle', WEAPON_COMPACTRIFLE='w_ar_assaultrifle_smg',
        WEAPON_PUMPSHOTGUN='w_sg_pumpshotgun', WEAPON_SAWNOFFSHOTGUN='w_sg_sawnoff', WEAPON_ASSAULTSHOTGUN='w_sg_assaultshotgun',
        WEAPON_BULLPUPSHOTGUN='w_sg_bullpupshotgun', WEAPON_HEAVYSHOTGUN='w_sg_heavyshotgun',
        WEAPON_SNIPERRIFLE='w_sr_sniperrifle', WEAPON_HEAVYSNIPER='w_sr_heavysniper', WEAPON_MARKSMANRIFLE='w_sr_marksmanrifle',
        WEAPON_MG='w_mg_mg', WEAPON_COMBATMG='w_mg_combatmg',
    },
    -- Known texture parts per model: { {txn='texture_name', label='Body'}, ... }. When a model is not listed the
    -- client probes common names; /weaponpaintprobe prints what it finds so the list can be filled in here.
    textures = {},
    -- Name patterns tried by the probe. %m = model name, %b = model name without the w_xx_ prefix.
    probe = { '%m', '%m_d', '%m_diff', '%b', '%b_d', '%m_body_d', '%m_mag_d', '%m_mag', '%m_a_d', '%m_b_d', '%m_c_d', '%b_mag_d' },
}

local function hex(v)return type(v)=='string'and v:match('^#%x%x%x%x%x%x$')~=nil end
local PATTERNS={solid=true,worn=true,stripes=true,camo=true,twotone=true}
-- Shared validator (client preview and server save). Returns a clean copy or nil.
function Weapons.ValidPaint(paint)
    if paint==nil then return nil end
    local P=Weapons.Paint
    if type(paint)~='table'or type(paint.parts)~='table'then return nil end
    local out,parts,points={v=1,parts={}},0,0
    for txn,part in pairs(paint.parts)do
        if type(txn)~='string'or #txn>48 or not txn:match('^[%w_]+$')or type(part)~='table'then return nil end
        parts=parts+1;if parts>(P.maxParts or 4)then return nil end
        local clean={base=part.base,pattern=part.pattern or 'solid',colour2=part.colour2 or '#1E1E1C',wear=tonumber(part.wear)or .35,strokes={}}
        if not hex(clean.base)or not PATTERNS[clean.pattern]or not hex(clean.colour2)or clean.wear~=clean.wear or clean.wear<0 or clean.wear>1 then return nil end
        clean.base,clean.colour2=clean.base:upper(),clean.colour2:upper()
        local strokes=part.strokes or {}
        if type(strokes)~='table'or #strokes>(P.maxStrokes or 40)then return nil end
        for _,s in ipairs(strokes)do
            if type(s)~='table'or not hex(s.c)or type(s.s)~='number'or s.s<1 or s.s>80 or type(s.p)~='table'or #s.p<2 or #s.p%2~=0 or #s.p>240 then return nil end
            local pts={}
            for i,n in ipairs(s.p)do
                if type(n)~='number'or n%1~=0 or n<0 or n>1000 then return nil end
                pts[i]=n
            end
            points=points+#pts/2;if points>(P.maxPoints or 2400)then return nil end
            clean.strokes[#clean.strokes+1]={c=s.c:upper(),s=s.s,p=pts,e=s.e==true or nil}
        end
        out.parts[txn]=clean
    end
    if parts==0 then return nil end
    return out
end
