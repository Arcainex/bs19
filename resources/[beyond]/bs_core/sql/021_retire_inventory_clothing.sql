-- Clothing appearance is now NPC/wardrobe-owned, not inventory-owned.
-- Keeps backpacks and bulletproof vests; removes retired clothing items from bags, containers, drops and the synced item-definition catalogue.
DELETE FROM `bs_inventory_items`
WHERE `item` IN (
  'worn_tshirt','field_jacket','hoodie','rain_coat','plain_vest',
  'work_trousers','cargo_pants','work_boots','trainers','dust_mask',
  'gas_mask','cap','safety_glasses','wrist_watch'
);

DELETE FROM `bs_item_definitions`
WHERE `name` IN (
  'worn_tshirt','field_jacket','hoodie','rain_coat','plain_vest',
  'work_trousers','cargo_pants','work_boots','trainers','dust_mask',
  'gas_mask','cap','safety_glasses','wrist_watch'
);