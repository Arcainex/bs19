-- bs_weapons - /giveammo: gives the ammo box matching the weapon in hand (staff debug command)

local ACE = 'bs.admin'

local function isStaff(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, ACE) then return true end
    if GetResourceState('bs_admin') == 'started' then
        local ok, admin = pcall(function() return exports.bs_admin:IsAdmin(src) end)
        if ok and admin == true then return true end
    end
    return false
end

local function tell(src, message)
    if src == 0 then
        print('^5[BeyondSurvival]^7 (ammo) ' .. message)
    else
        TriggerClientEvent('chat:addMessage', src, {
            args = { '[AMMO]', message }, color = { 200, 118, 58 },
        })
    end
end

-- The ammo item is asked from bs_inventory, which owns the item definitions
local function ammoItemFor(weaponName)
    if GetResourceState('bs_inventory') ~= 'started' then return nil end
    local ok, item = pcall(function()
        return exports.bs_inventory:AmmoItemFor(weaponName)
    end)
    return ok and item or nil
end

-- Label and rounds-per-box from the same owner, for the confirmation line.
local function blurbFor(itemName)
    if GetResourceState('bs_inventory') ~= 'started' then return nil end
    local ok, blurb = pcall(function()
        return exports.bs_inventory:ItemBlurb(itemName)
    end)
    return ok and blurb or nil
end


-- [src] = true while a request is in flight, so holding the key does not queue many grants.
local pending = {}

RegisterCommand('giveammo', function(src, args)
    if not isStaff(src) then
        tell(src, 'refused - needs the bs.admin ace or staff in bs_admin.')
        return
    end

    if src == 0 then
        tell(src, 'run this in game - it reads the weapon in YOUR hands.')
        return
    end

    if pending[src] then return end
    pending[src] = true

    -- Number of boxes, default 3.
    local boxes = math.max(1, math.min(20, math.floor(tonumber(args and args[1]) or 3)))

    TriggerClientEvent('bs:weapons:whatAmIHolding', src, boxes)

    -- Released on a timer, not on the reply, so a lost reply cannot lock the player out of the command
    CreateThread(function()
        Wait(2000)
        pending[src] = nil
    end)
end, false)

RegisterNetEvent('bs:weapons:holdingIs', function(weaponName, boxes)
    local src = source
    if not isStaff(src) then return end

    boxes = math.max(1, math.min(20, math.floor(tonumber(boxes) or 3)))

    if type(weaponName) ~= 'string' or weaponName == ''
       or string.upper(weaponName) == 'WEAPON_UNARMED' then
        tell(src, 'you are not holding a firearm.')
        return
    end

    local item = ammoItemFor(weaponName)
    if not item then
        -- Say which case it is: bs_inventory being down and a genuinely unlisted weapon both give nil here
        if GetResourceState('bs_inventory') ~= 'started' then
            tell(src, 'bs_inventory is not running, so nothing can be added to your bag.')
        else
            tell(src, ('no ammunition item lists %s in its `ammoFor` - check config_items.lua.')
                :format(weaponName))
        end
        return
    end

    local ok = false
    if GetResourceState('bs_inventory') == 'started' then
        local success, result = pcall(function()
            return exports.bs_inventory:GiveItem(src, item, boxes)
        end)
        ok = success and result and true or false
    end

    if ok then
        local blurb = blurbFor(item)
        tell(src, ('%d x %s%s - press R to load.'):format(
            boxes, (blurb and blurb.label) or item,
            (blurb and blurb.rounds) and (' (%d rounds each)'):format(blurb.rounds) or ''))
    else
        tell(src, ('could not add %s - the bag is probably full.'):format(item))
    end
end)
