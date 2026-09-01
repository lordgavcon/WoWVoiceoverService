--***********************************************************************
-- Bandits & Survivors — brain dispatcher (server)
--
-- Hooks OnZombieUpdate to drive NPC shells, keeps the engine's zombie
-- instincts suppressed, routes player weapon hits into NPC health, and
-- handles NPC death (loot + record removal).
--***********************************************************************

if isClient() then return end

require "BNS/BNS_Core"
require "BNS/BNS_Persistence"
require "BNS/BNS_Spawner"
require "BNS/BNS_Programs"

BNS.Brain = {}

local TICK_DIVIDER = 10 -- run full brain logic every N engine updates

local function suppressZombie(zombie)
    -- Re-assert every tick: keep the shell from lunging, biting or
    -- aggroing like a zombie.
    zombie:setUseless(true)
    if zombie.setTarget then zombie:setTarget(nil) end
    if zombie.setAttackedBy then zombie:setAttackedBy(nil) end
end

local function updateNPC(zombie, brain)
    suppressZombie(zombie)

    brain.tick = (brain.tick or ZombRand(TICK_DIVIDER)) + 1
    -- Combat timers must count every tick for smooth attack pacing.
    if brain.speechCooldown and brain.speechCooldown > 0 then
        brain.speechCooldown = brain.speechCooldown - 1
    end
    if brain.tick % TICK_DIVIDER ~= 0 then
        -- Between full ticks, keep attacking if mid-fight.
        if brain.program == BNS.Program.ATTACK or brain.program == BNS.Program.ROB then
            local p, d = BNS.nearestPlayer(zombie:getX(), zombie:getY())
            if p and brain.program == BNS.Program.ATTACK then
                BNS.Combat.attack(zombie, brain, p)
            end
        end
        return
    end

    local player, dist = BNS.nearestPlayer(zombie:getX(), zombie:getY())
    local ctx = { player = player, dist = dist or 999999 }

    -- Survivors and traders don't fight players; zombies scare everyone.
    if brain.role ~= BNS.Role.BANDIT
            and brain.program ~= BNS.Program.FLEE
            and brain.program ~= BNS.Program.TRADE then
        brain.program = BNS.Program.TRADE
    end

    local program = BNS.Programs[brain.program] or BNS.Programs[BNS.Program.WANDER]
    program(zombie, brain, ctx)

    -- Trickle position back into the persistent record.
    if brain.tick % (TICK_DIVIDER * 30) == 0 then
        BNS.Persistence.syncFromShell(zombie)
    end
end

function BNS.Brain.onZombieUpdate(zombie)
    local brain = BNS.brain(zombie)
    if not brain then return end
    if zombie:isDead() then return end
    updateNPC(zombie, brain)
end

-- Player weapons hitting NPC shells ------------------------------------

function BNS.Brain.onWeaponHitCharacter(attacker, target, weapon, damage)
    if not BNS.isNPC(target) then return end
    local brain = BNS.brain(target)
    -- Engine damage numbers vary wildly by weapon; normalise to our scale.
    local amount = math.min((damage or 0.5) / 2.5, 0.9)
    BNS.Combat.damageNPC(target, brain, amount)
    -- Bandits retaliate; neutrals turn hostile if attacked.
    if brain.health > 0 then
        if brain.role ~= BNS.Role.BANDIT then brain.role = BNS.Role.BANDIT end
        brain.program = (brain.tier == BNS.Tier.CIVILIAN and brain.health < 0.4)
            and BNS.Program.FLEE or BNS.Program.ATTACK
    end
end

-- Death -----------------------------------------------------------------

function BNS.Brain.onZombieDead(zombie)
    local brain = BNS.brain(zombie)
    if not brain then return end
    BNS.Spawner.dropLoot(zombie, brain)
    BNS.Persistence.remove(brain.id)
    if isServer() then
        sendServerCommand(BNS.CommandModule, "npcDead", { id = brain.id })
    end
end

Events.OnZombieUpdate.Add(BNS.Brain.onZombieUpdate)
Events.OnWeaponHitCharacter.Add(BNS.Brain.onWeaponHitCharacter)
Events.OnZombieDead.Add(BNS.Brain.onZombieDead)
