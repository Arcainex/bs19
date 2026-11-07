-- ALPHA-Z: Kenney 79 / modular snap engine V17.
-- All sockets use one coordinate contract: saved positions are the lower centre
-- of the *visible bounding box* as placed by Building.Align. Nominal kit spans
-- are 3m / 1.5m; protruding trim is NOT an attachment edge.
-- Only called when at least one side is Kenney. T1-to-T1 V19 is untouched.
local K = {}
Building.KenneySnap = K

local abs, max, min, floor, cos, sin, rad = math.abs, math.max, math.min, math.floor, math.cos, math.sin, math.rad
local function rot(x, y, h)
    local a=rad(h)
    return x*cos(a)-y*sin(a), x*sin(a)+y*cos(a)
end
local function near(a,b,tol) return abs(a-b) <= (tol or 0.045) end
local function quarter(h)
    local n=floor(((h%360)+45)/90)%4
    return n
end

function K.isKenney(id)
    return type(id)=='string' and id:sub(1,5)=='bs_k_'
end

function K.family(id)
    local v=tostring(id or ''):lower()
    if v=='foundation' or v=='floor' or v=='floor_frame' or v=='ceiling' or v=='roof'
        or v:find('^bs_k_floor') or v:find('^bs_k_roof') then return 'deck' end
    if v:find('^bs_k_wall_corner') then return 'cornerwall' end
    if v=='wall' or v=='wall_window' or v=='wall_doorway' or v:find('^bs_k_wall') then return 'wall' end
    if v=='stairs' or v=='stairs_z' or v:find('^bs_k_stairs') then return 'stair' end
    if v=='support_beam' or v:find('^bs_k_column') then return 'post' end
    if v=='fence' or v:find('^bs_k_border') then return 'rail' end
    if v=='door' or v=='window' or v:find('^bs_k_door_rotate') then return 'door' end
    if v:find('^bs_k_barricade') then return 'barricade' end
    if v:find('^bs_k_plating') then return 'cladding' end
    if v=='hatch' or v:find('^bs_k_gutter') or v:find('^bs_k_detail') then return 'detail' end
    return nil
end
local function roof(id) return id=='roof' or tostring(id):find('^bs_k_roof')~=nil end
local function patch(id) return tostring(id):find('^bs_k_roof_flat_patch')~=nil end
local function corner(id) return tostring(id):find('corner',1,true)~=nil end

local function nominal(span,id)
    if not K.isKenney(id) then return span end
    -- Most Kenney corners have 0.1-0.3m decorative overhang. They still
    -- connect to a 3m or 1.5m grid; don't snap to the decorative tip.
    if corner(id) or roof(id) then
        if span>=2.94 and span<3.76 then return 3 end
        if span>=1.45 and span<1.91 then return 1.5 end
    end
    return span
end

-- The visual-bounds centre can differ from the *construction* centre (e.g.
-- -1.5..+1.8m corner rails). Remember that difference and transform it by
-- the entity heading both when reading existing parts and placing new ones.
local function trimBias(bounds, nominalSpan)
    if not bounds then return 0 end
    local a,b=tonumber(bounds[1]),tonumber(bounds[2])
    if not a or not b then return 0 end
    local span=b-a
    local excess=span-nominalSpan
    if excess<=0.035 or excess>0.60 then return 0 end
    -- If one end matches the familiar 1.5m / 0m kit-grid boundary,
    -- the extra material belongs to the other, decorative end.
    local trimMin,trimMax=0,0
    if near(a,-1.5,0.025) or near(a,0,0.025) or near(a,-0.75,0.025) then
        trimMax=excess
    elseif near(b,1.5,0.025) or near(b,0,0.025) or near(b,0.75,0.025) then
        trimMin=excess
    else
        -- Unclear trim distribution: use the symmetric geometry centre.
        return 0
    end
    local boundsMid=(a+b)*0.5
    local kitMid=(a+trimMin + b-trimMax)*0.5
    return kitMid-boundsMid
end

function K.dimensions(id)
    local def=Building.Pieces[id]
    if not def then return nil end
    local s=def.size or {3,3,3}
    local sx,sy,sz=max(.01,tonumber(s[1]) or 3),max(.01,tonumber(s[2]) or 3),max(.01,tonumber(s[3]) or 3)
    local x,y=nominal(sx,id),nominal(sy,id)
    -- The 0.30m depth of window/door wall models includes their projecting
    -- frames. Snap the structural wall centreline and its 0.15m core, exactly
    -- like bs_k_wall; keep actual visual dimensions/collisions unchanged.
    -- All 3m/6m straight wall variants share this same construction contract.
    if K.isKenney(id) and K.family(id)=='wall' then
        y=0.15
    end
    -- Rail trim is not the structural edge. Straight borders are 3m long
    -- and use a 0.15m core; corner borders use the 3m/1.5m deck grid.
    if K.isKenney(id) and K.family(id)=='rail' then
        if corner(id) then
            if sx>=2.94 and sx<3.76 then x=3 end
            if sy>=2.94 and sy<3.76 then y=3 end
            if sx>=1.45 and sx<1.91 then x=1.5 end
            if sy>=1.45 and sy<1.91 then y=1.5 end
        else
            y=0.15
        end
    end
    local bounds=def.kenneyBounds
    local biasX=K.isKenney(id) and trimBias(bounds and bounds[1],x) or 0
    local biasY=K.isKenney(id) and trimBias(bounds and bounds[2],y) or 0
    return {x=x,y=y,z=sz,family=K.family(id),roof=roof(id),corner=corner(id),
        biasX=biasX,biasY=biasY}
end

local function top(id,d)
    if id=='foundation' then return 0.32 end
    if id=='ceiling' then return 0.25 end
    return d.z
end

local function positions(parent, child)
    local diff=parent-child
    if near(diff,0) then return {0} end
    if diff < -.04 then
        return {-(-diff)*.5,(-diff)*.5}
    end
    local cells=floor(parent/child+0.001)
    if cells>=2 and cells<=12 and near(cells*child,parent) then
        local out={}
        for i=1,cells do out[#out+1]=-parent*.5+(i-.5)*child end
        return out
    end
    return {-diff*.5,diff*.5}
end

local function axisSpan(d,h,axis)
    local a=rad(h)
    local alongX=axis=='x'
    return d.x*abs(alongX and cos(a) or sin(a)) + d.y*abs(alongX and sin(a) or cos(a))
end

-- Upper/lower bounds are necessary for detecting a duplicate. A diagonal
-- or perpendicular wall junction is *not* a duplicate, even when its thin
-- bounding boxes intersect at their intended meeting point.
function K.overlaps(a,aid,b,bid)
    local da,db=K.dimensions(aid),K.dimensions(bid)
    if not da or not db then return false end
    local decks=da.family=='deck' and db.family=='deck'
    local walls=(da.family=='wall' and db.family=='wall')
    local corners=(da.family=='cornerwall' and db.family=='cornerwall')
    if not decks and not walls and not corners then return false end
    if decks and da.roof~=db.roof then return false end
    if (a.z or 0)>=(b.z or 0)+db.z-.025 or
       (b.z or 0)>=(a.z or 0)+da.z-.025 then return false end
    local ah,bh=a.h or 0,b.h or 0
    if walls and abs(cos(rad(ah-bh)))<0.985 then return false end
    if corners and abs(cos(rad(ah-bh))-1)>0.015 then return false end
    local agx,agy=rot(da.biasX,da.biasY,ah)
    local bgx,bgy=rot(db.biasX,db.biasY,bh)
    local dx=(b.x+bgx)-(a.x+agx)
    local dy=(b.y+bgy)-(a.y+agy)
    -- Two L-corners may share their bounding square in different orientations.
    -- Reject only an essentially identical pose, not a valid complementary L.
    if corners then return dx*dx+dy*dy < .01 end
    local ax,ay=cos(rad(ah)),sin(rad(ah))
    local bx,by=cos(rad(bh)),sin(rad(bh))
    local axes={{ax,ay},{-ay,ax},{bx,by},{-by,bx}}
    for _,u in ipairs(axes) do
        local gap=abs(dx*u[1]+dy*u[2])
        local ra=.5*(da.x*abs(ax*u[1]+ay*u[2])+da.y*abs(-ay*u[1]+ax*u[2]))
        local rb=.5*(db.x*abs(bx*u[1]+by*u[2])+db.y*abs(-by*u[1]+bx*u[2]))
        if gap>=ra+rb-.045 then return false end
    end
    return true
end

-- Every socket is generated as a kit-grid location in parent-local space.
-- Conversion to saved (bounding-box centred) position occurs in ONE place.
-- 'rotationOffset' is the current R/wheel angle. Both socket position and
-- returned heading are calculated together; no post-hoc heading mutation.
function K.sockets(r,requestedId,rotationOffset)
    local p,q=K.dimensions(r.p),K.dimensions(requestedId)
    if not p or not q or not p.family or not q.family then return {} end
    local out={}
    local rh=tonumber(r.h) or 0
    local rr=tonumber(rotationOffset) or 0
    local parentBX,parentBY=rot(p.biasX,p.biasY,rh)
    local parentGridX,parentGridY=r.x+parentBX,r.y+parentBY
    local rrNorm=rr%360
    local hIsQuarter=near(rrNorm,quarter(rr)*90,0.6) or near(rrNorm,360,0.6)
    local function add(x,y,z,h,tag,coverage)
        local wx,wy=rot(x,y,rh)
        local worldH=(rh+h)%360
        local bx,by=rot(q.biasX,q.biasY,worldH)
        out[#out+1]={x=parentGridX+wx-bx,y=parentGridY+wy-by,z=r.z+z,h=worldH,
            kinds={[requestedId]=true},oriented=true,tag=tag,requiresCoverage=coverage or nil}
    end
    -- Attach two *actual points* with one chosen heading. Both parent and
    -- child endpoints are in nominal footprint space, NOT their full AABBs.
    local function anchor(px,py,pz,cx,cy,heading,tag)
        local xx,yy=rot(cx,cy,heading)
        add(px-xx,py-yy,pz,heading,tag)
    end
    local function endpoints(d)
        if d.family=='cornerwall' or (d.family=='rail' and d.corner) then
            -- L: free ends of the two perpendicular 3m arms.
            return {{-d.x/2,d.y/2},{d.x/2,-d.y/2}}
        end
        return {{-d.x/2,0},{d.x/2,0}}
    end
    local function connectEnds(heading,tag)
        for _,pa in ipairs(endpoints(p)) do
            for _,ca in ipairs(endpoints(q)) do
                anchor(pa[1],pa[2],0,ca[1],ca[2],heading,tag)
            end
        end
    end

    if p.family=='deck' then
        local ztop=top(r.p,p)
        if q.family=='deck' then
            if p.roof~=q.roof then
                -- Roofs belong on wall tops, not directly on foundations.
            elseif q.roof and patch(requestedId) and not patch(r.p) then
                -- A roof patch overlays its carrier; it is NOT a full tile.
                add(0,0,ztop,rr,'Dachflicken auf Dach')
            elseif not patch(requestedId) and not patch(r.p) then
                -- Footprints are oriented BEFORE edge offsets are computed.
                -- This also works for 3x1.5, 1.5x1.5 and 3.3 trim roofs.
                if hIsQuarter then
                    local cw,ch=axisSpan(q,rr,'x'),axisSpan(q,rr,'y')
                    local z=0
                    if r.p=='foundation' and requestedId~='foundation' then z=ztop-q.z end
                    for _,shift in ipairs(positions(p.y,ch)) do
                        add((p.x+cw)/2,shift,z,rr,'Boden Ost')
                        add(-(p.x+cw)/2,shift,z,rr,'Boden West')
                    end
                    for _,shift in ipairs(positions(p.x,cw)) do
                        add(shift,(p.y+ch)/2,z,rr,'Boden Nord')
                        add(shift,-(p.y+ch)/2,z,rr,'Boden Sued')
                    end
                end
            end
        elseif q.family=='wall' or (q.family=='rail' and not q.corner) then
            -- Edge sockets: the candidate's *rotated projected thickness*
            -- determines its exact inset. R=90 therefore makes a wall run
            -- inward as a divider instead of using an impossible 0.15m inset.
            -- Oversized 6m sections only snap when all underlying bays exist.
            if not q.corner or q.family=='wall' then
                for _,edge in ipairs({
                    {nx=0,ny=1,heading=0,axis='x',tag='Nord'},
                    {nx=0,ny=-1,heading=180,axis='x',tag='Sued'},
                    {nx=1,ny=0,heading=270,axis='y',tag='Ost'},
                    {nx=-1,ny=0,heading=90,axis='y',tag='West'},
                }) do
                    if hIsQuarter then
                        local h=edge.heading+rr
                        local span=axisSpan(q,h,edge.axis)
                        local depth=axisSpan(q,h,edge.axis=='x' and 'y' or 'x')
                        local edgeLength=edge.axis=='x' and p.x or p.y
                        local insideDepth=edge.axis=='x' and p.y or p.x
                        if depth<=insideDepth+0.06 then
                            local covers=span>edgeLength+0.045
                            for _,shift in ipairs(positions(edgeLength,span)) do
                                local x=edge.nx*(p.x-depth)/2
                                local y=edge.ny*(p.y-depth)/2
                                if edge.axis=='x' then x=shift else y=shift end
                                add(x,y,ztop,h,'Wand/Gelaender '..edge.tag,covers)
                            end
                        end
                    end
                end
            end
        elseif q.family=='cornerwall' or (q.family=='rail' and q.corner) then
            if q.family=='rail' then
                -- V21.4: An L-shaped railing has two OUTER faces, not a centred
                -- 3x3 square. Align the actual visible outside corner to the
                -- deck's outside corner; this removes the 0.1-0.3m trim overhang.
                -- The stored transform uses the centre of the VISIBLE bounds.
                -- Keep Z and every non-railing socket exactly as in V21.3.
                if hIsQuarter then
                    -- Local L outer corner is (+X,+Y); rotate this with the
                    -- same world heading as the child and anchor to the deck.
                    local h=(rh+rr)%360
                    -- V21.5: V21.4 used the decorative FULL bounds as the
                    -- attachment corner. On Kenney corner rails this pulls the
                    -- structural L inward by half the trim overhang.
                    -- Align the nominal construction corner instead. The
                    -- existing trimBias conversion in add() stays intact.
                    local ox,oy=rot(q.x*.5,q.y*.5,rr)
                    local signX=ox>=0 and 1 or -1
                    local signY=oy>=0 and 1 or -1
                    local deckX=signX*p.x*.5
                    local deckY=signY*p.y*.5
                    -- add() subtracts trim bias. Supply the construction-grid
                    -- anchor offset so the visible corner ends up on the edge.
                    local bx,by=rot(q.biasX,q.biasY,h)
                    local localBX,localBY=rot(bx,by,-rh)
                    add(deckX-ox+localBX,deckY-oy+localBY,ztop,rr,
                        'Eckgelaender buendig an Deck-Aussenkante')
                end
            else
                -- Existing wall-corner behaviour remains untouched.
                if q.x<=p.x+.05 and q.y<=p.y+.05 and hIsQuarter then
                    local qw,qh=axisSpan(q,rr,'x'),axisSpan(q,rr,'y')
                    for _,x in ipairs(positions(p.x,qw)) do
                        for _,y in ipairs(positions(p.y,qh)) do
                            add(x,y,ztop,rr,'Ecke auf Bauraster')
                        end
                    end
                end
            end
        elseif q.family=='stair' then
            -- V27 / AZ comfort stair ONLY: the endpoints are physically
            -- attached to the *outer* deck edges, not the tile centre.
            -- Roof end: stair body extends OUTSIDE the upper roof footprint.
            -- Floor end: stair body extends INSIDE the lower floor footprint.
            -- Both ends are checked against actual placed decks in cl_place.
            if requestedId=='bs_k_stairs_az_straight_wide_t1' then
                -- Direction points from stair FOOT to stair HEAD; at the
                -- positive X roof edge the stair must point towards -X.
                -- Offsets 0.75m provide two 1.5m lanes in one 3m bay.
                if hIsQuarter and near(rrNorm,0,0.6) then
                    for _,edge in ipairs({
                        {axis='x',sign=1,h=180}, {axis='x',sign=-1,h=0},
                        {axis='y',sign=1,h=270}, {axis='y',sign=-1,h=90},
                    }) do
                        local length=(edge.axis=='x') and p.y or p.x
                        for _,along in ipairs(positions(length,q.y)) do
                            local px,py
                            if edge.axis=='x' then
                                px=edge.sign*p.x*.5; py=along
                            else
                                px=along; py=edge.sign*p.y*.5
                            end
                            local h=edge.h
                            if p.roof then
                                -- The 1m LANDING finishes at this roof edge.
                                -- q.z = the true floor-to-roof SURFACE rise.
                                anchor(px,py,ztop-q.z,q.x*.5,0,h,
                                    'AZ V27: Podest buendig an Roof-Aussenkante')
                            else
                                -- On a lower deck the FOOT is at its outer
                                -- edge. The upper end must touch an actual roof.
                                anchor(px,py,ztop,-q.x*.5,0,h,
                                    'AZ V27: Fuss buendig an Bodenaussenkante')
                            end
                        end
                    end
                end
            else
                -- Existing Kenney stairs are NOT modified.
                for _,edge in ipairs({
                    {x=p.x/2,y=0,h=0},{x=-p.x/2,y=0,h=180},
                    {x=0,y=p.y/2,h=90},{x=0,y=-p.y/2,h=270},
                }) do
                    local h=edge.h+rr
                    anchor(edge.x,edge.y,ztop,-q.x/2,0,h,'Treppe Fuss')
                    anchor(edge.x,edge.y,ztop-q.z,q.x/2,0,h,'Treppe Kopf')
                end
            end -- original Kenney stairs
        elseif q.family=='post' then
            for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do
                add(sx*(p.x-q.x)/2,sy*(p.y-q.y)/2,ztop,rr,'Stuetzpfosten Ecke')
            end end
        elseif q.family=='barricade' or q.family=='cladding' or q.family=='detail' then
            add(0,0,ztop,rr,'Zubehoer auf Boden')
        end

    elseif p.family=='wall' or p.family=='cornerwall' then
        if q.family=='wall' or q.family=='cornerwall' or q.family=='rail' then
            -- Straight, L-corner and mixed length joins share exactly the
            -- same endpoint maths. 1.5m walls no longer jump 0.75m in a join.
            if hIsQuarter then
                if p.family=='cornerwall' and q.family=='wall' then
                    -- An L corner has two differently oriented free arms.
                    -- A straight wall must continue along the arm's tangent,
                    -- not use the same heading for both corner endpoints.
                    local cornerEnds = endpoints(p)
                    local wallEnds = endpoints(q)
                    for i, pa in ipairs(cornerEnds) do
                        local armHeading = (i==1) and 90 or 0
                        local childHeading = (armHeading+rr)%360
                        for _, ca in ipairs(wallEnds) do
                            anchor(pa[1],pa[2],0,ca[1],ca[2],childHeading,
                                'Wand an L-Ecke Arm '..i)
                        end
                    end
                else
                    connectEnds(rr,'Wandenden verbunden')
                end
            end
            if (q.family=='wall' or q.family=='cornerwall') and hIsQuarter and quarter(rr)%2==0 then
                -- Stack half-length pieces aligned within their actual bay.
                if p.family=='wall' and q.family=='wall' then
                    for _,shift in ipairs(positions(p.x,q.x)) do
                        add(shift,0,p.z,rr,'Wand ueber Wand')
                    end
                end
            end
        elseif q.family=='deck' then
            if not patch(requestedId) and hIsQuarter then
                local cw=axisSpan(q,rr,'x')
                local cd=axisSpan(q,rr,'y')
                local toInside=(cd-p.y)/2
                for _,along in ipairs(positions(p.x,cw)) do
                    add(along,-toInside,p.z,rr,'Decke innen')
                    add(along,toInside+p.y,p.z,rr,'Decke aussen')
                end
            end
        elseif q.family=='door' then
            if tostring(r.p):find('doorway',1,true) or r.p=='wall_doorway' then
                add(0,0,0,rr,'Tuer im Durchgang')
            elseif requestedId=='window' and (tostring(r.p):find('window',1,true)) then
                add(0,0,0.90,rr,'Fenster im Rahmen')
            end
        elseif q.family=='barricade' or q.family=='cladding' or q.family=='detail' then
            local height=max(0,(p.z-q.z)*.5)
            if q.family=='cladding' then height=min(height,.6) end
            if q.family=='detail' and q.z>p.z*.7 then height=0 end
            local matchingOpening=q.family=='barricade' and
                ((tostring(r.p):find('doorway',1,true) and tostring(requestedId):find('doorway',1,true)) or
                 (tostring(r.p):find('window',1,true) and tostring(requestedId):find('window',1,true)))
            if matchingOpening then
                -- A barricade spans the opening around its centre. It must
                -- NEVER be shifted +/-0.558m as though it were a half wall.
                add(0,0,height,rr,'Barrikade mittig im Durchgang')
            else
                for _,along in ipairs(positions(p.x,q.x)) do
                    add(along,0,height,rr,'An Wand montieren')
                end
            end
        elseif q.family=='post' then
            add((p.x-q.x)/2,0,0,rr,'Pfosten rechts')
            add(-(p.x-q.x)/2,0,0,rr,'Pfosten links')
        end

    elseif p.family=='stair' then
        if q.family=='deck' then
            if not patch(requestedId) then
                local cw=axisSpan(q,rr,'x')
                add(-(p.x+cw)/2,0,0,rr,'Treppenfuss-Boden')
                add((p.x+cw)/2,0,p.z,rr,'Treppenkopf-Boden')
            end
        elseif q.family=='stair' then
            if hIsQuarter then
                anchor(p.x/2,0,p.z,-q.x/2,0,rr,'Treppenlaeufe oben')
                anchor(-p.x/2,0,-q.z,q.x/2,0,rr,'Treppenlaeufe unten')
            end
        elseif q.family=='wall' or q.family=='rail' then
            -- Stairs are ~1.95m / 2.25m wide but the base uses a 3m bay.
            -- Side walls/rails belong at the OUTER 3m grid boundary.
            if hIsQuarter then
                local bay=max(3,math.ceil((p.y-.03)/3)*3)
                local side=(bay-q.y)/2
                for _,along in ipairs(positions(p.x,q.x)) do
                    add(along,side,0,rr,'Treppenseite Nord')
                    add(along,-side,0,180+rr,'Treppenseite Sued')
                end
                anchor(p.x/2,0,0,-q.x/2,0,90+rr,'Treppen-Endwand rechts')
                anchor(-p.x/2,0,0,q.x/2,0,270+rr,'Treppen-Endwand links')
            end
        end

    elseif p.family=='rail' then
        if q.family=='rail' or q.family=='wall' then
            if hIsQuarter then
                if p.corner and not q.corner then
                    -- Corner rails are L-shaped. Each free arm has its own
                    -- tangent, as for the already-tested wall-corner V19 fix.
                    for i,pa in ipairs(endpoints(p)) do
                        local heading=((i==1) and 90 or 0)+rr
                        for _,ca in ipairs(endpoints(q)) do
                            anchor(pa[1],pa[2],0,ca[1],ca[2],heading,
                                'Gelaender an Eckarm '..i)
                        end
                    end
                else
                    connectEnds(rr,'Gelaenderende')
                end
            end
        end
    elseif p.family=='post' then
        if q.family=='wall' or q.family=='rail' then
            if hIsQuarter then
                anchor(0,0,0,-q.x/2,0,rr,'Wand an Pfosten')
                anchor(0,0,0,q.x/2,0,rr,'Wand an Pfosten')
            end
        elseif q.family=='post' then
            add(0,0,p.z,rr,'Pfosten auf Pfosten')
        end
    end
    return out
end

-- V27: Reject ghost sockets that cannot meet BOTH real deck surfaces.
-- This prevents a roof-only attachment from leaving the foot floating and
-- prevents a floor-only attachment from driving the landing through a wall.
function K.azStairSupported(socket, pieces)
    if not socket or not pieces then return false end
    local id='bs_k_stairs_az_straight_wide_t1'
    local d=K.dimensions(id)
    if not d then return false end
    local heading=socket.h or 0
    local fx,fy=rot(-d.x*.5,0,heading)
    local tx,ty=rot(d.x*.5,0,heading)
    local footX,footY=socket.x+fx,socket.y+fy
    local headX,headY=socket.x+tx,socket.y+ty
    local footZ,headZ=socket.z,socket.z+d.z
    local footOK,headOK=false,false
    for _,deck in pairs(pieces) do
        local b=K.dimensions(deck.p)
        if b and b.family=='deck' and not patch(deck.p) then
            local gridX,gridY=rot(b.biasX,b.biasY,deck.h or 0)
            local cx,cy=deck.x+gridX,deck.y+gridY
            local function onSurface(x,y,z)
                if abs(z - ((deck.z or 0)+top(deck.p,b)))>0.085 then return false end
                local lx,ly=rot(x-cx,y-cy,-(deck.h or 0))
                return abs(lx)<=b.x*.5+0.10 and abs(ly)<=b.y*.5+0.10
            end
            if b.roof then
                if not headOK and onSurface(headX,headY,headZ) then headOK=true end
            else
                if not footOK and onSurface(footX,footY,footZ) then footOK=true end
            end
            if footOK and headOK then return true end
        end
    end
    return false
end

-- Wide 6m walls require a supporting deck at BOTH ends, not just the one 3m
-- tile that happened to provide the socket. Supports mixed half/full tiles and roofs.
function K.covered(socket, requestedId, pieces)
    if not socket.requiresCoverage then return true end
    local q=K.dimensions(requestedId)
    if not q or (q.family~='wall' and q.family~='rail') then return false end
    local x,y=socket.x,socket.y
    local bx,by=rot(q.biasX,q.biasY,socket.h or 0)
    x,y=x+bx,y+by
    local ux,uy=rot(1,0,socket.h or 0)
    for _,sign in ipairs({-1,1}) do
        local px=x+sign*ux*(q.x*.5-.16)
        local py=y+sign*uy*(q.x*.5-.16)
        local supported=false
        for _,deck in pairs(pieces or {}) do
            local d=K.dimensions(deck.p)
            if d and d.family=='deck' then
                if abs((deck.z+top(deck.p,d))-socket.z)<.07 then
                    local ox,oy=rot(d.biasX,d.biasY,deck.h or 0)
                    local localX,localY=rot(px-(deck.x+ox),py-(deck.y+oy),-(deck.h or 0))
                    if abs(localX)<=d.x*.5+.07 and abs(localY)<=d.y*.5+.07 then
                        supported=true; break
                    end
                end
            end
        end
        if not supported then return false end
    end
    return true
end
