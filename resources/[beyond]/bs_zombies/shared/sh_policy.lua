-- Pure rules shared by server, client and tests.
ZPolicy = {}

function ZPolicy.Finite(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

function ZPolicy.Point(x, y, z)
    return ZPolicy.Finite(x) and ZPolicy.Finite(y) and ZPolicy.Finite(z)
        and math.abs(x) <= 20000 and math.abs(y) <= 20000 and math.abs(z) <= 3000
end

-- Only unmaterialised agents wait at this boundary. Existing peds may approach.
function ZPolicy.ApproachFraction(x, y, nx, ny, players, radius)
    local fraction = 1.0
    local dx, dy = nx - x, ny - y
    local aa = dx * dx + dy * dy
    if aa < 0.000001 then return fraction end
    for _, p in ipairs(players) do
        local ox, oy = x - p.x, y - p.y
        local cc = ox * ox + oy * oy - radius * radius
        local dot = ox * dx + oy * dy
        if cc <= 0 then
            if dot < 0 then fraction = 0 end
        else
            local disc = dot * dot - aa * cc
            if disc >= 0 and dot < 0 then
                local enter = (-dot - math.sqrt(disc)) / aa
                if enter >= 0 and enter <= 1 then fraction = math.min(fraction, math.max(0, enter - 0.001)) end
            end
        end
    end
    return fraction
end

function ZPolicy.Share(cap, members, players)
    return math.max(0, math.floor(cap * members / math.max(1, players)))
end
