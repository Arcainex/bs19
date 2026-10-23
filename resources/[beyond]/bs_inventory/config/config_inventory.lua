-- bs_inventory - inventory config.

Inventory = {}

Inventory.Settings = {
    -- Player bag grid in cells (F1 editable). Item ids are not tied to these numbers, so changing
    -- them keeps every saved item where it was. Keep width * (height + backpack rows) under 139.
    gridWidth       = 10,
    gridHeight      = 7,
    hotbarSlots     = 5,
    -- Open key (I, since TAB is the shoulder-zoom). Remappable in the FiveM keybind settings.
    openKey         = 'I',
    openCommand     = 'inventory',
    tradeDistance   = 3.0,
    -- Dropping items creates a world container that decays after this many seconds.
    dropLifetime    = 1800,
    -- Dropped stacks always show as one plain bag, not a per-category prop.
    dropModel       = 'prop_paper_bag_01',
    dropModels = {},
    -- How close you have to be to pick a drop up.
    pickupRange     = 1.8,
    -- Items are removed from a corpse container after this long.
    corpseLifetime  = 900,
    -- Weight over the class cap slows the player instead of blocking pickups.
    overweightSlowdown = 0.75,
    -- Backpacks. A pack dropped on death stays until restart; with packDropDespawn on (F1) it goes after packDropLifetime seconds.
    packDropDespawn  = false,
    packDropLifetime = 1800,
    packDropModel    = 'p_michael_backpack_s',
    -- Load (share of the carry limit) where sprinting starts costing extra stamina; at 100% you cannot sprint.
    heavyLoadAt      = 0.8,
    heavySprintDrain = 1.5,
}

Inventory.Containers = {
    small_stash  = { label = 'Stash',   width = 8,  height = 5,  maxWeight = 120.0 },
    vehicle_boot = { label = 'Trunk',   width = 10, height = 6,  maxWeight = 200.0 },
    corpse       = { label = 'Remains', width = 6,  height = 4,  maxWeight = 60.0 },
}

-- Body status: 4 snapshot angles of a hidden clone, shown as images in Field Medical. Needs screenshot-basic for the screenshot path, otherwise a silhouette is shown.
Inventory.BodyRender = {
    enabled = true,
    captureMode = 'internal',  -- 'internal' = NUI game-view grab, 'screenshot-basic' = alternative path
    height = 400.0,        -- capture spot: this far above the player, in open sky
    distance = 8.0,        -- camera to clones
    spacing = nil,         -- nil = computed from fov/aspect so each clone gets a quarter of the frame
    fov = 22.0,
    chroma = { 255, 0, 255 },  -- backdrop colour; the page keys it out
    settleMs = 350,        -- let the clones stream in and the pose settle
    timeoutMs = 3000,      -- give up on a screenshot after this
    encoding = 'jpg', quality = 0.95,
    refreshDebounce = 900, -- ms after an outfit/weapon change before recapturing
    debug = false,
}
