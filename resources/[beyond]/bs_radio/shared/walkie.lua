Walkie = {
    directRange = 450.0, portableLife = 3600, portableRange = 900.0,
    tiers = {
        {item='radio',label='Field radio',hops=2,effect=1},
        {item='radio_advanced',label='Expedition radio',hops=4,effect=2},
        {item='radio_military',label='Military radio',hops=999,effect=3}
    },
    antennas = {
        {id='sandy',label='Sandy Shores relay',x=1692.7,y=2533.5,z=60.5,range=4500.0,linkRange=9000.0,enabled=true},
        {id='chiliad',label='Mount Chiliad relay',x=451.0,y=5566.0,z=794.0,range=6500.0,linkRange=14000.0,enabled=true},
        {id='city',label='Los Santos relay',x=735.7,y=132.4,z=80.7,range=4500.0,linkRange=9000.0,enabled=true}
    }
}
WalkieGraph = {}
function WalkieGraph.distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
function WalkieGraph.connected(a,b,nodes,hops,bucket)
    if WalkieGraph.distance(a,b)<=Walkie.directRange then return true end
    local queue, seen = {}, {}
    for i,node in ipairs(nodes) do
        if node.enabled and (not node.bucket or node.bucket==bucket) and not node.disrupted and WalkieGraph.distance(a,node)<=node.range then queue[#queue+1]={i,0};seen[i]=true end
    end
    local head=1
    while head<=#queue do
        local entry=queue[head];head=head+1
        local node=nodes[entry[1]]
        if WalkieGraph.distance(b,node)<=node.range then return true end
        if entry[2]<hops then
            for i,nextNode in ipairs(nodes) do
                if not seen[i] and nextNode.enabled and not nextNode.disrupted and (not nextNode.bucket or nextNode.bucket==bucket) and WalkieGraph.distance(node,nextNode)<=math.min(node.linkRange,nextNode.linkRange) then
                    seen[i]=true;queue[#queue+1]={i,entry[2]+1}
                end
            end
        end
    end
    return false
end
