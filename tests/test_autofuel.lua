require("class")
FUELTYPE = { BURNABLE = "BURNABLE", CHEMICAL = "CHEMICAL", NIGHTMARE = "NIGHTMARE", USAGE = "USAGE" }
TUNING = { WET_FUEL_PENALTY = 0.75 }
math.clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local Fueled = require("components/fueled") -- Real DST acceptance, value, delta, callbacks.
local Trader = require("components/trader") -- Real gift consumption and rejection.
local Auto = require("nearby_autofuel")
local guid, entities, passed = 0, {}, 0
local config
local function check(v, message) assert(v, message or "check failed") end
local function equal(a, b) assert(a == b, tostring(a).." ~= "..tostring(b)) end
local function entity(prefab, x, tags)
    guid = guid + 1
    local e = { prefab = prefab, GUID = guid, components = {}, tags = tags or {}, x = x or 0, z = 0 }
    function e:IsValid() return not self.removed end
    function e:Remove() self.removed = true end
    function e:AddTag(t) self.tags[t] = true end
    function e:RemoveTag(t) self.tags[t] = nil end
    function e:HasTag(t) return self.tags[t] == true end
    function e:PushEvent(t, data) self.last_event = t end
    function e:GetIsWet() return self.wet == true end
    function e:GetDistanceSqToInst(other) return (self.x-other.x)^2 + (self.z-other.z)^2 end
    function e:GetPosition()
        local x,z = self.x,self.z
        return {Get=function() return x,0,z end}
    end
    e.Transform = {
        GetWorldPosition=function() return e.x,0,e.z end,
        SetPosition=function(_,x,y,z) e.x,e.z=x,z end,
    }
    e.entity = {GetParent=function() return e.parent end}
    function e:DoPeriodicTask() return {Cancel=function() end} end
    entities[#entities+1] = e
    return e
end
local item
item = function(name, value, count, kind, x)
    local e = entity(name, x, {_inventoryitem=true})
    e.components.inventoryitem = {
        OnDropped=function() e.dropped=true end,
        RemoveFromOwner=function() return e end,
    }
    if value ~= nil then
        e.components.fuel = {fueltype=kind or FUELTYPE.BURNABLE, fuelvalue=value,
            Taken=function() e.taken=true end}
    end
    if count then
        e.components.stackable = {stacksize=count}
        function e.components.stackable:Get(n)
            if self.stacksize <= n then return e end
            self.stacksize = self.stacksize - n
            local one = item(name,value,n,kind,e.x)
            one.wet = e.wet
            if e.tags.gem then one.tags.gem=true end
            return one
        end
        function e.components.stackable:CanStackWith(other) return other.prefab == e.prefab end
        function e.components.stackable:Put(other)
            self.stacksize = self.stacksize + other.components.stackable.stacksize
            other:Remove()
        end
    end
    return e
end
local function target(current, maximum, prefab)
    local e = entity(prefab or "firepit", 0, {structure=true})
    e.components.fueled = Fueled(e)
    local f=e.components.fueled
    f.maxfuel, f.currentfuel, f.accepting = maximum or 100, current or 0, true
    return e
end
local function chest(x, slots)
    local e=entity("treasurechest",x,{structure=true})
    local c={inst=e, type="chest",slots=slots,canbeopened=true}
    e.components.container=c
    for _,v in pairs(slots) do v.components.inventoryitem.owner=e end
    function c:GetNumSlots() return 9 end
    function c:GetItemInSlot(i) return self.slots[i] end
    function c:RemoveItem(v, whole)
        equal(whole,false)
        if self.readonlycontainer then return nil end
        local one=v.components.stackable and v.components.stackable:Get(1) or v
        if one==v then
            for slot,entry in pairs(self.slots) do if entry==v then self.slots[slot]=nil end end
        end
        one.components.inventoryitem.owner=nil
        if self.onremove then self.onremove() end
        return one
    end
    function c:GiveItem(v, slot)
        if self.slots[slot] then self.slots[slot].components.stackable:Put(v)
        else self.slots[slot]=v;v.components.inventoryitem.owner=e end
        return true
    end
    return e
end
TheSim={FindEntities=function(_,x,y,z,r,must,exclude,oneof)
    local found={}
    for _,e in ipairs(entities) do
        local ok=e:IsValid() and (e.x-x)^2+(e.z-z)^2<=r*r
        for _,t in ipairs(exclude) do if e:HasTag(t) then ok=false end end
        local any=false
        for _,t in ipairs(oneof) do if e:HasTag(t) then any=true end end
        if ok and any then found[#found+1]=e end
    end
    return found
end}
local function test(name, fn)
    entities={}
    config={radius=8,threshold=1,ground=true,empty=true}
    fn()
    passed=passed+1
    print("PASS "..name)
end
test("skip nonfuel and holes, preserve numeric order, take one",function()
    local t=target(10)
    local a,b=item("log",20,3),item("twigs",10,3)
    chest(2,{[1]=item("rocks"),[3]=a,[4]=b})
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,30)
    equal(a.components.stackable.stacksize,2);equal(b.components.stackable.stacksize,3)
end)
test("incompatible fuel skipped",function()
    local t=target(0);local n=item("nightmarefuel",30,2,FUELTYPE.NIGHTMARE)
    chest(1,{n,item("log",20,2)})
    check(Auto.Tick(t,config));equal(n.components.stackable.stacksize,2)
end)
test("strict priority waits instead of using later slot or ground",function()
    local t=target(80);local a=item("log",30,2)
    chest(1,{a,item("twigs",10,2)});local ground=item("grass",5,2,nil,0)
    check(not Auto.Tick(t,config));equal(a.components.stackable.stacksize,2)
    equal(ground.components.stackable.stacksize,2);equal(t.components.fueled.currentfuel,80)
end)
test("oversized fuel skips to next usable item",function()
    local t=target(10);chest(1,{item("huge",101,2),item("log",20,2)})
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,30)
end)
test("chest before closer ground",function()
    local t=target(0);local g=item("grass",10,2,nil,0)
    chest(7,{item("log",20,2)})
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,20);equal(g.components.stackable.stacksize,2)
end)
test("nearer chest wins independent of discovery order",function()
    local t=target(0);chest(7,{item("log",20,2)});chest(2,{item("twigs",10,2)})
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,10)
end)
test("equal distance uses stable GUID order",function()
    local t=target(0);chest(-2,{item("log",20,2)});chest(2,{item("twigs",10,2)})
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,20)
end)
test("nearest ground stack consumes exactly one",function()
    local t=target(0);item("log",20,2,nil,6);local g=item("grass",10,4,nil,1)
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,10);equal(g.components.stackable.stacksize,3)
end)
test("last unstacked item removed",function()
    local t=target(0);local g=item("log",20,nil,nil,1)
    check(Auto.Tick(t,config));check(g.removed);check(g.taken)
end)
test("ground disabled",function()
    local t=target(0);item("log",20,2,nil,1);config.ground=false
    check(not Auto.Tick(t,config))
end)
test("range limit",function()
    local t=target(0);chest(8.01,{item("log",20,2)})
    check(not Auto.Tick(t,config))
end)
test("player inventory and parented items excluded",function()
    local t=target(0);local g=item("log",20,2,nil,1)
    g.components.inventoryitem.owner={};local h=item("grass",10,2,nil,1);h.parent={}
    check(not Auto.Tick(t,config))
end)
test("full or above threshold does not consume",function()
    local t=target(100);local g=item("log",20,2,nil,1)
    check(not Auto.Tick(t,config));t.components.fueled.currentfuel=51;config.threshold=.5
    check(not Auto.Tick(t,config));equal(g.components.stackable.stacksize,2)
end)
test("exact threshold and exact capacity accepted",function()
    local t=target(50);item("log",50,2,nil,1);config.threshold=.5
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,100)
end)
test("wet penalty and both multipliers agree with vanilla",function()
    local t=target(10);t.components.fueled.bonusmult=2;t.components.fueled.multfn=function() return 3 end
    local g=item("log",20,3,nil,1);g.wet=true
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,100);equal(g.components.stackable.stacksize,2)
end)
test("wet chest stack uses single item moisture",function()
    local t=target(10);local g=item("log",40,3);g.wet=true;chest(1,{g})
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,40)
end)
test("secondary fuel accepted",function()
    local t=target(10);t.components.fueled.secondaryfueltype=FUELTYPE.CHEMICAL
    item("nitre",30,2,FUELTYPE.CHEMICAL,1)
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,40)
end)
test("custom rejection skipped without invoking consumption",function()
    local t=target(0);t.components.fueled.cantakefuelitemfn=function(_,it,doer) equal(doer,nil);return it.prefab~="log" end
    chest(1,{item("log",20,2),item("grass",10,2)})
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,10)
end)
test("post removal capacity change restores chest stack",function()
    local t=target(0);local g=item("log",20,4);local c=chest(1,{g})
    c.components.container.onremove=function() t.components.fueled.currentfuel=99 end
    check(not Auto.Tick(t,config));equal(g.components.stackable.stacksize,4)
end)
test("take refusal restores ground stack",function()
    local t=target(0);local g=item("log",20,4,nil,1)
    t.components.fueled.TakeFuelItem=function() return false end
    check(not Auto.Tick(t,config));equal(g.components.stackable.stacksize,4)
end)
test("two buildings share stack without double spending",function()
    local a,b=target(0),target(0);local g=item("log",20,1,nil,1)
    check(Auto.Tick(a,config));check(not Auto.Tick(b,config));check(g.removed)
end)
test("empty disabled and no accepting disabled",function()
    local t=target(0);item("log",20,2,nil,1);config.empty=false
    check(not Auto.Tick(t,config));config.empty=true;t.components.fueled.accepting=false
    check(not Auto.Tick(t,config))
end)
test("portable fuel equipment excluded",function()
    local t=target(0,100);t.components.inventoryitem={}
    check(not Auto.IsTarget(t))
end)
test("campfire without structure tag supported",function()
    local t=target(0);t.tags.structure=nil;t.tags.campfire=true
    item("log",20,2,nil,1);check(Auto.Tick(t,config))
end)
test("readonly and burnt storage skipped",function()
    local t=target(0);local c=chest(1,{item("log",20,2)});c.components.container.readonlycontainer=true
    local b=chest(2,{item("grass",10,2)});b.tags.burnt=true
    check(not Auto.Tick(t,config))
end)
test("off sprinkler with remaining fuel left off",function()
    local t=target(10);t.components.machine={IsOn=function() return false end}
    item("log",20,2,nil,1);check(not Auto.Tick(t,config))
end)
test("zero and negative fuels skipped",function()
    local t=target(0);chest(1,{item("zero",0,2),item("negative",-2,2),item("log",20,2)})
    check(Auto.Tick(t,config));equal(t.components.fueled.currentfuel,20)
end)
test("gem generator uses actual Trader and consumes one",function()
    local t=target(0,300,"winona_battery_high");t._gems={};t.components.fueled.accepting=false
    local tr=Trader(t);t.components.trader=tr
    tr.deleteitemonaccept=false
    tr:SetAbleToAcceptTest(function(_,it) return it:HasTag("gem") end)
    tr.onaccept=function(_,giver,it)
        equal(giver,nil);t._gems[#t._gems+1]=it.prefab;t.components.fueled:DoDelta(100);it:Remove()
    end
    local g=item("redgem",nil,3);g.tags.gem=true;chest(1,{item("rocks"),g})
    check(Auto.Tick(t,config));equal(#t._gems,1);equal(g.components.stackable.stacksize,2)
    equal(t.components.fueled.currentfuel,100)
end)
print("RESULT "..passed.." tests passed (Lua 5.1, real DST Fueled + Trader components)")
