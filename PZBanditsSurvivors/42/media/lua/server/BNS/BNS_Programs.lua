--***********************************************************************
-- Bandits & Survivors — brain programs (server)
--
-- Each program is a function(zombie, brain, ctx) run every brain tick.
-- ctx carries the nearest player and distance. Programs mutate
-- brain.program to transition; BNS_Brain dispatches.
--***********************************************************************

if isClient() then return end

require "BNS/BNS_Core"
require "BNS/BNS_Combat"

BNS.Programs = {}

-- Speech: broadcast to clients so text appears over the NPC's head.
function BNS.Say(zombie, brain, text)
    brain.speechCooldown = brain.speechCooldown or 0
    if brain.speechCooldown > 0 then return end
    brain.speechCooldown = 300
    local args = { id = zombie:getOnlineID(), text = text, x = zombie:getX(), y = zombie:getY() }
    if isServer() then
        sendServerCommand(BNS.CommandModule, "say", args)
    elseif BNS.Client and BNS.Client.showSpeech then
        BNS.Client.showSpeech(args) -- single player: call straight through
    end
end

-- Movement --------------------------------------------------------------

function BNS.Programs.walkTo(zombie, x, y, z, run)
    if zombie.pathToLocationF then
        zombie:pathToLocationF(x, y, z or 0)
    elseif zombie.pathToLocation then
        zombie:pathToLocation(math.floor(x), math.floor(y), z or 0)
    end
    if zombie.setRunning then zombie:setRunning(run == true) end
end

local function arrived(zombie, brain, dist)
    if not brain.targetX then return true end
    return BNS.dist(zombie:getX(), zombie:getY(), brain.targetX, brain.targetY) < (dist or 2)
end

-- Threat perception: does this NPC currently notice the player?
local function noticesPlayer(zombie, ctx)
    if not ctx.player then return false end
    if ctx.dist > 30 then return false end
    if ctx.dist < 8 then return true end
    -- Beyond close range, sneaking players in cover go unnoticed.
    return not ctx.player:isSneaking() or ZombRand(100) < 10
end

-- WANDER ----------------------------------------------------------------

BNS.Programs[BNS.Program.WANDER] = function(zombie, brain, ctx)
    if brain.role == BNS.Role.BANDIT and noticesPlayer(zombie, ctx) then
        brain.program = BNS.Program.APPROACH
        return
    end
    if arrived(zombie, brain, 3) then
        -- Pick a new destination: nearby drift, occasionally a long trek.
        local reach = ZombRand(100) < 15 and 300 or 40
        brain.targetX = zombie:getX() + ZombRand(-reach, reach + 1)
        brain.targetY = zombie:getY() + ZombRand(-reach, reach + 1)
    end
    BNS.Programs.walkTo(zombie, brain.targetX, brain.targetY, 0, false)
end

-- APPROACH (bandits closing on a player) --------------------------------

BNS.Programs[BNS.Program.APPROACH] = function(zombie, brain, ctx)
    local p = ctx.player
    if not p or ctx.dist > 45 then
        brain.program = BNS.Program.WANDER
        return
    end
    local opts = BNS.Options()
    -- Decide intent once, when first getting close.
    if ctx.dist < 6 and not brain.intent then
        local robChance = 0
        if opts.robbery then
            if brain.tier == BNS.Tier.CIVILIAN then robChance = 65
            elseif brain.tier == BNS.Tier.THUG then robChance = 35 end
        end
        -- Nobody tries to mug someone aiming a gun at them.
        if p:isAiming() then robChance = 0 end
        brain.intent = (ZombRand(100) < robChance) and BNS.Program.ROB or BNS.Program.ATTACK
    end
    if brain.intent and ctx.dist < 4 then
        brain.program = brain.intent
        return
    end
    -- Gunners open fire before closing.
    if brain.weapon and brain.weapon.gun and ctx.dist < brain.weapon.range then
        brain.program = BNS.Program.ATTACK
        return
    end
    BNS.Programs.walkTo(zombie, p:getX(), p:getY(), p:getZ(), true)
end

-- ROB -------------------------------------------------------------------

local function stealFromPlayer(player)
    local inv = player:getInventory()
    local items = inv:getItems()
    local stolen = {}
    -- Take money first, then up to two random non-equipped items.
    local money = inv:getFirstTypeRecurse("Money")
    if money then
        inv:Remove(money)
        table.insert(stolen, money:getFullType())
    end
    for _ = 1, 2 do
        if items:size() == 0 then break end
        local it = items:get(ZombRand(items:size()))
        if it and not player:isEquipped(it) and not it:isFavorite() then
            inv:Remove(it)
            table.insert(stolen, it:getFullType())
        end
    end
    return stolen
end

BNS.Programs[BNS.Program.ROB] = function(zombie, brain, ctx)
    local p = ctx.player
    if not p or ctx.dist > 10 then brain.program = BNS.Program.WANDER return end
    -- Player pulled a weapon up: robbery turns into a fight.
    if p:isAiming() then
        brain.program = BNS.Program.ATTACK
        return
    end
    if ctx.dist > 2 then
        BNS.Programs.walkTo(zombie, p:getX(), p:getY(), p:getZ(), true)
        BNS.Say(zombie, brain, getText("UI_BNS_RobberyDemand"))
        return
    end
    brain.robTimer = (brain.robTimer or 120) - 1 -- ~2s standoff, then take
    if brain.robTimer <= 0 then
        local stolen = stealFromPlayer(p)
        if isServer() then
            sendServerCommand(p, BNS.CommandModule, "robbed", { items = stolen })
        end
        brain.speechCooldown = 0
        BNS.Say(zombie, brain, getText("UI_BNS_RobberyDone"))
        brain.robTimer = nil
        brain.intent = nil
        brain.program = BNS.Program.FLEE
        brain.fleeUntil = 600
    end
end

-- ATTACK ----------------------------------------------------------------

BNS.Programs[BNS.Program.ATTACK] = function(zombie, brain, ctx)
    local p = ctx.player
    if not p or ctx.dist > 50 or p:isDead() then
        brain.program = brain.home and BNS.Program.DEFEND or BNS.Program.WANDER
        brain.intent = nil
        return
    end
    local w = brain.weapon or {}
    if w.gun then
        -- Keep distance and shoot; close only if the player hides.
        if ctx.dist > w.range * 0.8 then
            BNS.Programs.walkTo(zombie, p:getX(), p:getY(), p:getZ(), true)
        end
        BNS.Combat.attack(zombie, brain, p)
    else
        if ctx.dist > (w.range or 1.3) then
            BNS.Programs.walkTo(zombie, p:getX(), p:getY(), p:getZ(), true)
        end
        BNS.Combat.attack(zombie, brain, p)
    end
end

-- FLEE ------------------------------------------------------------------

BNS.Programs[BNS.Program.FLEE] = function(zombie, brain, ctx)
    brain.fleeUntil = (brain.fleeUntil or 600) - 1
    if brain.fleeUntil <= 0 then
        brain.fleeUntil = nil
        brain.program = BNS.Program.WANDER
        return
    end
    local p = ctx.player
    if p then
        local dx = zombie:getX() - p:getX()
        local dy = zombie:getY() - p:getY()
        local d = math.max(BNS.dist(0, 0, dx, dy), 0.1)
        BNS.Programs.walkTo(zombie, zombie:getX() + dx / d * 20, zombie:getY() + dy / d * 20, 0, true)
    end
end

-- DEFEND (POI garrison) -------------------------------------------------

BNS.Programs[BNS.Program.DEFEND] = function(zombie, brain, ctx)
    local home = brain.home
    if not home then brain.program = BNS.Program.WANDER return end
    -- Engage players who come within the perimeter.
    if ctx.player and ctx.dist < 15 and noticesPlayer(zombie, ctx) then
        brain.program = BNS.Program.ATTACK
        return
    end
    local dHome = BNS.dist(zombie:getX(), zombie:getY(), home.x, home.y)
    if dHome > (home.radius or 12) then
        BNS.Programs.walkTo(zombie, home.x, home.y, 0, false)
    elseif ZombRand(600) == 0 then
        -- Patrol drift inside the perimeter.
        BNS.Programs.walkTo(zombie,
            home.x + ZombRand(-(home.radius or 10), (home.radius or 10) + 1),
            home.y + ZombRand(-(home.radius or 10), (home.radius or 10) + 1), 0, false)
    end
end

-- TRADE (traders/survivors idling near players) -------------------------

BNS.Programs[BNS.Program.TRADE] = function(zombie, brain, ctx)
    -- Traders stand still while a customer is close, else wander slowly.
    if ctx.player and ctx.dist < 6 then
        if zombie.StopAllActionQueue then zombie:StopAllActionQueue() end
        return
    end
    BNS.Programs[BNS.Program.WANDER](zombie, brain, ctx)
end
