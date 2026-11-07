-- Zombie difficulty scaling: F1 multipliers per stat plus an optional progression factor

ZDiff = ZDiff or {}

local function C() return (Zombies and Zombies.Difficulty) or {} end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

-- Flat multiplier from F1.
function ZDiff.Mult(stat)
    return math.max(0.0, tonumber(C()[stat .. 'Mult']) or 1.0)
end

-- Progression part for t in 0..1 (nil t = nobody near, no change).
function ZDiff.Prog(stat, t)
    local P = C().Progression or {}
    if P.enabled ~= true or t == nil then return 1.0 end
    local s = P[stat]
    if type(s) ~= 'table' or s.enabled == false then return 1.0 end
    local lo, hi = tonumber(s.min) or 1.0, tonumber(s.max) or 1.0
    return lo + (hi - lo) * clamp(t, 0.0, 1.0)
end

function ZDiff.Scale(stat, t)
    return ZDiff.Mult(stat) * ZDiff.Prog(stat, t)
end

-- Move rate after scaling, kept under the absolute ceiling.
function ZDiff.Rate(rate, f)
    if not rate then return rate end
    return math.min(rate * (f or 1.0), tonumber(C().speedCeiling) or 1.35)
end

function ZDiff.SpeedOnDrunk() return C().speedOnDrunkGait == true end

if not IsDuplicityVersion() then
    -- Factor the server worked out for this player (own level and players nearby)
    function ZDiff.Local(stat)
        local st = LocalPlayer and LocalPlayer.state and LocalPlayer.state.bsZDiff
        local k = stat == 'damage' and 'd' or 's'
        local v = type(st) == 'table' and tonumber(st[k]) or nil
        return v or ZDiff.Mult(stat)
    end
end
