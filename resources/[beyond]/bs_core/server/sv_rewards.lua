-- One entry point for rewards: exports.bs_core:AwardAction(src, 'zombie_kill_headshot'). Pays XP and money from Config.Rewards and forwards the skill part to bs_skills when running.

--- @param src number
--- @param actionId string   key in Config.Rewards
--- @param multiplier number|nil  scales the whole reward (zone difficulty, perks)
--- @return table|nil  what was actually awarded
function BS.AwardAction(src, actionId, multiplier)
    local player = BS.GetPlayer(src)
    if not player then return nil end

    local reward = Config.Rewards[actionId]
    if not reward then
        BS.Log.warn('rewards', ('unknown action "%s"'):format(tostring(actionId)))
        return nil
    end

    multiplier = tonumber(multiplier) or 1.0

    -- Perks can raise what an action pays. bs_skills owns that calculation;
    -- if it is not running the base value stands.
    if GetResourceState('bs_skills') == 'started' then
        local ok, bonus = pcall(function()
            return exports.bs_skills:RewardMultiplier(src, actionId)
        end)
        if ok and type(bonus) == 'number' then multiplier = multiplier * bonus end
    end

    -- Power station buff (bs_operations): extra XP while the faction holds it.
    -- Asked from the server, the player statebag can be written by the client.
    local xpMult = 1.0
    if GetResourceState('bs_operations') == 'started' then
        local ok, pct = pcall(function() return exports.bs_operations:XpBuffPct(src) end)
        if ok and tonumber(pct) then xpMult = 1.0 + math.max(0, math.min(100, tonumber(pct))) / 100 end
    end

    local xp    = math.floor((reward.xp or 0) * multiplier * xpMult)
    local money = math.floor((reward.money or 0) * multiplier)

    if xp > 0 then player:AddXP(xp, actionId) end
    if money > 0 then player:AddMoney('cash', money, actionId) end

    if reward.skill and reward.skillXp and GetResourceState('bs_skills') == 'started' then
        pcall(function()
            exports.bs_skills:AddSkillXP(src, reward.skill, math.floor(reward.skillXp * multiplier))
        end)
    end

    BS.Emit('player:action', player, actionId, { xp = xp, money = money })
    return { xp = xp, money = money, skill = reward.skill }
end

exports('AwardAction', BS.AwardAction)

--- Bulk version for things that happen in batches (a horde wipe).
exports('AwardActionTimes', function(src, actionId, times)
    times = math.max(1, math.floor(tonumber(times) or 1))
    local total = { xp = 0, money = 0 }
    for _ = 1, times do
        local r = BS.AwardAction(src, actionId)
        if r then total.xp = total.xp + r.xp; total.money = total.money + r.money end
    end
    return total
end)
