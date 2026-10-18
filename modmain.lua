local G = GLOBAL
local AutoFuel = G.require("nearby_autofuel")
local config = {
    radius = GetModConfigData("SEARCH_RADIUS") or 8,
    threshold = GetModConfigData("REFUEL_PERCENT") or 0.5,
    ground = GetModConfigData("GROUND_FUEL") ~= false,
    interval = GetModConfigData("CHECK_INTERVAL") or 0.5,
    empty = GetModConfigData("REFUEL_EMPTY") ~= false,
}

AddPrefabPostInitAny(function(inst)
    if G.TheWorld == nil or not G.TheWorld.ismastersim or not AutoFuel.IsTarget(inst) then
        return
    end
    -- Start after prefab creation / save loading. Entity removal cancels its tasks.
    if inst._nearby_autofuel_task == nil then
        inst._nearby_autofuel_task = inst:DoPeriodicTask(config.interval, function()
            AutoFuel.Tick(inst, config)
        end, 1 + G.math.random() * config.interval)
    end
end)
