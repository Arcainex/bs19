-- Wheel damage that survives a restart.
-- Vehicles restored after streaming out are rebuilt with CreateVehicle (four good tyres), so tyre state is stored as JSON, wheel index -> state: 0 = fine, 1 = burst, 2 = detached.
-- Additive only, see bs_core/server/sv_migrations.lua.

ALTER TABLE `bs_vehicles`
    ADD COLUMN `tyres_burst` LONGTEXT NULL AFTER `parts`;
