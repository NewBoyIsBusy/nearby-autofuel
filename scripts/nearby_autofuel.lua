local M = {}
local EXCLUDE = { "INLIMBO", "NOCLICK", "FX", "DECOR", "burnt" }
local SOURCE_TAGS = { "structure", "_inventoryitem" }

local function IsAvailable(inst)
    return inst ~= nil and inst:IsValid()
        and not inst:HasTag("INLIMBO") and not inst:HasTag("NOCLICK")
        and not inst:HasTag("burnt")
end

function M.IsTarget(inst)
    return inst.components.fueled ~= nil
        and inst.components.inventoryitem == nil
        and (inst:HasTag("structure") or inst:HasTag("campfire"))
end

local function IsGemGenerator(inst)
    return inst.prefab == "winona_battery_high"
        and inst.components.trader ~= nil and inst._gems ~= nil
end

local function IsStorage(inst)
    local container = inst.components.container
    return IsAvailable(inst) and inst:HasTag("structure")
        and inst.components.inventoryitem == nil
        and inst.components.health == nil
        and container ~= nil and container.type == "chest"
        and container.canbeopened ~= false and not container.readonlycontainer
        and inst.components.container_proxy == nil
        and inst.components.pocketdimensioncontainer == nil
        and inst.prefab ~= "shadow_container"
        and not (inst.components.burnable ~= nil and inst.components.burnable:IsBurning())
end

local function IsGroundItem(inst)
    local inventoryitem = inst.components.inventoryitem
    return IsAvailable(inst) and inventoryitem ~= nil
        and inventoryitem.owner == nil and inventoryitem.canbepickedup ~= false
        and inst.entity:GetParent() == nil
        and not (inst.components.burnable ~= nil and inst.components.burnable:IsBurning())
end

-- Same calculation as Fueled:TakeFuelItem(item, nil). No character mastery bonus.
local function FuelValue(inst, item)
    local fueled = inst.components.fueled
    local fuel = item.components.fuel
    -- CanAcceptFuelItem assumes a fuel component; never pass arbitrary chest items.
    if fuel == nil or not fueled:CanAcceptFuelItem(item)
        or (fueled.cantakefuelitemfn ~= nil
            and not fueled.cantakefuelitemfn(inst, item, nil)) then
        return nil
    end
    local mult = fueled.multfn ~= nil and fueled.multfn(inst, item) or 1
    local wetmult = item:GetIsWet() and TUNING.WET_FUEL_PENALTY or 1
    local value = fuel.fuelvalue * fueled.bonusmult * mult * wetmult
    -- Oversized fuel can NEVER fit: skip it instead of blocking the entire chest.
    if value > 0 and value <= fueled.maxfuel then
        return value
    end
end

-- nil = not usable; false = usable but must wait; true = can consume one now.
local function ItemStatus(inst, item)
    if item == nil or not item:IsValid() or item.components.inventoryitem == nil
        or item.components.itemmimic ~= nil then
        return nil
    end
    local fueled = inst.components.fueled
    if IsGemGenerator(inst) then
        -- This prefab uses trader / gem slots, not fueled:TakeFuelItem.
        -- Skill-gated lunar items and nightmare fuel are not granted player skills.
        if not item:HasTag("gem") then
            return nil
        end
        local trader = inst.components.trader
        if not trader:AbleToAccept(item, nil, 1)
            or not trader:WantsToAccept(item, nil, 1) then
            return nil
        end
        return #inst._gems < 3 and fueled.currentfuel < fueled.maxfuel
    end
    local value = FuelValue(inst, item)
    if value ~= nil then
        return value <= fueled.maxfuel - fueled.currentfuel
    end
end

local function SortByDistance(inst, entities)
    table.sort(entities, function(a, b)
        local da, db = inst:GetDistanceSqToInst(a), inst:GetDistanceSqToInst(b)
        return da == db and a.GUID < b.GUID or da < db
    end)
end

local function FindCandidate(inst, config)
    local x, y, z = inst.Transform:GetWorldPosition()
    local entities = TheSim:FindEntities(x, y, z, config.radius, nil, EXCLUDE, SOURCE_TAGS)
    local chests, ground = {}, {}
    for _, entity in ipairs(entities) do
        if entity ~= inst then
            if IsStorage(entity) then
                chests[#chests + 1] = entity
            elseif config.ground and IsGroundItem(entity) then
                ground[#ground + 1] = entity
            end
        end
    end
    SortByDistance(inst, chests)
    for _, chest in ipairs(chests) do
        local container = chest.components.container
        -- Numeric traversal: pairs() does not preserve slot order or empty slots.
        for slot = 1, container:GetNumSlots() do
            local item = container:GetItemInSlot(slot)
            local status = ItemStatus(inst, item)
            if status ~= nil then
                return { item = item, container = container, slot = slot, ready = status }
            end
        end
    end
    SortByDistance(inst, ground)
    for _, item in ipairs(ground) do
        local status = ItemStatus(inst, item)
        if status ~= nil then
            return { item = item, ready = status }
        end
    end
end

local function RestoreItem(item, candidate, pos)
    if not item:IsValid() then
        return
    end
    if candidate.container ~= nil and candidate.container.inst:IsValid() then
        -- GiveItem also drops at src_pos if a callback filled/disabled the slot.
        candidate.container:GiveItem(item, candidate.slot, pos, true)
    elseif candidate.item ~= item and candidate.item:IsValid()
        and candidate.item.components.stackable ~= nil
        and candidate.item.components.stackable:CanStackWith(item) then
        local remainder = candidate.item.components.stackable:Put(item)
        if remainder ~= nil then
            remainder.Transform:SetPosition(pos:Get())
            remainder.components.inventoryitem:OnDropped(true)
        end
    else
        item.Transform:SetPosition(pos:Get())
        item.components.inventoryitem:OnDropped(true)
    end
end

function M.Tick(inst, config)
    if not IsAvailable(inst) or not M.IsTarget(inst) then
        return false
    end
    local fueled = inst.components.fueled
    if fueled.maxfuel <= 0 or fueled.currentfuel >= fueled.maxfuel
        or fueled:GetPercent() > config.threshold
        or (not config.empty and fueled.currentfuel <= 0)
        or (not fueled.accepting and not IsGemGenerator(inst)) then
        return false
    end
    -- Do not restart a manually switched-off sprinkler that still has fuel.
    if inst.components.machine ~= nil and not inst.components.machine:IsOn()
        and fueled.currentfuel > 0 then
        return false
    end
    local candidate = FindCandidate(inst, config)
    if candidate == nil or not candidate.ready then
        return false
    end
    local item = candidate.item
    local pos = candidate.container ~= nil and candidate.container.inst:GetPosition()
        or item:GetPosition()
    if candidate.container ~= nil then
        item = candidate.container:RemoveItem(item, false)
    elseif item.components.stackable ~= nil then
        item = item.components.stackable:Get(1)
        if item ~= nil then
            item.Transform:SetPosition(pos:Get())
        end
    end
    if item == nil then
        return false
    end
    -- Stack splitting/removal can run callbacks. Recheck the actual single item.
    local accepted = false
    if IsAvailable(inst) and M.IsTarget(inst) and ItemStatus(inst, item) == true then
        if IsGemGenerator(inst) then
            accepted = inst.components.trader:AcceptGift(nil, item, 1) == true
        else
            accepted = inst.components.fueled:TakeFuelItem(item, nil) == true
        end
    end
    if not accepted then
        RestoreItem(item, candidate, pos)
    end
    return accepted
end

return M
