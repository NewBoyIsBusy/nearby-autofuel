-- Runs only in the isolated offline validation world, never in the release mod.
local Auto = require("nearby_autofuel")
local config = {radius=8,threshold=1,ground=true,empty=true}
local spawned, count = {}, 0
local function spawn(name,x)
    local e=assert(SpawnPrefab(name),name)
    e.Transform:SetPosition(100+(x or 0),0,100)
    spawned[#spawned+1]=e
    return e
end
local function stack(name,n,x)
    local e=spawn(name,x)
    e.components.stackable:SetStackSize(n)
    return e
end
local function approx(a,b) assert(math.abs(a-b)<0.001,tostring(a).." ~= "..tostring(b)) end
local function setup(name)
    local t=spawn(name or "firepit")
    assert(t._nearby_autofuel_task,"modmain failed to attach task")
    t._nearby_autofuel_task:Cancel()
    t.components.fueled:StopConsuming()
    t.components.fueled:SetPercent(.1)
    return t
end
local function test(name,fn)
    fn()
    count=count+1
    print("AUTOFUEL_GAME_PASS "..name)
    for _,e in ipairs(spawned) do if e:IsValid() then e:Remove() end end
    spawned={}
end
test("real chest slot order and one item from a stack",function()
    local t=setup();local c=spawn("treasurechest",2).components.container
    local rocks=stack("rocks",3);local logs=stack("log",5);local grass=stack("cutgrass",5)
    assert(c:GiveItem(rocks,1));assert(c:GiveItem(logs,3));assert(c:GiveItem(grass,4))
    local old=t.components.fueled.currentfuel
    local value=logs.components.fuel.fuelvalue*t.components.fueled.bonusmult
    assert(Auto.Tick(t,config));approx(t.components.fueled.currentfuel,old+value)
    assert(logs.components.stackable:StackSize()==4)
    assert(grass.components.stackable:StackSize()==5)
    assert(c:GetItemInSlot(1)==rocks and c:GetItemInSlot(3)==logs)
end)
test("real chest before ground and no overflow",function()
    local t=setup();local c=spawn("treasurechest",2).components.container
    local logs=stack("log",3);local grass=stack("cutgrass",3,1)
    assert(c:GiveItem(logs,1))
    t.components.fueled:SetPercent(.99)
    assert(not Auto.Tick(t,config));assert(logs.components.stackable:StackSize()==3)
    assert(grass.components.stackable:StackSize()==3)
end)
test("real ground stack and wet fuel",function()
    local t=setup();local logs=stack("log",3,1)
    logs.components.inventoryitem:InheritMoisture(100,true)
    local old=t.components.fueled.currentfuel
    local value=logs.components.fuel.fuelvalue*t.components.fueled.bonusmult*TUNING.WET_FUEL_PENALTY
    assert(logs:GetIsWet());assert(Auto.Tick(t,config))
    approx(t.components.fueled.currentfuel,old+value)
    assert(logs.components.stackable:StackSize()==2)
end)
test("real chest rejected transfer restores item",function()
    local t=setup();local c=spawn("treasurechest",2).components.container
    local logs=stack("log",3);assert(c:GiveItem(logs,1))
    t.components.fueled.TakeFuelItem=function() return false end
    assert(not Auto.Tick(t,config));assert(logs.components.stackable:StackSize()==3)
end)
for _,name in ipairs({"campfire","coldfire","coldfirepit","nightlight","firesuppressor","winona_battery_low"}) do
    test("real building "..name,function()
        local t=setup(name)
        local fuel=name=="nightlight" and "nightmarefuel" or name=="winona_battery_low" and "nitre" or "log"
        local g=stack(fuel,3,1)
        if t.components.machine then t.components.machine:TurnOn() end
        local old=t.components.fueled.currentfuel
        assert(Auto.Tick(t,config),name.." rejected "..fuel)
        assert(t.components.fueled.currentfuel>old)
        assert(g.components.stackable:StackSize()==2)
    end)
end
test("real gem generator",function()
    local t=setup("winona_battery_high")
    local gems=stack("redgem",3,1)
    local old=t.components.fueled.currentfuel
    assert(Auto.Tick(t,config));assert(#t._gems==1)
    assert(t.components.fueled.currentfuel>old);assert(gems.components.stackable:StackSize()==2)
end)
test("real switched off sprinkler stays off",function()
    local t=setup("firesuppressor");t.components.machine:TurnOff()
    local logs=stack("log",3,1)
    assert(not Auto.Tick(t,config));assert(not t.components.machine:IsOn())
    assert(logs.components.stackable:StackSize()==3)
end)
print("AUTOFUEL_GAME_RESULT "..count.." synchronous cases passed")
-- Verify the actual periodic modmain callback, not only direct Tick calls.
local t=spawn("firepit");t.components.fueled:SetPercent(.1)
local c=spawn("treasurechest",2).components.container
local logs=stack("log",10);assert(c:GiveItem(logs,1))
TheWorld:DoTaskInTime(3,function()
    if logs:IsValid() and logs.components.stackable:StackSize()<10 and t.components.fueled:GetPercent()>.1 then
        print("AUTOFUEL_GAME_SUCCESS periodic callback and "..count.." synchronous cases passed")
    else
        print("AUTOFUEL_GAME_FAILURE periodic callback did not refuel")
    end
    c_shutdown(false)
end)
