-- bs_economy - blowing up a cash machine.
-- The server cannot see ATMs (they are map props, not spawned entities), but it does hear explosions with a position and a causer. So: the server hears the bang and asks the causing client whether a machine was there; the client checks with the game's object lookup; the server pays out after confirming the bang, position, distance and cooldown.
-- A client can only lie about a machine standing where its own explosion went off.

local A = Economy.ATM or { enabled = false }

-- [key] = { x, y, z, ready } - ready is os.time() when the machine can be blown again. Coords kept so a claim can be range-checked.
local cracked = {}

-- Radius inside which a recent crack counts as the same machine.
local CRACK_RADIUS = 5.0

-- [src] = { x, y, z, at } - last explosion this player caused, so a claim is matched against a bang the server heard.
local blasts = {}

local function keyFor(x, y, z)
    return ('%.1f:%.1f:%.1f'):format(x, y, z)
end

-- Hearing it

AddEventHandler('explosionEvent', function(sender, ev)
    if not A.enabled then return end

    local src = tonumber(sender)
    if not src or src <= 0 then return end
    if type(ev) ~= 'table' or not ev.posX then return end

    blasts[src] = { x = ev.posX, y = ev.posY, z = ev.posZ, at = GetGameTimer() }

    -- Ask the causing client only: it has the machine streamed in, and its claim can be checked.
    TriggerClientEvent('bs:atm:blast', src, ev.posX, ev.posY, ev.posZ)
end)

AddEventHandler('playerDropped', function() blasts[source] = nil end)

-- Paying for it

local function roll(range, fallbackLo, fallbackHi)
    local lo = math.floor((range and range[1]) or fallbackLo)
    local hi = math.floor((range and range[2]) or fallbackHi)
    if hi <= lo then return lo end
    return math.random(lo, hi)
end

BSB.RegisterCallback('atm:crack', function(src, x, y, z)
    if not A.enabled then return { ok = false } end

    local player = exports.bs_core:GetPlayer(src)
    if not player then return { ok = false } end

    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then
        return { ok = false }
    end

    -- The claim must match a bang we heard, within ten seconds. Otherwise the callback would be "give me money at these coordinates".
    local blast = blasts[src]
    if not blast or (GetGameTimer() - blast.at) > 10000 then
        return { ok = false, error = 'nothing went off here' }
    end

    local bdx, bdy, bdz = blast.x - x, blast.y - y, blast.z - z
    if math.sqrt(bdx * bdx + bdy * bdy + bdz * bdz) > (A.blastRadius or 4.0) then
        return { ok = false, error = 'the blast was not on the machine' }
    end

    -- The player must also be near their own explosion.
    local ped = GetPlayerPed(src)
    local at = ped and ped ~= 0 and GetEntityCoords(ped)
    if not at then return { ok = false } end

    local pdx, pdy, pdz = at.x - x, at.y - y, at.z - z
    if math.sqrt(pdx * pdx + pdy * pdy + pdz * pdz) > (A.claimRadius or 30.0) then
        return { ok = false, error = 'too far from it' }
    end

    -- Matched by distance, not key: the key is coords rounded to 0.1, so small nudges made new machines. Any live crack within CRACK_RADIUS is the same machine.
    local now = os.time()
    for _, c in pairs(cracked) do
        if now < c.ready then
            local cdx, cdy, cdz = c.x - x, c.y - y, c.z - z
            if math.sqrt(cdx * cdx + cdy * cdy + cdz * cdz) <= CRACK_RADIUS then
                return { ok = false,
                         error = ('Already emptied. %d min.'):format(math.ceil((c.ready - now) / 60)) }
            end
        end
    end

    local key = keyFor(x, y, z)
    cracked[key] = { x = x, y = y, z = z, ready = now + (A.cooldown or 2700) }
    blasts[src] = nil        -- one machine per bang

    local cash = roll(A.cash, 600, 3200)
    local scrap = roll(A.scrap, 2, 6)

    exports.bs_core:AddMoney(src, 'cash', cash, 'atm cracked')

    local gaveScrap = 0
    if scrap > 0 and GetResourceState('bs_inventory') == 'started' then
        local ok = exports.bs_inventory:GiveItem(src, 'scrap_metal', scrap)
        gaveScrap = ok and scrap or 0
    end

    print(('^3[BeyondSurvival]^7 (atm) %s cracked a machine at %s for $%d')
        :format(GetPlayerName(src) or src, key, cash))

    return { ok = true, cash = cash, scrap = gaveScrap }
end)

-- Forget expired entries: a machine whose cooldown ran out is the same as an untouched one.
CreateThread(function()
    while true do
        Wait(600000)
        local now = os.time()
        for key, c in pairs(cracked) do
            if now > c.ready + 600 then cracked[key] = nil end
        end
    end
end)
