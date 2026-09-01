--***********************************************************************
-- Bandits & Survivors — bandits vs doors (server)
--
-- Bandits can get through closed doors, but never silently or
-- instantly. An unlocked door takes a configurable delay (sandbox,
-- default 3s) of audible handle-rattling before it swings open. A door
-- secured by a combination lock (BNS_Locks), key lock or barricade
-- can't be opened at all: a bandit with a reason to get in (pursuit or
-- raid) has to break it down — slow, and loud enough to warn the whole
-- street (and pull in zombies). Wandering bandits give up on secured
-- doors and go elsewhere.
--***********************************************************************

if isClient() then return end

require "BNS/BNS_Core"
require "BNS/BNS_Anim"
require "BNS/BNS_Locks"

BNS.Doors = {}

local OPEN_NOISE_EVERY = 60  -- ticks between rattles while opening (~1s)
local BASH_EVERY       = 90  -- ticks between bashes (~1.5s)
local NOISE_RADIUS_OPEN = 20 -- world-sound radius of the rattle
local NOISE_RADIUS_BASH = 25 -- bashing wakes the whole street

-- Landed bashes needed to break a secured door, by tier.
local BASH_HITS = {
    [BNS.Tier.CIVILIAN] = 12,
    [BNS.Tier.THUG]     = 8,
    [BNS.Tier.MILITIA]  = 6,
}

-- Programs that justify breaking a door down rather than giving up.
local PURSUIT = {
    [BNS.Program.APPROACH] = true,
    [BNS.Program.ATTACK]   = true,
    [BNS.Program.ROB]      = true,
    [BNS.Program.RAID]     = true,
}

-- Detection --------------------------------------------------------------

local function isClosedDoor(obj)
    if not obj then return false end
    local isDoor = instanceof(obj, "IsoDoor")
        or (instanceof(obj, "IsoThumpable") and obj.isDoor and obj:isDoor())
    if not isDoor then return false end
    if obj.IsOpen and obj:IsOpen() then return false end
    return true
end

-- A closed door on the NPC's square or one of its 8 neighbours.
function BNS.Doors.findBlockingDoor(zombie)
    local cell = getCell()
    if not cell then return nil end
    local cx = math.floor(zombie:getX())
    local cy = math.floor(zombie:getY())
    local cz = math.floor(zombie:getZ())
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    if isClosedDoor(obj) then
                        return obj, sq:getX(), sq:getY(), sq:getZ()
                    end
                end
            end
        end
    end
    return nil
end

local function resolveDoor(st)
    local sq = getCell() and getCell():getGridSquare(st.x, st.y, st.z) or nil
    if not sq then return nil end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        if isClosedDoor(obj) then return obj end
    end
    return nil
end

-- Starting an attempt ----------------------------------------------------

-- Called when a stalled bandit might be stuck on a door. Returns true
-- when a door attempt started.
function BNS.Doors.tryStart(zombie, brain)
    if brain.door then return true end
    local door, x, y, z = BNS.Doors.findBlockingDoor(zombie)
    if not door then
        -- Not a door problem: unstick wanderers by forcing a new target.
        if brain.program == BNS.Program.WANDER then
            brain.targetX, brain.targetY = nil, nil
        end
        return false
    end
    if BNS.Locks.isSecured(door) then
        if not PURSUIT[brain.program] then
            -- No reason to break in: go around.
            if brain.program == BNS.Program.WANDER then
                brain.targetX, brain.targetY = nil, nil
            end
            return false
        end
        brain.door = { x = x, y = y, z = z, bash = true, bashCount = 0, noiseTimer = 1 }
    else
        local delay = math.max((BNS.Options().doorDelay or 3) * 60, 30)
        brain.door = { x = x, y = y, z = z, timer = delay, noiseTimer = 1 }
    end
    return true
end

function BNS.Doors.abort(brain)
    brain.door = nil
end

-- Working the door -------------------------------------------------------

local function openDoor(zombie, door)
    if door.ToggleDoor then
        local ok = pcall(function() door:ToggleDoor(zombie) end)
        if ok then return end
    end
    if door.setOpened then pcall(function() door:setOpened(true) end) end
end

local function smashDoor(zombie, door)
    BNS.Locks.onDoorDestroyed(door)
    zombie:playSound("WoodDoorBreak")
    addSound(zombie, zombie:getX(), zombie:getY(), zombie:getZ(), NOISE_RADIUS_BASH, 50)
    local sq = door.getSquare and door:getSquare() or nil
    local ok = false
    if door.destroy then
        ok = pcall(function() door:destroy() end)
    end
    if not ok and sq then
        pcall(function() sq:transmitRemoveItemFromSquare(door) end)
        pcall(function() sq:RemoveTileObject(door) end)
    end
end

-- Per-engine-tick driver, called from BNS_Brain. Returns true while the
-- NPC is busy with a door (movement and attacks are held meanwhile).
function BNS.Doors.tick(zombie, brain)
    local st = brain.door
    if not st then return false end
    local door = resolveDoor(st)
    if not door then
        brain.door = nil
        return false
    end

    st.noiseTimer = st.noiseTimer - 1
    if st.bash then
        if st.noiseTimer <= 0 then
            st.noiseTimer = BASH_EVERY
            st.bashCount = st.bashCount + 1
            BNS.Anim.pulse(zombie, brain, "swing")
            zombie:playSound("ZombieThumpGeneric")
            addSound(zombie, zombie:getX(), zombie:getY(), zombie:getZ(), NOISE_RADIUS_BASH, 40)
            if st.bashCount >= (BASH_HITS[brain.tier] or 12) then
                smashDoor(zombie, door)
                brain.door = nil
                return false
            end
        end
        return true
    end

    -- Unlocked door: rattle through the delay, then open it.
    if st.noiseTimer <= 0 then
        st.noiseTimer = OPEN_NOISE_EVERY
        BNS.Anim.set(zombie, brain, "idle")
        zombie:playSound("ZombieThumpGeneric")
        addSound(zombie, zombie:getX(), zombie:getY(), zombie:getZ(), NOISE_RADIUS_OPEN, 30)
    end
    st.timer = st.timer - 1
    if st.timer <= 0 then
        openDoor(zombie, door)
        brain.door = nil
        return false
    end
    return true
end
