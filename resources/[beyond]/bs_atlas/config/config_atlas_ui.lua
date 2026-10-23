-- bs_atlas - config for the node atlas panel (viewer only)
-- Simulation tunables live in bs_zombies/config/config_sim.lua and are edited live from the atlas CONFIG panel (callback zombies:atlas:config)

AtlasUI = AtlasUI or {}

-- 1. Opening it

-- /atlas toggles the panel
-- No RegisterKeyMapping: a mapping on a control that is also polled fires the command twice per press and the
AtlasUI.openCommand = 'atlas'

-- Refuse to open the panel when bs_admin is not running? true (default): no staff resource means nobody gets the map editor. false: dev boxes only.
-- Grants nothing (the six callbacks still refuse everybody server-side); it just lets the panel open for layout work
AtlasUI.requireAdminResource = true

-- 2. Live poll

-- How often the panel asks the server what is in view, ms
-- Each snapshot walks the cells in the requested rectangle (max 4000, decimated above that) plus the near-field agents
AtlasUI.pollMs      = 500
AtlasUI.pollMsMin   = 150
AtlasUI.pollMsMax   = 5000

-- How long BSB.Await waits for one callback, seconds
-- Must be longer than the slowest snapshot and short enough that a human would not think the tool is broken
AtlasUI.callTimeoutMs = 8000

-- Missed polls before the panel shows STALE. 2 forgives one hiccup; higher lies longer, 1 flashes a banner on a single dropped packet.
AtlasUI.staleAfterPolls = 2

-- 3. Observer

-- An observer is a point the server promotes to live individuals even with no player nearby (e.g. watch Sandy Shores at 04:00 on an empty server).
-- It is expensive and time-limited: it keeps hundreds of records alive, and the server expires it after 300s unless the atlas re-registers

-- Seconds between refreshes
-- Must be well below the server TTL (Sim.observer.ttlSeconds, 300s). 100 allows two misses; above ~250 a single dropped call ends the observation.
AtlasUI.observerRefreshSeconds = 100

-- Radius the observer control opens with, and its slider ends
-- The server clamps at Sim.observer.maxRadius (1200m) and reports the clamp back; the panel shows the radius actually granted
AtlasUI.observerRadius    = 300
AtlasUI.observerRadiusMin = 50
AtlasUI.observerRadiusMax = 1200

-- 4. View

-- Metres of world across the screen when the atlas opens. 3000 puts most of Los Santos in frame.
-- Centres on you if found, otherwise on the middle of the world box
AtlasUI.openSpanMetres = 3000.0

-- Zoom limits, metres across the screen
-- Lower bound is about two density cells wide; upper bound is the whole world plus a margin
AtlasUI.minSpanMetres = 120.0
AtlasUI.maxSpanMetres = 16000.0

-- How much bigger than the visible rectangle the snapshot request is
AtlasUI.fetchMargin = 0.15
