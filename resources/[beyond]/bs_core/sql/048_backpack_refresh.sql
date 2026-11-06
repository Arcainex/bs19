-- Keep each bag ID and its stored contents while replacing the retired pack items.
UPDATE `bs_inventory_items` SET `item` = 'pack_civilian' WHERE `item` = 'pack_small';
UPDATE `bs_inventory_items` SET `item` = 'pack_hiking' WHERE `item` IN ('pack_medium', 'hiking_pack');
UPDATE `bs_inventory_items` SET `item` = 'pack_survival' WHERE `item` = 'pack_large';
UPDATE `bs_inventory_items` SET `item` = 'pack_field_military' WHERE `item` = 'pack_military';
