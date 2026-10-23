-- BeyondSurvival - bs_ui level-up: card, boom and music in one place so their timing stays in sync. The card first shows the old level, then flips.

local CFG = {
    appear     = 'level_appear.ogg',
    music      = 'level_music.ogg',

    -- How long the card holds the old number before it flips. The CSS delays its number animations by the same amount, so change both together.
    transitionAt = 380,

    -- Delay before the music comes in. LevelAppear has 5.4s of audio, so this is slightly before its middle, so the swell arrives while the boom is still going.
    musicAt      = 2400,

    appearVolume = 0.85,
    musicVolume  = 0.55,
}

local function play(file, volume)
    if GetResourceState('bs_ui') ~= 'started' then return end
    pcall(function()
        exports.bs_ui:PlaySound2D(file, { volume = volume })
    end)
end

-- Full character level-up: card, boom and music.
-- @param level number the level just reached
-- @param from number|nil the level just left
function BSLevelUpSequence(level, from)
    TriggerEvent('bs:ui:levelCard', { level = level, from = from, skill = false })

    CreateThread(function()
        Wait(CFG.transitionAt)
        play(CFG.appear, CFG.appearVolume)

        -- Not a second thread: the music is timed relative to the boom, so it is scheduled from here.
        Wait(CFG.musicAt)
        play(CFG.music, CFG.musicVolume)
    end)
end

-- Skill tree level: same card, smaller, boom only.
function BSSkillLevelSequence(level, from)
    TriggerEvent('bs:ui:levelCard', { level = level, from = from, skill = true })

    CreateThread(function()
        Wait(CFG.transitionAt)
        play(CFG.appear, CFG.appearVolume * 0.8)
    end)
end

exports('LevelUpSequence', BSLevelUpSequence)
exports('SkillLevelSequence', BSSkillLevelSequence)

-- Test commands: `/leveltest 12` plays the character sequence at level 12, `/leveltest 4 skill` plays the skill one.
RegisterCommand('leveltest', function(_, args)
    local level = math.floor(tonumber(args[1]) or 2)
    if args[2] == 'skill' then
        BSSkillLevelSequence(level, level - 1)
    else
        BSLevelUpSequence(level, level - 1)
    end
end, false)

TriggerEvent('chat:addSuggestion', '/leveltest',
    'Preview the level-up card and audio', {
        { name = 'level', help = 'the level reached' },
        { name = 'skill', help = 'add "skill" for the quieter skill version' },
    })
