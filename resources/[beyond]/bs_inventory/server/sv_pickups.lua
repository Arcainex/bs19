-- Presentation receipts, not inventory arithmetic. Record only after an operation succeeds.
-- Sent through the existing inventory state packet: no extra network event or database access.
local pending, sequence = {}, 0
local epoch = ('%d:%d'):format(os.time(), GetGameTimer())
Inv.Pickups = {}

function Inv.Pickups.Record(src, item, amount, kind, character)
    src = tonumber(src)
    if not src then return end
    local cfg = Inventory.PickupVisuals or {}
    if cfg.enabled == false or (kind == 'removed' and cfg.showRemoved ~= true)
        or (kind ~= 'removed' and cfg.showReceived == false) then return end
    local player = exports.bs_core:GetPlayer(src)
    local def = Items.Get(item)
    amount = math.floor(tonumber(amount) or 0)
    if not player or not def or amount < 1 or (character and tostring(character) ~= tostring(player.charId)) then return end
    local batch = pending[src]
    if not batch or batch.character ~= player.charId then
        batch = { character = player.charId, changes = {} }; pending[src] = batch
    end
    -- One mutation normally produces one receipt; bound unusual multi-operation bursts too.
    if #batch.changes >= 128 then table.remove(batch.changes, 1) end
    batch.changes[#batch.changes + 1] = {
        item = item, amount = amount, kind = kind or 'received', category = def.category or 'misc',
        w = def.w or 1, h = def.h or 1, rarity = def.rarity,
    }
end

function Inv.Pickups.Flush(src, payload)
    src = tonumber(src)
    local batch = pending[src]; pending[src] = nil
    if not batch then return end
    local player = exports.bs_core:GetPlayer(src)
    if not player or player.charId ~= batch.character or (Inventory.PickupVisuals or {}).enabled == false then return end
    sequence = sequence + 1
    batch.epoch, batch.sequence = epoch, sequence
    payload.pickups = batch
end

AddEventHandler('playerDropped', function() pending[source] = nil end)
AddEventHandler('bs:hook:player:unloaded', function(player) if player then pending[player.source] = nil end end)
print(('^2[BeyondSurvival]^7 (inventory) pickup visuals ready (enabled=%s, native slots, progress-aware)')
    :format(tostring((Inventory.PickupVisuals or {}).enabled ~= false)))
