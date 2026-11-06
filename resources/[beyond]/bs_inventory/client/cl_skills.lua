local function list()
    if GetResourceState('bs_skills') ~= 'started' then return { ok = false, error = 'Skills are unavailable.' } end
    return BSB.Await('skills:list', 8000) or { ok = false, error = 'Skills request timed out.' }
end

RegisterNUICallback('skillsList', function(_, cb)
    CreateThread(function() cb(list()) end)
end)

for nui, callback in pairs({ skillsUnlock = 'skills:unlock', skillsTrain = 'skills:train', skillsRespec = 'skills:respec' }) do
    local name = callback
    RegisterNUICallback(nui, function(data, cb)
        CreateThread(function()
            if GetResourceState('bs_skills') ~= 'started' then cb({ ok = false, error = 'Skills are unavailable.' }); return end
            local result = BSB.Await(name, 8000, data.tree, data.perk)
            if result and result.ok and data.sound ~= false and GetResourceState('bs_ui') == 'started' then
                pcall(function() exports.bs_ui:PlaySound2D('level_appear.ogg', { volume = 0.12, id = 'inventory-skill-confirm' }) end)
            end
            cb(result or { ok = false, error = 'Request timed out. Check your points before trying again.' })
        end)
    end)
end

AddEventHandler('bs:skills:changed', function()
    if not exports.bs_inventory:IsOpen() then return end
    local effects = exports.bs_skills:GetEffects()
    local ok, character = pcall(function() return exports.bs_core:GetData() end)
    if ok and character and character.class and character.class.stats then
        local carry = character.class.stats.carryWeight
        if carry then effects.carryWeight = carry - 40.0 end
    end
    SendNUIMessage({ action = 'skillsChanged', levels = exports.bs_skills:GetLevels(), effects = effects, trees = exports.bs_skills:GetTrees() })
end)
