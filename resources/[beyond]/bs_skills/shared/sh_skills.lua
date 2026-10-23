-- Level maths, shared so client and server agree.

Skills.Math = {}

--- XP needed to go from `level` to `level + 1`.
function Skills.Math.ToNext(treeId, level)
    local tree = Skills.Trees[treeId]
    if not tree then return math.huge end
    if level >= (tree.maxLevel or 20) then return math.huge end
    return math.floor(tree.xpPerLevel(level))
end

-- Applies XP to a { level, xp } pair, rolling levels over. Mutates and returns levels gained.
function Skills.Math.Apply(treeId, entry, amount)
    local tree = Skills.Trees[treeId]
    if not tree then return 0 end

    entry.xp = (entry.xp or 0) + math.floor(amount)
    local gained = 0

    while entry.level < (tree.maxLevel or 20) do
        local needed = Skills.Math.ToNext(treeId, entry.level)
        if entry.xp < needed then break end
        entry.xp = entry.xp - needed
        entry.level = entry.level + 1
        gained = gained + 1
    end

    if entry.level >= (tree.maxLevel or 20) then entry.xp = 0 end
    return gained
end

--- Every perk in a tree, ordered, with its unlock state resolved.
function Skills.Math.PerkList(treeId, level, owned)
    local tree = Skills.Trees[treeId]
    if not tree then return {} end

    local list = {}
    for id, perk in pairs(tree.perks or {}) do
        list[#list + 1] = {
            id          = id,
            label       = perk.label,
            description = perk.description,
            requires    = perk.requires,
            cost        = perk.cost or 1,
            order       = perk.order or 99,
            pending     = perk.pending or false,
            owned       = owned and owned[id] and true or false,
            available   = (level or 0) >= (perk.requires or 0)
                          and (not perk.needsPerk or (owned and owned[perk.needsPerk]) and true or false),
        }
    end

    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end
