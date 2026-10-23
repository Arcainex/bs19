-- bs_esx_bridge - ESX-shaped API for third-party ESX scripts.
-- Add this file as a shared_script (after '@bs_core/shared/sh_bridge.lua') so ESX is built in the script's own Lua state; functions do not survive export boundaries.
-- The getSharedObject export in sv_main.lua is a best-effort fallback only.
-- See the unsupported-features list at the bottom of this file.

ESX = ESX or {}
ESX.Version = 'bs_esx_bridge 0.1.0'


if IsDuplicityVersion() then
    ----------------------------------------------------------------- server --

    -- xPlayer: a real object built locally, never sent across a boundary. Every method calls bs_core's/bs_inventory's plain-data exports directly.
    local function buildXPlayer(src)
        src = tonumber(src)
        local self = { source = src }

        function self.getIdentifier()
            return ('bs:%d'):format(src)
        end

        function self.getMoney()
            local ok, summary = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
            return (ok and summary and summary.accounts and summary.accounts.cash) or 0
        end

        function self.addMoney(amount, reason)
            return exports.bs_core:AddMoney(src, 'cash', amount, reason or 'esx_bridge')
        end

        function self.removeMoney(amount, reason)
            return exports.bs_core:RemoveMoney(src, 'cash', amount, reason or 'esx_bridge')
        end

        -- ESX account names: 'money' = cash, 'bank' = bank. 'black_money' has no equivalent here and always reports zero. See the unsupported-features note at the end of this file.
        local function accountKey(name)
            if name == 'bank' then return 'bank' end
            if name == 'money' or name == 'cash' then return 'cash' end
            return nil -- black_money and anything else
        end

        function self.getAccount(name)
            local key = accountKey(name)
            if not key then return { name = name, money = 0 } end
            local ok, summary = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
            local accounts = (ok and summary and summary.accounts) or {}
            return { name = name, money = accounts[key] or 0 }
        end

        function self.getAccounts()
            local ok, summary = pcall(function() return exports.bs_core:GetPlayerSummary(src) end)
            local accounts = (ok and summary and summary.accounts) or {}
            return {
                { name = 'money', money = accounts.cash or 0 },
                { name = 'bank',  money = accounts.bank or 0 },
                { name = 'black_money', money = 0 }, -- unsupported, see note above
            }
        end

        function self.addAccountMoney(name, amount, reason)
            local key = accountKey(name)
            if not key then return false end
            return exports.bs_core:AddMoney(src, key, amount, reason or 'esx_bridge')
        end

        function self.removeAccountMoney(name, amount, reason)
            local key = accountKey(name)
            if not key then return false end
            return exports.bs_core:RemoveMoney(src, key, amount, reason or 'esx_bridge')
        end

        function self.addInventoryItem(item, count)
            local ok, given = pcall(function() return exports.bs_inventory:GiveItem(src, item, count or 1) end)
            return ok and given and true or false
        end

        function self.removeInventoryItem(item, count)
            local ok, removed = pcall(function() return exports.bs_inventory:RemoveItem(src, item, count or 1) end)
            return ok and removed and true or false
        end

        function self.getInventoryItem(item)
            local ok, count = pcall(function() return exports.bs_inventory:CountItem(src, item) end)
            return { name = item, count = (ok and count) or 0 }
        end

        function self.hasItem(item, count)
            return self.getInventoryItem(item).count >= (count or 1)
        end

        function self.getMeta(key)
            local ok, value = pcall(function() return exports.bs_core:GetPlayerMeta(src, key, nil) end)
            return ok and value or nil
        end

        function self.setMeta(key, value)
            exports.bs_core:SetPlayerMeta(src, key, value)
        end

        function self.clearMeta(key)
            exports.bs_core:SetPlayerMeta(src, key, nil)
        end

        -- Not real job/grade/salary parity (see the unsupported-features note). This is a label so job-gated scripts do not error on a nil job.
        function self.getJob()
            return { name = 'unemployed', label = 'Unemployed', grade = 0, grade_name = 'unemployed',
                grade_label = 'Unemployed', grade_salary = 0 }
        end
        function self.setJob(_, _) return false end

        function self.getCoords()
            local ped = GetPlayerPed(src)
            if not ped or ped == 0 then return vector3(0.0, 0.0, 0.0) end
            return GetEntityCoords(ped)
        end

        function self.setCoords(coords)
            local ped = GetPlayerPed(src)
            if not ped or ped == 0 or not coords then return end
            SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
        end

        function self.save()
            return exports.bs_core:SavePlayer(src, true)
        end

        function self.showNotification(message, _)
            TriggerClientEvent('bs:ui:notify', src, { type = 'info', message = tostring(message) })
        end

        return self
    end

    -- Returns nil for a source with no loaded character, like real ESX.
    function ESX.GetPlayerFromId(src)
        src = tonumber(src)
        if not src or not GetPlayerName(src) then return nil end
        local ok, player = pcall(function() return exports.bs_core:GetPlayer(src) end)
        if not ok or not player then return nil end
        return buildXPlayer(src)
    end

    -- Server callback transport (client asks server)

    local SV_REQUEST  = 'bsesx:triggerServerCallback'
    local SV_RESPONSE = 'bsesx:clientCallback'
    local svHandlers  = {}

    --- ESX.RegisterServerCallback(name, function(source, cb, ...) cb(result) end)
    function ESX.RegisterServerCallback(name, fn)
        svHandlers[name] = fn
    end

    RegisterNetEvent(SV_REQUEST, function(name, token, ...)
        local handler = svHandlers[name]
        if not handler then return end -- another resource owns this name

        local src = source
        local args = table.pack(...)

        CreateThread(function()
            local response
            local cb = function(...) response = table.pack(...) end
            local ok, err = pcall(handler, src, cb, table.unpack(args, 1, args.n))
            if not ok then
                print(('^1[bs_esx_bridge]^7 server callback "%s" errored: %s'):format(name, tostring(err)))
                return TriggerClientEvent(SV_RESPONSE, src, token, nil)
            end
            response = response or {}
            TriggerClientEvent(SV_RESPONSE, src, token, table.unpack(response, 1, response.n or #response))
        end)
    end)

    -- ESX.TriggerClientCallback(target, name, cb, ...) is built on BSB.AwaitClient, so clients register with the plain BSB.RegisterClientCallback name.
    function ESX.TriggerClientCallback(target, name, cb, ...)
        local args = table.pack(...)
        CreateThread(function()
            local result = table.pack(BSB.AwaitClient(target, name, 15000, table.unpack(args, 1, args.n)))
            if cb then cb(table.unpack(result, 1, result.n)) end
        end)
    end

    -- Usable items: dispatches to whichever resource registered the item via ESX.RegisterUsableItem, over a same-side TriggerEvent. bs_inventory fires this event once per used item (see the inventory:use callback in bs_inventory/server/sv_main.lua).
    -- Limitation: the item still needs an entry with usable = true in bs_inventory's Items config.

    function ESX.RegisterUsableItem(item, cb)
        if type(item) ~= 'string' or type(cb) ~= 'function' then return end
        AddEventHandler('bsesx:useItem:' .. item, function(playerId)
            local ok, err = pcall(cb, playerId)
            if not ok then
                print(('^1[bs_esx_bridge]^7 usable item "%s" errored: %s'):format(item, tostring(err)))
            end
        end)
    end

    -- Commands - delegates to BSB.RegisterCommand

    -- ESX.RegisterCommand(name, permissionGroups, callback, requiresPlayer, help)
    -- permissionGroups: a string ACE, a table of ACE strings (first one is used), or nil for anyone.
    function ESX.RegisterCommand(name, permissionGroups, callback, requiresPlayer, help)
        local ace = nil
        if type(permissionGroups) == 'string' and permissionGroups ~= 'user' then
            ace = permissionGroups
        elseif type(permissionGroups) == 'table' then
            -- One ACE per command, not a group list: the first non-'user' entry wins. Finer group logic needs its own check in the callback.
            for _, g in ipairs(permissionGroups) do
                if g ~= 'user' then ace = g break end
            end
        end

        BSB.RegisterCommand(name, ace, (help and help.help) or name, {}, function(src, args, raw)
            local xPlayer = src > 0 and ESX.GetPlayerFromId(src) or nil
            if requiresPlayer and not xPlayer then return end
            local ok, err = pcall(callback, xPlayer, args, function(msg)
                if src > 0 then TriggerClientEvent('bs:ui:notify', src, { type = 'error', message = msg }) end
            end)
            if not ok then
                print(('^1[bs_esx_bridge]^7 command "/%s" errored: %s'):format(name, tostring(err)))
            end
        end)
    end
else
    ----------------------------------------------------------------- client --

    ESX.PlayerData  = ESX.PlayerData or {}
    ESX.PlayerLoaded = ESX.PlayerLoaded or false

    local SV_REQUEST  = 'bsesx:triggerServerCallback'
    local SV_RESPONSE = 'bsesx:clientCallback'
    local pending, sequence = {}, 0

    -- ESX.TriggerServerCallback(name, cb, ...)
    function ESX.TriggerServerCallback(name, cb, ...)
        sequence = sequence + 1
        local token = ('%s:%d'):format(GetCurrentResourceName(), sequence)
        pending[token] = cb

        TriggerServerEvent(SV_REQUEST, name, token, ...)
    end

    RegisterNetEvent(SV_RESPONSE, function(token, ...)
        local cb = pending[token]
        pending[token] = nil
        if cb then cb(...) end
    end)

    -- Registers a callback the server may invoke on this client via ESX.TriggerClientCallback (alias of BSB.RegisterClientCallback).
    ESX.RegisterClientCallback = BSB.RegisterClientCallback

    -- Standard events are re-broadcast from bs_core hooks by bs_esx_bridge/server/sv_main.lua and client/cl_main.lua. Not registered here, since a shared file runs once per including resource and would re-broadcast.
end

-- Not supported by this bridge:
-- - ESX job/society system (job/grade/salary). getJob()/setJob() are labels only; BeyondSurvival has bs_factions.
-- - black_money: always 0.
-- - Full weapon-loadout/component API (addWeaponComponent, setWeaponTint, per-component ammo). Use bs_weapons' exports.
-- - ESX.GetPlayerFromIdentifier: use ESX.GetPlayerFromId(source).
-- - Scripts that hardcode exports['es_extended']:getSharedObject() need that line changed to bs_esx_bridge.
