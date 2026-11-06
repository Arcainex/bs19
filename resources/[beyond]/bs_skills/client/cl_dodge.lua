-- bs_skills - dodge: sHIFT + W W / S S / A A / D D dodges forward / backward / left / right.

-- Declarations first: a local used above its declaration compiles to a global lookup (nil at runtime)

local cfg                                     -- Skills.Dodge, read once below
local dodging      = false                    -- the one piece of state
local lastDodgeAt  = 0
local lastTapKey   = nil
local lastTapAt    = 0
-- Heading is taken at the first tap: movement is camera-relative
local lastTapHeading = nil

-- Keep a short heading history (20 samples, last second).
local headingHistory = {}
CreateThread(function()
    while true do
        Wait(50)
        local now = GetGameTimer()
        headingHistory[#headingHistory + 1] = { t = now, h = GetEntityHeading(PlayerPedId()) }
        while #headingHistory > 0 and now - headingHistory[1].t > 1200 do table.remove(headingHistory, 1) end
    end
end)
local function headingBefore(t)
    local best
    for i = #headingHistory, 1, -1 do
        if headingHistory[i].t <= t then best = headingHistory[i].h break end
    end
    return best or (headingHistory[1] and headingHistory[1].h) or GetEntityHeading(PlayerPedId())
end
local resolved     = {}                       -- [direction] = anim or false
local resolveDone  = false
local lastRefusal  = 'none yet'               -- for /skilltest
local loopAlive    = false                    -- for /skilltest: did the thread survive start-up
local bootState    = 'not started'            -- for /skilltest

-- Debug surface for /skilltest (cl_skilldebug.lua).
BS_SkillsDebug = BS_SkillsDebug or {}

-- INPUT_SPRINT, read as a modifier only. Never disabled, so Shift still sprints.
local SPRINT_CONTROL = 21

-- Movement controls are polled, not registered as key mappings.
local MOVE_UP, MOVE_DOWN, MOVE_LEFT, MOVE_RIGHT = 32, 33, 34, 35

-- Animations, checked with GetAnimDuration

-- Clip names come from a dump of the game's clip dictionaries (github.com/DurtyFree/gta-v-data-dumps), never guessed.
-- DoesAnimDictExist can be true for a dict lacking the clip, so GetAnimDuration is the honest probe (missing = 0.0).
-- move_strafe@roll (and _fps) has 20 combatroll_* clips; the suffix is the roll angle relative to facing, and
-- left and right come from different families. p1 is used, p2 is the get-up variant.
-- melee@unarmed@streamed_core has dodge_generic_l / _r / _centre. Flags: 16 upper body only, 32 player control, 48 both.
-- Rule: a wrong full-body clip is worse than none, so list bottoms are upper-body-only or nothing.

-- Left/right use combatroll_fwd_p1_90 and combatroll_bwd_p1_-90. Which one is the right side is inferred
-- from the angle sign and can't be proven from a dump. If left and right are swapped in game,
-- set Skills.Dodge.mirrorSides = true.
local CANDIDATES = {
    -- Straight ahead: plain forward combat roll, full-body is correct here.
    forward = {
        { dict = 'move_strafe@roll',            clip = 'combatroll_fwd_p1_00',  flag = 32, style = 'roll' },
        { dict = 'move_strafe@roll_fps',        clip = 'combatroll_fwd_p1_00',  flag = 32, style = 'roll' },
        { dict = 'melee@unarmed@streamed_core', clip = 'dodge_generic_centre',  flag = 48, style = 'upper' },
    },

    -- 180 is the roll made for going backwards.
    backward = {
        { dict = 'move_strafe@roll',            clip = 'combatroll_bwd_p1_180', flag = 32, style = 'roll' },
        { dict = 'move_strafe@roll_fps',        clip = 'combatroll_bwd_p1_180', flag = 32, style = 'roll' },
        { dict = 'melee@unarmed@streamed_core', clip = 'dodge_generic_centre',  flag = 48, style = 'upper' },
    },

    -- -90 is the pure left roll. It lives in the bwd family, which owns the negative angles.
    left = {
        { dict = 'move_strafe@roll',            clip = 'combatroll_bwd_p1_-90', flag = 32, style = 'roll' },
        { dict = 'move_strafe@roll_fps',        clip = 'combatroll_bwd_p1_-90', flag = 32, style = 'roll' },
        { dict = 'melee@unarmed@streamed_core', clip = 'dodge_generic_l',       flag = 32, style = 'sidestep' },
    },

    -- +90 is the pure right roll, in the fwd family. dodge_generic_r is full-body because it is handed.
    right = {
        { dict = 'move_strafe@roll',            clip = 'combatroll_fwd_p1_90',  flag = 32, style = 'roll' },
        { dict = 'move_strafe@roll_fps',        clip = 'combatroll_fwd_p1_90',  flag = 32, style = 'roll' },
        { dict = 'melee@unarmed@streamed_core', clip = 'dodge_generic_r',       flag = 32, style = 'sidestep' },
    },
}

-- Skills.Dodge.animStyle: 'roll' - try everything, best first (default) 'sidestep' - skip the full-body rolls
local STYLE_ALLOWED = {
    roll     = { roll = true, upper = true, sidestep = true },
    sidestep = { upper = true, sidestep = true },
    none     = {},
}

-- The probe. Same shape as resolveWorkAnim in bs_weapons/client/cl_main.lua.
local function resolveOne(direction)
    local style   = (cfg and cfg.animStyle) or 'roll'
    local allowed = STYLE_ALLOWED[style] or STYLE_ALLOWED.roll

    for _, c in ipairs(CANDIDATES[direction] or {}) do
        if allowed[c.style or 'roll'] and c.dict and DoesAnimDictExist(c.dict) then
            if not HasAnimDictLoaded(c.dict) then RequestAnimDict(c.dict) end
            local waited = 0
            while not HasAnimDictLoaded(c.dict) and waited < 1200 do
                Wait(10); waited = waited + 10
            end

            if HasAnimDictLoaded(c.dict) then
                local ok, duration = pcall(GetAnimDuration, c.dict, c.clip)
                if ok and type(duration) == 'number' and duration > 0.0 then
                    print(('^2[BeyondSurvival]^7 (skills) dodge animation [%s]: %s / %s  (%s, flag %d)')
                        :format(direction, c.dict, c.clip, c.style or 'roll', c.flag or 32))
                    return c
                end
            end
        end
    end

    -- Not an error: running off the end of the list means no clip, which is the intended floor.
    print(('^3[BeyondSurvival]^7 (skills) no dodge animation resolved for [%s] - the dodge still MOVES, it is just a fast step (this is the intended floor, not a bug)')
        :format(direction))
    return false
end

-- Resolved once on a thread and cached, never on the hot path.
local function resolveAll()
    if resolveDone then return end
    resolveDone = true
    for direction in pairs(CANDIDATES) do
        resolved[direction] = resolveOne(direction)
    end

    -- Escape hatch for the sign convention (see note above the table).
    if cfg and cfg.mirrorSides then
        resolved.left, resolved.right = resolved.right, resolved.left
        print('^3[BeyondSurvival]^7 (skills) dodge: mirrorSides is on - left and right clips swapped')
    end
end

-- Skill

-- Survival level, or 0 if the bs_skills cache is not filled yet.
local function survivalLevel()
    local ok, level = pcall(function() return exports.bs_skills:GetSkillLevel('survival') end)
    if ok and type(level) == 'number' then return level end
    return 0
end

local function hasBreakFall()
    local ok, value = pcall(function() return exports.bs_skills:HasFlag('break_fall') end)
    return ok and value == true
end

-- 0.0 at the minimum level that unlocks the dodge, 1.0 at the tree cap.
local function trainedFraction()
    local tree    = (Skills.Trees and Skills.Trees.survival) or {}
    local maxLvl  = tree.maxLevel or 20
    local minLvl  = cfg.minLevel or 0
    local span    = math.max(1, maxLvl - minLvl)
    local t       = (survivalLevel() - minLvl) / span
    return math.max(0.0, math.min(1.0, t))
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Refusals

-- Refusal reasons that are not shown to the player: driving, in a menu, dead or ragdolled.
local quietReasons = {
    ['in a vehicle'] = true,
    ['nui focus']    = true,
    ['dead']         = true,
    ['ragdoll']      = true,
}

-- One sentence per refusal code.
local REASON_KEYS = {
    ['aiming']      = 'dodge.aiming',
    ['cooldown']    = 'dodge.cooldown',
    ['swimming']    = 'dodge.swimming',
    ['airborne']    = 'dodge.ground',
    ['in air']      = 'dodge.ground',
    ['not on foot'] = 'dodge.not_now',
    ['cuffed']      = 'dodge.cuffed',
    ['disabled']    = 'dodge.disabled',
}
local REASON_TEXT = setmetatable({}, {
    __index = function(_, k) local key = REASON_KEYS[k]; return key and L(key) or nil end,
})

local function debugPrint(reason)
    lastRefusal = tostring(reason) .. ' @ ' .. tostring(GetGameTimer())
    if cfg and cfg.debug then
        print('^3[BeyondSurvival]^7 (skills) dodge refused: ' .. tostring(reason))
    end
end

-- States where Shift + double-tap does nothing, cheapest check first:
-- - in a vehicle
-- - swimming (velocity would fight the swim solver)
-- - ragdolled, dead or in a scripted task
-- - in the air (would be a double jump)
-- - NUI focus (typing WASD with Shift held would trigger dodges). IsNuiFocused covers every menu without
-- each one having to report in.
local function blocked(ped)
    if IsPedInAnyVehicle(ped, true)            then return 'in a vehicle' end
    if IsNuiFocused()                          then return 'nui focus' end
    if IsPedDeadOrDying(ped, true)             then return 'dead' end
    if IsPedRagdoll(ped)                       then return 'ragdoll' end
    if IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) then return 'swimming' end
    if IsPedFalling(ped) or IsPedJumping(ped) or IsPedClimbing(ped) then return 'airborne' end
    if not IsPedOnFoot(ped)                    then return 'not on foot' end
    if IsEntityInAir(ped)                      then return 'in air' end
    if IsPedCuffed(ped)                        then return 'cuffed' end

    -- Aiming down sights: off by default, see config_abilities.lua.
    if not cfg.allowWhileAiming then
        if IsPlayerFreeAiming(PlayerId())
            or IsControlPressed(0, 25)
            or IsDisabledControlPressed(0, 25) then
            return 'aiming'
        end
    end

    return nil
end

-- The dodge itself

-- Notify with fallbacks, so a message can't silently land nowhere (bs_ui stopped or renamed event):
-- 1. bs_ui export, if started and exposed
-- 2. client event used by the rest of the project
-- 3. native game notification (guaranteed)
-- Also printed to F8 every time so the owner can copy it.
local function notify(kind, message, duration)
    local delivered = false

    if GetResourceState('bs_ui') == 'started' then
        delivered = pcall(function()
            exports.bs_ui:Notify({ type = kind, message = message, duration = duration })
        end)
    end

    -- Project-standard event. Fires even if the export existed, a duplicate beats none.
    pcall(function()
        TriggerEvent('bs:ui:notify', { type = kind, message = message, duration = duration })
    end)

    if not delivered then
        -- Native notification, can't be swallowed by a stopped resource.
        pcall(function()
            BeginTextCommandThefeedPost('STRING')
            AddTextComponentSubstringPlayerName('~y~' .. message)
            EndTextCommandThefeedPostTicker(false, false)
        end)
    end

    print('^3[BeyondSurvival]^7 (skills) dodge: ' .. message)
end

local lastComplaintAt = 0

-- Rate-limited because these fire off a key people mash.
local function complain(message)
    if cfg and cfg.announceRefusals == false then return end
    local now = GetGameTimer()
    if now - lastComplaintAt < ((cfg and cfg.announceCooldownMs) or 2500) then return end
    lastComplaintAt = now
    notify('warn', message, 2600)
end

-- Single entry point for a refused dodge.
local function refuse(reason, text)
    debugPrint(reason)
    -- locked = skill not unlocked yet: the double tap is just movement, no message
    if reason ~= 'locked' and not quietReasons[reason] then
        complain(text or REASON_TEXT[reason] or L('dodge.not_now'))
    end
    return false
end

-- Is the dodge allowed right now, and if not why.
local levelGate, stateGate  -- forward declarations, see the Lua 5.4 note above

-- Unit vectors for the four directions from the ped's heading, so left means the character's left.
local function directionVector(ped, direction, fromHeading)
    local heading = math.rad(fromHeading or GetEntityHeading(ped))
    -- GTA headings: 0 = north (+Y), increasing anticlockwise.
    local fx, fy = -math.sin(heading), math.cos(heading)
    local rx, ry =  math.cos(heading), math.sin(heading)

    if direction == 'forward'  then return  fx,  fy end
    if direction == 'backward' then return -fx, -fy end
    if direction == 'left'     then return -rx, -ry end
    return rx, ry
end

-- Level gate: returns the sentence, not a boolean
function levelGate()
    local need = (cfg and cfg.minLevel) or 0
    if need <= 0 then return nil end
    local have = survivalLevel()
    if have >= need then return nil end
    return L('dodge.need_level', { need = need, have = have })
end

-- State, cooldown and stamina checks. Returns reason code, sentence (both nil if allowed).
function stateGate(ped)
    if not cfg or not cfg.enabled then return 'disabled', REASON_TEXT['disabled'] end

    local why = blocked(ped)
    if why then return why, REASON_TEXT[why] end

    local levelWhy = levelGate()
    if levelWhy then return 'locked', levelWhy end

    -- Unlocked as a perk, not given to everyone.
    if (cfg.requirePerk ~= false) then
        local ok, has = pcall(function() return exports.bs_skills:HasPerk('dodge_roll') end)
        -- the Fighting perk Footwork unlocks the same roll
        if not (ok and has) then
            ok, has = pcall(function() return exports.bs_skills:HasPerk('fight_footwork') end)
        end
        if not (ok and has) then
            return 'locked', L('dodge.locked')
        end
    end

    local t        = trainedFraction()
    local cost     = lerp(cfg.staminaCost or 22.0, cfg.staminaCostAtMax or 9.0, t)
    local cooldown = lerp(cfg.cooldownMs or 1600, cfg.cooldownMsAtMax or 700, t)
    if hasBreakFall() then
        local bonus = cfg.perkBonus or 0.0
        cost, cooldown = cost * (1.0 - bonus), cooldown * (1.0 - bonus)
    end

    local now = GetGameTimer()
    if now - lastDodgeAt < cooldown then
        return 'cooldown', L('dodge.recovering', { s = ('%.1f'):format(math.max(0.0, (cooldown - (now - lastDodgeAt)) / 1000.0)) })
    end

    local stamina  = 100.0
    local okNeeds, needs = pcall(function() return exports.bs_core:GetNeeds() end)
    if okNeeds and type(needs) == 'table' and type(needs.stamina) == 'number' then
        stamina = needs.stamina
    end

    local floor = math.max(cost, cfg.staminaFloor or 0.0)
    if stamina < floor then
        return 'stamina', L('dodge.stamina', { need = math.floor(floor + 0.5), have = math.floor(stamina + 0.5) })
    end

    return nil, nil, cost, cooldown, t
end

local rollTimeMs
local function p2Of(anim)
    if not anim or anim.style ~= 'roll' then return nil end
    local c2 = anim.clip:gsub('_p1_', '_p2_', 1)
    if c2 == anim.clip or not HasAnimDictLoaded(anim.dict) then return nil end
    local ok, d = pcall(GetAnimDuration, anim.dict, c2)
    if ok and type(d) == 'number' and d > 0.0 then return c2, d end
    return nil
end

rollTimeMs = function(anim)
    if not anim or not HasAnimDictLoaded(anim.dict) then return 0 end
    local ok, d1 = pcall(GetAnimDuration, anim.dict, anim.clip)
    if not ok or type(d1) ~= 'number' then return 0 end
    local ms = d1 * 1000.0 * (cfg.p1Portion or 1.0)
    if cfg.playGetUp ~= false then
        local _, d2 = p2Of(anim)
        if d2 then ms = ms + d2 * 1000.0 end
    end
    return math.floor(ms + (cfg.extraLockMs or 0))
end

local function performDodge(direction, fromHeading)
    if dodging then return refuse('busy', L('dodge.busy')) end

    local ped = PlayerPedId()

    local why, text, cost, _, t = stateGate(ped)
    if why then return refuse(why, text) end

    local speed = lerp(cfg.speed or 7.0, cfg.speedAtMax or 9.5, t or 0.0)
    local now   = GetGameTimer()

    -- Stamina is read through GetNeeds and spent through AdjustStamina.
    lastRefusal = 'none - last dodge succeeded @ ' .. tostring(now)

    dodging     = true
    lastDodgeAt = now

    pcall(function() exports.bs_core:AdjustStamina(-cost) end)
    -- bs_fighting listens for this to open a counter window
    TriggerEvent('bs:skills:dodged', direction)

    local anim = resolved[direction]
    if anim then
        -- Blend in and out hard, with a duration that ends with the push so no clip tail lingers.
        -- Flag is per candidate: rolls use 32 (full body, player control enabled), the centre slip uses 48
        -- (upper body only). Default is 48, so an unknown clip plays on the torso only.
        -- For rolls: play p1 (roll) then p2 (get-up), flag 0 so movement input can't cancel it.
        local flag = anim.flag or 48
        if anim.style == 'roll' then flag = cfg.rollFlag or 0 end
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, cfg.blendOut or -2.0,
            -1, flag, 0.0, false, false, false)
    end
    local animMs = rollTimeMs(anim)

    CreateThread(function()
        local dx, dy  = directionVector(ped, direction, fromHeading)
        local pushMs  = cfg.pushMs or 340
        local lift    = cfg.lift or 0.0
        local started = GetGameTimer()

        -- Heading is captured before anything moves. Roll clips rotate the root, so the ped would end up facing
        -- somewhere else. Holding the heading for the push (instead of restoring at the end) avoids a one-frame
        -- snap. Means no steering during the ~340 ms. Set Skills.Dodge.lockHeading = false to allow drift.
        local heading     = fromHeading or GetEntityHeading(ped)
        local lockHeading = (cfg.lockHeading ~= false)

        while true do
            local elapsed = GetGameTimer() - started
            if elapsed >= pushMs then break end

            -- Exit conditions are re-checked every iteration, not just at the start: 340 ms is long enough to die
            local live = PlayerPedId()
            if live ~= ped or IsPedDeadOrDying(live, true) or IsPedRagdoll(live)
                or IsPedInAnyVehicle(live, true) then
                break
            end

            -- Cosine decay from full speed to zero across the window, so it reads as a push you recover from instead of a lurch and stop.
            local k  = 1.0 - (elapsed / pushMs)
            local mag = speed * (0.5 + 0.5 * math.cos((1.0 - k) * math.pi))

            -- Z comes from the ped's current velocity, not zero, otherwise gravity is cancelled and a dodge off a ledge floats.
            local vel      = GetEntityVelocity(live)
            local vz       = (type(vel) == 'table' or type(vel) == 'userdata') and (vel.z or 0.0) or 0.0
            local addLift  = (elapsed < pushMs / 3) and lift or 0.0

            SetEntityVelocity(live, dx * mag, dy * mag, vz + addLift)

            -- Re-applied every frame because the clip rotates the root every frame.
            if lockHeading then SetEntityHeading(live, heading) end

            Wait(0)
        end

        local p1Ms = 0
        if anim and HasAnimDictLoaded(anim.dict) then
            local ok, d1 = pcall(GetAnimDuration, anim.dict, anim.clip)
            if ok and type(d1) == 'number' then p1Ms = math.floor(d1 * 1000.0 * (cfg.p1Portion or 1.0)) end
        end
        local c2 = (cfg.playGetUp ~= false) and p2Of(anim) or nil
        local p2Started = false
        while GetGameTimer() - started < animMs do
            local live = PlayerPedId()
            if live ~= ped or IsPedDeadOrDying(live, true) or IsPedRagdoll(live)
                or IsPedInAnyVehicle(live, true) then break end
            if c2 and not p2Started and GetGameTimer() - started >= p1Ms - (cfg.chainOverlapMs or 60) then
                p2Started = true
                if HasAnimDictLoaded(anim.dict) then
                    TaskPlayAnim(live, anim.dict, c2, cfg.chainBlendIn or 4.0, cfg.blendOut or -2.0,
                        -1, cfg.rollFlag or 0, 0.0, false, false, false)
                end
            end
            if cfg.lockControls ~= false then
                DisableControlAction(0, 30, true); DisableControlAction(0, 31, true) -- move
                DisableControlAction(0, 21, true); DisableControlAction(0, 22, true) -- sprint/jump
                DisableControlAction(0, 24, true); DisableControlAction(0, 25, true) -- attack/aim
                DisableControlAction(0, 140, true); DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true); DisableControlAction(0, 37, true)
            end
            Wait(0)
        end
        dodging = false

        -- Shift is both the dodge modifier and sprint, and still held when controls return, so the ped would sprint off.
        local untilAt = GetGameTimer() + 1500
        while GetGameTimer() < untilAt
              and (IsControlPressed(0, SPRINT_CONTROL) or IsDisabledControlPressed(0, SPRINT_CONTROL)) do
            DisableControlAction(0, SPRINT_CONTROL, true)
            Wait(0)
        end
    end)
end

-- Input

-- Maps a control to a direction. A table so the key list and direction list can't drift apart.
local TAP_CONTROLS = {
    { control = MOVE_UP,    direction = 'forward'  },
    { control = MOVE_DOWN,  direction = 'backward' },
    { control = MOVE_LEFT,  direction = 'left'     },
    { control = MOVE_RIGHT, direction = 'right'    },
}

-- Wait for bs_core, but don't depend on it.
local function waitForCore(maxMs)
    local waited = 0
    while waited < maxMs do
        local ok, loaded = pcall(function() return exports.bs_core:IsLoaded() end)
        if ok and loaded then return true end
        if not ok and waited == 0 then
            print('^3[BeyondSurvival]^7 (skills) bs_core:IsLoaded not callable - proceeding on a timer instead. This is not fatal.')
            -- Don't keep calling an export that doesn't exist.
            Wait(maxMs)
            return false
        end
        Wait(500); waited = waited + 500
    end
    return false
end

CreateThread(function()
    cfg = Skills.Dodge or {}

    -- Boot line, always printed (not behind debug), so "did the file load" never needs a config edit and restart.
    if not Skills or not Skills.Dodge then
        bootState = 'CONFIG MISSING'
        print('^1[BeyondSurvival]^7 (skills) cl_dodge.lua LOADED but Skills.Dodge is nil - config/config_abilities.lua did not load, or it loaded BEFORE config_skills.lua and its table was overwritten. Check shared_scripts order in fxmanifest.lua. The dodge is OFF.')
        return
    end

    print(('^2[BeyondSurvival]^7 (skills) cl_dodge.lua loaded - enabled=%s minLevel=%s doubleTapMs=%s. Type /skilltest in game for the full picture.')
        :format(tostring(cfg.enabled), tostring(cfg.minLevel), tostring(cfg.doubleTapMs)))

    if not cfg.enabled then
        bootState = 'disabled in config'
        print('^3[BeyondSurvival]^7 (skills) dodge is disabled by config (Skills.Dodge.enabled = false).')
        return
    end

    bootState = 'waiting for bs_core'
    waitForCore(15000)
    Wait(2000)

    bootState = 'probing animations'
    resolveAll()

    bootState  = 'running'
    loopAlive  = true

    while true do
        -- Two wait rates: per-frame polling only while Shift is held, 150 ms idle otherwise.
        local shift = IsControlPressed(0, SPRINT_CONTROL)
            or IsDisabledControlPressed(0, SPRINT_CONTROL)

        if not shift then
            lastTapKey = nil
            Wait(150)
            goto continue
        end

        do
            -- The gesture is detected first and the gates are checked inside performDodge
            if IsNuiFocused() then
                lastTapKey = nil
                Wait(100)
                goto continue
            end

            for _, entry in ipairs(TAP_CONTROLS) do
                if IsControlJustPressed(0, entry.control)
                    or IsDisabledControlJustPressed(0, entry.control) then

                    local now = GetGameTimer()

                    if lastTapKey == entry.direction
                        and (now - lastTapAt) < (cfg.doubleTapMs or 420) then
                        -- Consume the pair: otherwise a third tap would pair with the second
                        local okS, hud = pcall(function() return exports.bs_ui:GetHudSettings() end)
                        local playerOff = okS and type(hud) == 'table' and hud.dodge == false
                        local h = lastTapHeading
                        lastTapKey = nil
                        lastTapAt  = 0
                        lastTapHeading = nil
                        if not playerOff then performDodge(entry.direction, h) end
                    else
                        lastTapKey = entry.direction
                        lastTapAt  = now
                        lastTapHeading = headingBefore(now - 200)
                    end

                    break
                end
            end

            Wait(0)
        end

        ::continue::
    end
end)

-- Debug surface for /skilltest.

BS_SkillsDebug.dodge = function()
    local ped = PlayerPedId()
    local why, text = nil, nil

    -- pcall: a diagnostic that can throw is not a diagnostic.
    local ok = pcall(function() why, text = stateGate(ped) end)

    return {
        loaded       = true,
        configFound  = (Skills and Skills.Dodge) and true or false,
        enabled      = cfg and cfg.enabled or false,
        bootState    = bootState,
        loopAlive    = loopAlive,
        minLevel     = cfg and cfg.minLevel or 0,
        survival     = survivalLevel(),
        breakFall    = hasBreakFall(),
        trained      = cfg and trainedFraction() or 0.0,
        doubleTapMs  = cfg and cfg.doubleTapMs or 0,
        allowed      = ok and (why == nil),
        reason       = ok and (why or 'allowed') or 'stateGate errored',
        reasonText   = ok and (text or '-') or '-',
        lastRefusal  = lastRefusal,
        dodging      = dodging,
        anims        = resolved,
        animsProbed  = resolveDone,
        animStyle    = (cfg and cfg.animStyle) or 'roll',
        mirrorSides  = (cfg and cfg.mirrorSides) or false,
        lockHeading  = (cfg == nil) or (cfg.lockHeading ~= false),
    }
end

-- Never stuck: `dodging` is cleared on every exit path of the push thread; death

local function release()
    dodging    = false
    lastTapKey = nil
end

AddEventHandler('bs:hook:player:spawned', release)
AddEventHandler('bs:ui:panic', release)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    release()
    local ped = PlayerPedId()
    for _, anim in pairs(resolved) do
        if anim then StopAnimTask(ped, anim.dict, anim.clip, 4.0) end
    end
end)

-- For bs_zombies' claw: a dodge in progress beats a grab. True only while the roll/push is happening.
-- GrantEvade: a short window where IsDodging is also true, used by bs_fighting when a guard beats a walker swing.
local evadeUntil = 0
exports('IsDodging', function() return dodging == true or GetGameTimer() < evadeUntil end)
exports('GrantEvade', function(ms)
    ms = math.min(900, math.max(0, tonumber(ms) or 0))
    evadeUntil = math.max(evadeUntil, GetGameTimer() + ms)
end)
