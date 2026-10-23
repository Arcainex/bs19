-- Two-dimensional placement for inventory items.
-- slot_x stays the flat slot index (hotbar, crafting, drops and moves all key on it); the grid position gets its own columns. Additive and idempotent. slot_y stays untouched.
-- 0,0 means not placed: existing rows are repacked on first load, biggest item first (see Grid.Repack in bs_inventory/server/sv_grid.lua).

ALTER TABLE `bs_inventory_items`
    ADD COLUMN IF NOT EXISTS `grid_x` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `slot_y`,
    ADD COLUMN IF NOT EXISTS `grid_y` TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER `grid_x`;
