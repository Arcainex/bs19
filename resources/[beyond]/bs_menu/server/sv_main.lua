-- bs_menu - one snapshot call that gathers everything the hub displays. Uses a flat summary from bs_core because the player table is a serialised copy without methods.

BSB.RegisterCallback('menu:snapshot', function(src)
    local summary = exports.bs_core:GetPlayerSummary(src)
    if not summary then return { ok = false, error = 'no character' } end

    -- Skills come from bs_skills when it is running.
    local skills, skillsReady = {}, false
    if GetResourceState('bs_skills') == 'started' then
        local ok, list = pcall(function() return exports.bs_skills:GetSkills(src) end)
        if ok and type(list) == 'table' then
            skills = list
            skillsReady = true
        end
    end

    return {
        ok = true,
        data = {
            name        = summary.name,
            class       = summary.class,
            classId     = summary.classId,
            level       = summary.level,
            xp          = summary.xp,
            xpToNext    = summary.xpToNext,
            skillPoints = summary.skillPoints,
            accounts    = summary.accounts,
            needs       = summary.needs,
            playtime    = summary.playtime,
            role        = summary.role,
            stats       = {
                carryWeight = summary.stats.carryWeight,
                maxHealth   = summary.stats.maxHealth,
                melee       = summary.stats.meleeDamageMult,
                stamina     = summary.stats.staminaMult,
            },
            skills      = skills,
            skillsReady = skillsReady,
        },
    }
end)

exports.bs_core:RegisterModule('menu', { side = 'server', version = '1.0.0' })
