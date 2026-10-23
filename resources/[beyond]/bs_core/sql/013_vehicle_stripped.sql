-- A stripped car stays as a hulk; this adds a timestamp so the 3-day cleanup sweep in bs_vehicles/server/sv_main.lua knows what to remove.

ALTER TABLE `bs_vehicles`
    ADD COLUMN IF NOT EXISTS `stripped_at` DATETIME NULL AFTER `scrapped`;
