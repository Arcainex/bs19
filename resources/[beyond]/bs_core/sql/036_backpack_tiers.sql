-- Backpack tiers (bs_inventory). The old single pack ('hiking_pack', and any 'backpack' row) becomes the medium tier.
-- Metadata (bagId) is kept, so whatever was inside the old pack stays inside it.
-- Items that sat in the extra rows an old pack added to the main grid are left alone: the grid keeps those rows until they are emptied.
UPDATE `bs_inventory_items` SET `item` = 'pack_medium' WHERE `item` IN ('hiking_pack', 'backpack');
