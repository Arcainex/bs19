-- bs_skills - /skilltest: prints why a skill did or did not work (character level vs tree level, refusal reasons, dodge clips, sway).

-- Output uses print() so it can be copied from F8. Colour codes (^1 red, ^2 green, ^3 yellow, ^7 reset) only mark failing lines; the text never depends on colour.

local function line(text) print('^7[skilltest] ' .. tostring(text)) end

local function flag(label, value, goodWhenTrue)
    local good = (goodWhenTrue ~= false) and value or not value
    line(('%s %-22s %s'):format(good and '^2 OK ^7' or '^1FAIL^7', label, tostring(value)))
end

local function head(text)
    print('^7[skilltest] ------------------------------------------------------------')
    print('^7[skilltest] ' .. text)
end

-- Trees are read through the resource's own export, the same numbers other resources see.

local TREES = { 'combat', 'survival', 'crafting', 'medical' }

local function reportTrees()
    head('SKILL TREE LEVELS  (these are TREE levels, not your character level)')

    local ok, levels = pcall(function() return exports.bs_skills:GetLevels() end)
    if not ok or type(levels) ~= 'table' then
        line('^1GetLevels() failed - cl_main.lua is not exporting, or the resource is not started.^7')
        return
    end

    local any = false
    for _, id in ipairs(TREES) do
        local lvl = levels[id]
        if lvl then any = true end
        line(('  %-10s %s'):format(id, tostring(lvl or 0)))
    end

    -- Character level and tree level look alike but are different, so this is spelled out.
    if not any then
        line('^3  All trees are 0 or absent. That is normal for a character who has not^7')
        line('^3  earned skill XP or spent points on training - and it is NOT the same as^7')
        line('^3  your CHARACTER level. If the server has not sent bs:skills:sync yet this^7')
        line('^3  is also what you would see; relog once before reporting it.^7')
    end
end

--------------------------------------------------------------------------------
-- Dodge
--------------------------------------------------------------------------------

local function reportDodge()
    head('DODGE  (cl_dodge.lua)')

    if type(BS_SkillsDebug) ~= 'table' or type(BS_SkillsDebug.dodge) ~= 'function' then
        line('^1FAIL  cl_dodge.lua DID NOT FINISH LOADING.^7')
        line('  It is missing from fxmanifest.lua client_scripts, it errored while')
        line('  loading (check the console from resource start), or Skills.Dodge was nil')
        line('  and it returned early. Nothing below this point can be reported.')
        return
    end

    local d = BS_SkillsDebug.dodge()

    flag('file loaded',      d.loaded)
    flag('config found',     d.configFound)
    flag('enabled',          d.enabled)
    flag('input loop alive', d.loopAlive)
    line(('      boot state           %s'):format(d.bootState))
    line(('      gesture              SHIFT + double-tap W/S/A/D within %dms'):format(d.doubleTapMs or 0))
    line(('      survival level       %d   (minLevel required: %d)'):format(d.survival or 0, d.minLevel or 0))
    line(('      break_fall perk      %s'):format(tostring(d.breakFall)))
    line(('      trained fraction     %.2f  (0 = untrained, 1 = capped)'):format(d.trained or 0.0))
    line(('      currently dodging    %s'):format(tostring(d.dodging)))

    -- Print the refusal reason itself, the same sentence the game would show.
    if d.allowed then
        line('^2 OK ^7 DODGE IS ALLOWED RIGHT NOW. Hold SHIFT and tap a direction twice.')
    else
        line(('^1FAIL^7 DODGE IS REFUSED RIGHT NOW: %s'):format(tostring(d.reason)))
        line(('      player would be told: "%s"'):format(tostring(d.reasonText)))
        line('      (some refusals are position-dependent: run this again standing still,')
        line('       on foot, on the ground, not aiming, and see if it changes)')
    end

    line(('      last refusal         %s'):format(tostring(d.lastRefusal)))

    head('DODGE ANIMATIONS  (probed with GetAnimDuration - the only honest test)')
    if not d.animsProbed then
        line('^3  Not probed yet. The probe runs a couple of seconds after spawn; if this^7')
        line('^3  still says false a minute in, the boot state above says where it stuck.^7')
    end
    for _, dir in ipairs({ 'forward', 'backward', 'left', 'right' }) do
        local a = (d.anims or {})[dir]
        if type(a) == 'table' then
            -- Print the clip style and flag, not just the names, so it is clear which tier resolved (e.g. 'roll, flag 32' vs 'upper, flag 48').
            line(('  %-9s %s / %s   [%s, flag %d]')
                :format(dir, a.dict, a.clip, tostring(a.style or 'roll'), a.flag or 48))
        else
            -- Not a failure. The push uses SetEntityVelocity and runs even if no clip resolved; it just looks like a fast step.
            line(('  %-9s no clip - the dodge STILL MOVES; a fast step, which is the intended floor'):format(dir))
        end
    end

    -- The config settings that change the output above, echoed so a pasted result is self-explanatory.
    line(('      animStyle            %s'):format(tostring(d.animStyle)))
    line(('      mirrorSides          %s   (set true in config if left/right roll the wrong way)')
        :format(tostring(d.mirrorSides)))
    line(('      lockHeading          %s'):format(tostring(d.lockHeading)))

    -- Warn when all four clips are identical: every real candidate failed the probe and the fallback caught them all.
    local first = (d.anims or {}).forward
    local same  = type(first) == 'table'
    if same then
        for _, dir in ipairs({ 'backward', 'left', 'right' }) do
            local a = (d.anims or {})[dir]
            if type(a) ~= 'table' or a.dict ~= first.dict or a.clip ~= first.clip then
                same = false
                break
            end
        end
    end
    if same then
        line('^1  WARNING: all four directions resolved to the SAME clip.^7')
        line('^1  That is the round-one bug exactly: a sideways dodge will be playing a^7')
        line('^1  clip authored for another direction. Check the clip names in cl_dodge.lua^7')
        line('^1  against a game-file dump before trusting anything above.^7')
    end
end

--------------------------------------------------------------------------------
-- Sway
--------------------------------------------------------------------------------

local function reportSway()
    head('SWAY  (cl_sway.lua)')

    if type(BS_SkillsDebug) ~= 'table' or type(BS_SkillsDebug.sway) ~= 'function' then
        line('^1FAIL  cl_sway.lua DID NOT FINISH LOADING.^7')
        line('  Same three causes as the dodge above: not in fxmanifest.lua, errored on')
        line('  load, or Skills.Sway was nil and it returned early.')
        return
    end

    local w = BS_SkillsDebug.sway()

    flag('file loaded',   w.loaded)
    flag('config found',  w.configFound)
    flag('enabled',       w.enabled)
    flag('loop alive',    w.loopAlive)
    line(('      boot state           %s'):format(w.bootState))
    line(('      mode                 %s   (aim / crosshair / both)'):format(tostring(w.mode)))
    line(('      %-8s level       %d   (sway reaches exactly 0 at %d)')
        :format(tostring(w.tree), w.level or 0, w.zeroAt or 20))
    line(('      steady_hands perk    %s'):format(tostring(w.steadyHands)))
    line(('      camera view          %s'):format(w.firstPerson and 'FIRST PERSON' or 'third person'))
    line(('      free aiming          %s'):format(tostring(w.freeAiming)))
    line(('      weapon hash          %s   firearm: %s'):format(tostring(w.weaponHash), tostring(w.isFirearm)))

    if w.active then
        line('^2 OK ^7 SWAY IS ACTIVE RIGHT NOW.')
    else
        line(('^3 -- ^7 sway is NOT active right now: %s'):format(tostring(w.reason)))
        line('      Run this again WHILE HOLDING RIGHT MOUSE with a gun out - most of')
        line('      the numbers below are only meaningful in that state.')
    end

    -- Amplitude in both units: degrees (what the aim does) and screen fraction (what the reticle does).
    line(('      loop last saw        active=%s (%s)'):format(tostring(w.loopActive), tostring(w.loopReason)))
    line(('      skill factor         %.3f  (1.0 = worst, 0.0 = perfectly steady)'):format(w.baseFactor or 0.0))
    line(('      situational mult     %.3f  (moving / crouched / winded)'):format(w.situational or 1.0))
    line(('      COMPUTED AMPLITUDE   %.3f degrees of aim error'):format(w.degrees or 0.0))
    line(('                           %.4f of screen height on the reticle'):format(w.screenFrac or 0.0))

    if (w.degrees or 0.0) <= 0.0 and w.active then
        line('^3      Amplitude is zero: you are at or past the level where sway clears.^7')
    end

    if w.mode == 'aim' then
        line('^3      NOTE: mode is "aim", which draws NOTHING on screen. If you want to^7')
        line('^3      SEE it, set Skills.Sway.mode = "both" in config_abilities.lua.^7')
    end
end

-- The command is registered with a chat suggestion.

RegisterCommand('skilltest', function()
    print('^7[skilltest] ============================================================')
    print('^7[skilltest] BeyondSurvival bs_skills self-test')
    print(('^7[skilltest] resource state: %s   game time: %d')
        :format(GetResourceState('bs_skills'), GetGameTimer()))

    -- Each section is wrapped in pcall so one failing native does not hide the rest.
    for _, fn in ipairs({ reportTrees, reportDodge, reportSway }) do
        local ok, err = pcall(fn)
        if not ok then line('^1section errored: ' .. tostring(err) .. '^7') end
    end

    print('^7[skilltest] ============================================================')
    print('^7[skilltest] Select all of the above and paste it back when reporting.')

    pcall(function()
        TriggerEvent('bs:ui:notify', {
            type = 'info',
            message = 'Skill self-test printed to the F8 console.',
            duration = 4000,
        })
    end)
end, false)

TriggerEvent('chat:addSuggestion', '/skilltest',
    'Print why the dodge and the weapon sway are or are not working right now.')

print('^2[BeyondSurvival]^7 (skills) cl_skilldebug.lua loaded - type /skilltest in game.')
