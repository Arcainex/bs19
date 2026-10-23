-- Booster/gadget loadout slots (901-903 / 911-912) don't fit a TINYINT UNSIGNED, so the column is widened. bs_inventory moves rows already clamped to 255 back into a loadout slot on load.
ALTER TABLE `bs_inventory_items`
    MODIFY COLUMN `slot_x` SMALLINT UNSIGNED NOT NULL DEFAULT 0;
