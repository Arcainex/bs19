-- BeyondSurvival - bs_interactions config. A dot in the screen centre that opens into a ring of options for what you look at. Own system, feeds loot and containers directly.

Interactions = {}

Interactions.Settings = {
    -- Hold to aim (LALT). Releasing without a pick selects nothing.
    targetKey        = 19,
    -- Confirm the highlighted option.
    interactKey      = 38,          -- E
    -- How far the ray reaches.
    maxDistance      = 3.2,
    -- Raycast shape flags: peds, vehicles, objects, world, foliage.
    traceFlags       = 4294967295,

    -- Debug overlay reach. Separate from `maxDistance` (3.2m, interaction reach) so the overlay can inspect any prop in the game, ymap or not.
    debugDistance    = 250.0,
    -- Milliseconds between rays while aiming. 0 = every frame (smoothest).
    scanInterval     = 0,

    -- Fallback search numbers. The camera ray is one of four ways the dot finds a target; the other three are proximity based (see `fallbackWhenNoOptions` in cl_target.lua).

    -- Milliseconds between refreshes of the entity pool snapshot for the proximity fallback. The object pool is large, so 250 is a good balance.
    poolInterval     = 250,

    -- Downward fan of probes cast from the player when the camera ray finds nothing usable.
    probeStartHeight = 0.35,        -- chest, relative to the ped's root
    probeDrop        = 0.95,        -- how far the far end sits below the start
    probeSpread      = 0.5,         -- left/right offset of the outer probes

    -- Extra ray length beyond the player's reach, so a hit just past maxDistance is still measured.
    camPadding       = 1.0,

    -- The dot itself.
    dotSize          = 6,           -- px
    dotIdleAlpha     = 0.35,
    dotActiveAlpha   = 1.0,
    -- Grow the dot into a ring when something is targetable.
    ringSize         = 26,

    -- Outline the entity under the dot.
    useOutline       = true,
    outline          = { r = 200, g = 118, b = 58, a = 190 },

    -- Do not target while these are true.
    blockInVehicle   = false,

    -- The ALT dot is disabled while a firearm is aimed or fired. Crash fix: the probe caches an entity handle across frames and shooting walkers deletes those entities (see blocked() in cl_target.lua).
    blockWhileAiming = true,
    blockWhenDead    = true,
    blockWhenCuffed  = true,
}

-- Options are matched against what the ray hit; the first matching group is shown and every entry is re-validated on the server.
-- model: name or list of names | entityType: 'ped'|'vehicle'|'object'
-- zone: { coords = vector3, radius = number }
-- canInteract(entity, distance, data) -> boolean (client pre-filter)
-- event / serverEvent: fired on pick (server gets the entity net id)
-- item: required item | job/class: required character class
Interactions.Options = {}

--- Registers options at runtime:
---   exports.bs_interactions:AddModel({ 'prop_bin_01a' }, { ... })
Interactions.Models = {}
Interactions.Zones  = {}
