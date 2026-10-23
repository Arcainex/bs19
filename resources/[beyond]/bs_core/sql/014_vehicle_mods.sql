-- Admin Car Tuning menu: installed performance/visual mods, so a tune persists through despawn and restart.
-- Stored as JSON, mod type -> mod index (as GetVehicleMod/SetVehicleMod), e.g. {"11": 3, "12": 2}. Additive only.

ALTER TABLE `bs_vehicles`
    ADD COLUMN `mods` LONGTEXT NULL AFTER `parts`;
