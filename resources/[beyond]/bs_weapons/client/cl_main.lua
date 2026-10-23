-- bs_weapons - attachment wheel (O)

-- Only one wheel at a time: it loops and holds a scripted camera
local wheelOpen = false
local wheelOpenedAt = 0

local Fitted = {}      -- [weaponName] = { [slot] = attachmentId }
local SyncedAmmo = {}  -- [weaponName] = rounds, as of the last server sync
local busy = false
local lastWeapon = nil
local lastWeaponHash = nil
local lastReportedAmmo = nil
local lastAmmoReportAt = 0

-- Helpers

local function notify(kind, message, duration)
    TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration })
end

--- The weapon in hand, as the NAME the config is keyed by.
local WEAPON_NAMES = {}

CreateThread(function()
    -- Build hash to name once, from the config, so we never have to guess
    for _, att in pairs(Weapons.Attachments) do
        for name in pairs(att.components or {}) do
            WEAPON_NAMES[GetHashKey(name)] = name
        end
    end

    -- Also map every other known weapon name, so a bat or crowbar says it takes no attachments instead of the key seeming dead
    for _, name in ipairs(Weapons.Known or {}) do
        WEAPON_NAMES[GetHashKey(name)] = name
    end
end)

local function currentWeapon()
    local ped = PlayerPedId()
    local _, hash = GetCurrentPedWeapon(ped, true)
    if not hash or hash == GetHashKey('WEAPON_UNARMED') then return nil end
    return WEAPON_NAMES[hash], hash
end

local function componentFor(attachmentId, weaponName)
    local att = Weapons.Attachments[attachmentId]
    if not att then return nil end
    return att.components and att.components[weaponName]
end

-- Config wins over the engine
local engineDisagreed = {}

local function engineAccepts(weaponHash, componentName)
    if not componentName then return false end

    local component = GetHashKey(componentName)
    local ok, takes = pcall(DoesWeaponTakeWeaponComponent, weaponHash, component)

    if ok and takes == true then return true end

    local key = tostring(weaponHash) .. ':' .. componentName
    if not engineDisagreed[key] then
        engineDisagreed[key] = true
        print(('^3[BS WEAPONS]^7 engine says %s does not take %s - offering it anyway (config is the authority). If it visibly does not fit, that config line is wrong.')
            :format(tostring(weaponHash), componentName))
    end

    -- Config wins. See the note above.
    return true
end

-- Applying

-- Puts everything the server says is fitted back on the weapon in hand
local function reapply(weaponName, weaponHash)
    local set = Fitted[weaponName] or {}

    -- Request the weapon asset so the engine can answer component questions
    local ours = false
    if not HasWeaponAssetLoaded(weaponHash) then
        ours = true
        pcall(RequestWeaponAsset, weaponHash, 31, 0)

        local waited = 0
        while not HasWeaponAssetLoaded(weaponHash) and waited < 1500 do
            Wait(10); waited = waited + 10
        end
    end

    local verified = HasWeaponAssetLoaded(weaponHash)

    local ped = PlayerPedId()

    -- Take off parts this gun does not have
    local keep = {}
    for _, attachmentId in pairs(set) do
        local c = componentFor(attachmentId, weaponName)
        if c then keep[c] = true end
    end
    for _, att in pairs(Weapons.Attachments) do
        local c = att.components and att.components[weaponName]
        if c and not keep[c] and HasPedGotWeaponComponent(ped, weaponHash, GetHashKey(c)) then
            RemoveWeaponComponentFromPed(ped, weaponHash, GetHashKey(c))
        end
    end

    for _, attachmentId in pairs(set) do
        local component = componentFor(attachmentId, weaponName)
        -- not verified = we could not ask, so we trust the server record rather than throwing the attachment away
        if component and (not verified or engineAccepts(weaponHash, component)) then
            GiveWeaponComponentToPed(ped, weaponHash, GetHashKey(component))
        end
    end

    -- Only release what this call requested; something else may hold the same asset.
    if ours then pcall(RemoveWeaponAsset, weaponHash) end
end

-- Asks the server what is on the gun item in hand, then fits exactly that.
local function refit(weaponName, weaponHash)
    local st = BSB.Await('weapons:fitted', 4000, weaponName)
    if st and st.ok then Fitted[weaponName] = st.fitted or {} end
    reapply(weaponName, weaponHash)
end

-- Keep the ammo argument the server sends with set, so the spawn-restore path can look up the saved round count
RegisterNetEvent('bs:weapons:sync', function(set, ammo)
    Fitted = set or {}
    SyncedAmmo = ammo or {}

    -- reapply now waits for the weapon asset to stream (see its note), so it yields
    local name, hash = currentWeapon()
    if name then CreateThread(function() refit(name, hash) end) end
end)

-- What the server last told us was left in this weapon. nil means it has never told us
exports('SyncedAmmo', function(weapon) return SyncedAmmo[weapon] end)

-- SyncedAmmo is keyed by weapon name, but the spawn-restore path stores a numeric hash, so the lookup could never match
exports('SyncedAmmoByHash', function(hash)
    local name = WEAPON_NAMES[tonumber(hash)]
    return name and SyncedAmmo[name] or nil
end)

-- Hash to weapon name, from the same table
exports('NameOfHash', function(hash)
    hash = tonumber(hash)
    return hash and WEAPON_NAMES[hash] or nil
end)

-- Ammo, remembered
-- The engine forgets ammo when a weapon is taken away and given back (GetAmmoInPedWeapon returns 0), so the server remembers it

local function reportAmmo(hash, weaponName)
    if not weaponName or not hash then return end
    local ammo = GetAmmoInPedWeapon(PlayerPedId(), hash)
    if ammo == lastReportedAmmo then return end
    lastReportedAmmo = ammo
    TriggerServerEvent('bs:weapons:reportAmmo', weaponName, ammo)
end

-- Weapon changed in your hands: re-fit whatever belongs on this one, and write down what was left in whatever you just put away
CreateThread(function()
    while true do
        Wait(400)

        if exports.bs_core:IsLoaded() then
            local name, hash = currentWeapon()

            if name and name ~= lastWeapon then
                if lastWeapon and lastWeaponHash then reportAmmo(lastWeaponHash, lastWeapon) end
                lastWeapon, lastWeaponHash, lastReportedAmmo = name, hash, nil
                lastAmmoReportAt = GetGameTimer()
                refit(name, hash)

            elseif name and name == lastWeapon then
                local now = GetGameTimer()
                if now - lastAmmoReportAt > 4000 then
                    lastAmmoReportAt = now
                    reportAmmo(hash, name)
                end

            elseif not name then
                if lastWeapon and lastWeaponHash then reportAmmo(lastWeaponHash, lastWeapon) end
                lastWeapon, lastWeaponHash, lastReportedAmmo = nil, nil, nil
            end
        end
    end
end)

-- A real ammo decrease is the authoritative shot signal
CreateThread(function()
    local watchedHash, watchedAmmo = nil, nil
    while true do
        Wait(watchedHash and 15 or 80)
        if exports.bs_core:IsLoaded() then
            local name, hash = currentWeapon()
            if name and hash then
                local ammo = GetAmmoInPedWeapon(PlayerPedId(), hash)
                if watchedHash == hash and watchedAmmo ~= nil and ammo < watchedAmmo then
                    local hit, impact = GetPedLastWeaponImpactCoord(PlayerPedId())
                    TriggerEvent('bs:weapons:shot', hit and {
                        x = impact.x,
                        y = impact.y,
                        z = impact.z,
                    } or nil)
                end
                watchedHash, watchedAmmo = hash, ammo
            else
                watchedHash, watchedAmmo = nil, nil
            end
        end
    end
end)

-- Magazine size (config first, engine as fallback)

-- Mag size for the weapon in hand, taking the fitted mag into account
function Weapons.ClientMagSize(ped, hash)
    local name = WEAPON_NAMES[hash]
    local size = name and Weapons.MagSizeFor(name, Fitted[name])
    if size then return size end
    return GetMaxAmmoInClip(ped, hash, true) or 0
end

-- GTA's own clip can be bigger than ours (AK extended is 60 in GTA, 45 here)
local function trimClip(ped, hash)
    local mag = Weapons.ClientMagSize(ped, hash)
    if mag <= 0 then return end
    local _, clip = GetAmmoInClip(ped, hash)
    if (clip or 0) <= mag then return end

    local total = GetAmmoInPedWeapon(ped, hash) or 0
    SetAmmoInClip(ped, hash, mag)
    if (GetAmmoInPedWeapon(ped, hash) or 0) ~= total then
        SetPedAmmo(ped, hash, total)
        local _, again = GetAmmoInClip(ped, hash)
        if (again or 0) > mag then SetAmmoInClip(ped, hash, mag) end
    end
end

CreateThread(function()
    while true do
        local name, hash = currentWeapon()
        if name and hash then
            trimClip(PlayerPedId(), hash)
            Wait(50)
        else
            Wait(400)
        end
    end
end)

AddEventHandler('bs:hook:player:unloaded', function()
    if lastWeapon and lastWeaponHash then reportAmmo(lastWeaponHash, lastWeapon) end
end)

-- Working on it

-- Working animation: the first candidate that really exists
local workAnim, workAnimChecked = nil, false

local function resolveWorkAnim()
    if workAnimChecked then return workAnim end
    workAnimChecked = true

    local candidates = Weapons.Anims or { Weapons.Anim }

    for _, c in ipairs(candidates) do
        if c and c.dict and DoesAnimDictExist(c.dict) then
            if not HasAnimDictLoaded(c.dict) then RequestAnimDict(c.dict) end
            local waited = 0
            while not HasAnimDictLoaded(c.dict) and waited < 1200 do
                Wait(10); waited = waited + 10
            end

            if HasAnimDictLoaded(c.dict) then
                local ok, duration = pcall(GetAnimDuration, c.dict, c.clip)
                if ok and type(duration) == 'number' and duration > 0.0 then
                    workAnim = c
                    print(('^2[BeyondSurvival]^7 (weapons) working animation: %s / %s')
                        :format(c.dict, c.clip))
                    return workAnim
                end
            end
        end
    end

    print('^3[BeyondSurvival]^7 (weapons) no working animation resolved - fitting will be silent')
    return nil
end

local function playWork(time)
    local ped = PlayerPedId()
    local a = resolveWorkAnim()

    if a then
        TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, time, a.flag or 49,
            0.0, false, false, false)
    end

    Wait(time)
    ClearPedTasks(ped)
end

local function fit(weaponName, weaponHash, attachmentId)
    if busy then return end
    busy = true

    local result = BSB.Await('weapons:fit', 8000, weaponName, attachmentId)

    if not result or not result.ok then
        busy = false
        return notify('warn', (result and result.error) or L('wp.wont_on'))
    end

    playWork(Weapons.Settings.workTime or 1800)

    GiveWeaponComponentToPed(PlayerPedId(), weaponHash, GetHashKey(result.component))

    Fitted[weaponName] = Fitted[weaponName] or {}
    Fitted[weaponName][result.slot] = attachmentId

    notify('success', L('wpn.fitted', { name = result.label }), 2400)
    busy = false
end

local function remove(weaponName, weaponHash, slot)
    if busy then return end
    busy = true

    local result = BSB.Await('weapons:remove', 8000, weaponName, slot)

    if not result or not result.ok then
        busy = false
        return notify('warn', (result and result.error) or L('wp.wont_off'))
    end

    playWork(Weapons.Settings.workTime or 1800)

    local ped = PlayerPedId()
    local totalBefore = GetAmmoInPedWeapon(ped, weaponHash) or 0

    if result.component then
        RemoveWeaponComponentFromPed(ped, weaponHash, GetHashKey(result.component))
    end

    if Fitted[weaponName] then Fitted[weaponName][slot] = nil end

    -- Mag came off: what no longer fits in the standard mag goes back to the bag as ammo boxes
    if slot == 'mag' then
        local newMag = Weapons.ClientMagSize(ped, weaponHash)
        local excess = totalBefore - newMag
        if excess > 0 then
            local back = BSB.Await('weapons:returnAmmo', 8000, weaponName, excess)
            if back and back.ok and (back.rounds or 0) > 0 then
                SetPedAmmo(ped, weaponHash, math.max(0, totalBefore - back.rounds))
                notify('info', L('wpn.rounds_back', { n = back.rounds }), 2400)
            else
                SetPedAmmo(ped, weaponHash, totalBefore)
            end
        end
        trimClip(ped, weaponHash)
        reportAmmo(weaponHash, weaponName)
    end

    notify('info', L('wp.removed', { name = result.label or L('wp.attachment') }), 2400)
    busy = false
end

local function inspect()
    local ped = PlayerPedId()
    local anim = Weapons.Inspect

    if not DoesAnimDictExist(anim.dict) then return end
    if not HasAnimDictLoaded(anim.dict) then RequestAnimDict(anim.dict) end
    local waited = 0
    while not HasAnimDictLoaded(anim.dict) and waited < 1200 do Wait(10); waited = waited + 10 end
    if not HasAnimDictLoaded(anim.dict) then return end

    TaskPlayAnim(ped, anim.dict, anim.clip, 4.0, -4.0, anim.time or 2200,
        anim.flag or 48, 0.0, false, false, false)
end

-- The wheel

-- Builds the slices
local function buildItems(weaponName, weaponHash, state)
    local ped = PlayerPedId()

    Fitted[weaponName] = (state and state.ok and state.fitted) or {}
    local fitted = Fitted[weaponName]
    local counts = (state and state.ok and state.counts) or {}

    local items = {}

    for _, slot in ipairs(Weapons.Slots) do
        local current = fitted[slot.id]

        -- What could go in this slot that this weapon takes and we have.
        local options = {}
        for attachmentId, att in pairs(Weapons.Attachments) do
            if att.slot == slot.id then
                local component = att.components and att.components[weaponName]
                if engineAccepts(weaponHash, component) then
                    local have = tonumber(counts[att.item]) or 0

                    options[#options + 1] = {
                        id = 'fit:' .. slot.id .. ':' .. attachmentId,
                        label = att.label,
                        icon = att.icon or 'dot',
                        note = have > 0 and L('wp.have_n', { n = have }) or L('wp.none_bag'),
                        disabled = have <= 0,
                    }
                end
            end
        end

        if current then
            local att = Weapons.Attachments[current]
            items[#items + 1] = {
                id     = 'off:' .. slot.id,
                label  = slot.label,
                icon   = att and att.icon or slot.icon,
                active = true,
                note   = L('wp.take_off', { name = att and att.label or current }),
            }
        elseif #options > 0 then
            items[#items + 1] = {
                id      = 'slot:' .. slot.id,
                label   = slot.label,
                icon    = slot.icon,
                note    = ('%d option%s'):format(#options, #options == 1 and '' or 's'),
                title   = slot.label:upper(),
                submenu = options,
            }
        else
            items[#items + 1] = {
                id       = 'none:' .. slot.id,
                label    = slot.label,
                icon     = slot.icon,
                disabled = true,
                note     = L('wp.nothing_fits'),
            }
        end
    end

    items[#items + 1] = { id = 'inspect', label = L('wp.inspect'), icon = 'inspect',
                          note = L('wp.look_at_it') }
    items[#items + 1] = { id = 'ammo', label = L('wp.ammo'), icon = 'ammo',
                          note = L('wp.rounds_n', { n = GetAmmoInPedWeapon(ped, weaponHash) }) }

    return items
end

-- The wheel loops: picking applies the change and the wheel returns with the gun's new state
local function openWheel()
    if busy then return end

    -- Stale-flag guard: if the loop throws
    if wheelOpen then
        if GetGameTimer() - wheelOpenedAt < 120000 then return end
        wheelOpen = false
        if Weapons.StopPreview then Weapons.StopPreview() end
    end

    -- Claim wheelOpen on the same tick as the check, not after the asset wait
    wheelOpen = true
    wheelOpenedAt = GetGameTimer()

    -- Every early return from here must hand the flag back.
    local function bail(kind, message, ms)
        wheelOpen = false
        if message then notify(kind, message, ms) end
    end

    if GetResourceState('bs_radial') ~= 'started' then
        return bail('warn', 'bs_radial is not running')
    end

    local ped = PlayerPedId()
    local weaponName, weaponHash = currentWeapon()

    if not weaponName then
        return bail('info', L('wp.no_attach_hands'), 2600)
    end

    if Weapons.Settings.requireStill and IsPedRunning(ped) then
        return bail('warn', L('wp.not_running'), 2000)
    end

    -- DoesWeaponTakeWeaponComponent reads the weapon asset
    local wheelAsset = false
    if not HasWeaponAssetLoaded(weaponHash) then
        wheelAsset = weaponHash
        pcall(RequestWeaponAsset, weaponHash, 31, 0)

        local assetWaited = 0
        while not HasWeaponAssetLoaded(weaponHash) and assetWaited < 1500 do
            Wait(10); assetWaited = assetWaited + 10
        end
    end

    local title = (weaponName:gsub('^WEAPON_', ''):gsub('_', ' '))

    -- Camera goes up before the first wheel so the gun is already framed when the slices fade in.
    local previewing = false
    if Weapons.StartPreview then
        previewing = Weapons.StartPreview() and true or false
    end

    -- nil anchor = the bs_radial default (centre), right when there is no preview.
    local side = nil
    if previewing then side = Weapons.PreviewWheelSide() end

    -- Hard ceiling on the loop
    local rounds = 0
    -- wheelOpen was claimed at the guard above.

    while rounds < 24 do
        rounds = rounds + 1

        -- The weapon can change under us: holstered, swapped, taken on death
        local nowName, nowHash = currentWeapon()
        if nowName ~= weaponName then break end
        weaponHash = nowHash

        -- Ask the server for what is fitted and what is in the bag
        local state = BSB.Await('weapons:state', 6000, weaponName)

        -- nil means "whatever bs_radial is configured to do"; false means "definitely not"
        local blurSetting = nil
        if previewing then blurSetting = false end

        local picked = BSB.Radial({
            title  = title,
            items  = buildItems(weaponName, weaponHash, state),
            anchor = side,
            -- The world must not blur while the preview is up
            blur   = blurSetting,
            -- Click to pick, not hold: fitting a scope is fiddly work you do standing still, not something you flick through mid-fight
        })

        if not picked then break end

        if picked == 'inspect' then
            inspect()
            Wait((Weapons.Inspect and Weapons.Inspect.time or 2600) + 200)
        elseif picked == 'ammo' then
            notify('info', L('wpn.rounds_in', { n = GetAmmoInPedWeapon(PlayerPedId(), weaponHash) }), 2600)
        else
            -- Split on the separator instead of matching %a: slot and attachment ids can contain digits or underscores
            local action, slot, attachmentId = picked:match('^([^:]+):([^:]+):?(.*)$')

            if action == 'off' then
                remove(weaponName, weaponHash, slot)
            elseif action == 'fit' and attachmentId ~= '' then
                fit(weaponName, weaponHash, attachmentId)
            end

            -- Short pause on the finished weapon before the wheel covers it again, so the change is actually seen
            Wait(previewing and 600 or 120)
        end
    end

    wheelOpen = false
    Weapons.StopPreview()

    -- Give the script-resource slot back (see where it was requested).
    if wheelAsset then pcall(RemoveWeaponAsset, wheelAsset) end
end

RegisterCommand(Weapons.Settings.openCommand, function()
    CreateThread(openWheel)
end, false)
RegisterKeyMapping(Weapons.Settings.openCommand, L('wpn.key_attach'),
    'keyboard', Weapons.Settings.openKey)

-- Debug command
-- Prints the whole decision chain

RegisterCommand('attachdebug', function()
    CreateThread(function()
        local ped = PlayerPedId()
        local _, hash = GetCurrentPedWeapon(ped, true)
        local name = WEAPON_NAMES[hash]

        print('^5[BS WEAPONS]^7 --- attachment diagnosis ---')
        print(('  weapon hash in hand : %s'):format(tostring(hash)))
        print(('  recognised as       : %s'):format(tostring(name)))

        if not name then
            print('^3  This weapon is not in Weapons.Known or any attachment table,')
            print('^3  so the wheel cannot name it. Add it to Weapons.Known.^7')
            return
        end

        local state = BSB.Await('weapons:state', 6000, name)
        if not state or not state.ok then
            print('^1  The server did not answer weapons:state. bs_weapons server side is down.^7')
            return
        end

        print('  fitted now          : ' .. json.encode(state.fitted or {}))
        print('  counts from server  : ' .. json.encode(state.counts or {}))

        for id, att in pairs(Weapons.Attachments) do
            local component = att.components and att.components[name]
            local accepts = component and engineAccepts(hash, component) or false
            local have = tonumber((state.counts or {})[att.item]) or 0

            print(('  %-12s slot=%-7s component=%-32s engine=%-5s have=%d')
                :format(id, att.slot, tostring(component), tostring(accepts), have))
        end

        print('^5[BS WEAPONS]^7 --- end ---')
    end)
end, false)

-- Suppressors and noise

-- A suppressed weapon broadcasts a much smaller gunshot noise to bs_emotes
exports('NoiseScale', function()
    local weaponName = currentWeapon()
    if not weaponName then return 1.0 end

    local set = Fitted[weaponName]
    if not set then return 1.0 end

    local scale = 1.0
    for _, attachmentId in pairs(set) do
        local effect = Weapons.Effects[attachmentId]
        if effect and effect.noiseScale then scale = scale * effect.noiseScale end
    end
    return scale
end)

-- Is this shot silent?
exports('IsSuppressed', function()
    local cfg = Weapons.Noise
    if not cfg or not cfg.suppressorIsSilent then return false end

    local threshold = cfg.silentAtOrBelow or 0.30

    local weaponName = currentWeapon()
    local set = weaponName and Fitted[weaponName]
    if set then
        for _, attachmentId in pairs(set) do
            local effect = Weapons.Effects[attachmentId]
            if effect and effect.noiseScale and effect.noiseScale <= threshold then
                return true
            end
        end
    end

    if cfg.engineSilencerCounts then
        local ped = PlayerPedId()
        local has, weapon = GetCurrentPedWeapon(ped, true)
        if has and weapon and IsPedCurrentWeaponSilenced(ped) then return true end
    end

    return false
end)

-- Same list as the server export, for client code that needs to know what fits what (the staff menu uses it)
exports('AttachmentsFor', function(weapon)
    if type(weapon) ~= 'string' then return {} end

    local out = {}
    for id, att in pairs(Weapons.Attachments) do
        local component = att.components and att.components[weapon]
        if component then
            out[#out + 1] = {
                id = id, item = att.item, label = att.label, slot = att.slot,
            }
        end
    end

    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end)

exports('OpenWheel', function() CreateThread(openWheel) end)
exports('FittedOn', function(weaponName) return Fitted[weaponName] or {} end)

-- An inventory wipe removed the guns from the ped
AddEventHandler('bs:weapons:forget', function(weaponHash)
    local name = WEAPON_NAMES[tonumber(weaponHash) or 0]
    if name then Fitted[name] = nil end
    if lastWeaponHash == weaponHash then lastWeapon, lastWeaponHash, lastReportedAmmo = nil, nil, nil end
end)

-- The bag changed (trade, loot, drop)
local refitPending = false
AddEventHandler('bs:weapons:bagChanged', function()
    if refitPending or busy then return end
    refitPending = true
    SetTimeout(300, function()
        refitPending = false
        local name, hash = currentWeapon()
        if name then refit(name, hash) end
    end)
end)

AddEventHandler('bs:weapons:forgetAll', function()
    Fitted = {}
    SyncedAmmo = {}
    lastWeapon, lastWeaponHash, lastReportedAmmo = nil, nil, nil
end)

-- lets bs_inventory cap ammo-box top-ups at the real mag size
exports('ClientMagSize', function(hash) return Weapons.ClientMagSize(PlayerPedId(), hash) end)
