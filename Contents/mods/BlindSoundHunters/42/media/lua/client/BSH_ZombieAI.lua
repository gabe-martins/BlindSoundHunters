-- BlindSoundHunters - zombie state machine
--   IDLE_WANDER    : blind shambler (speedType 3), short random walks
--   ALERT_SPRINT   : heard a valid sound -> sprinter (speedType 1) running to its origin
--   TACTILE_COMBAT : hit/shoved or physical contact -> locked on the player
--
-- Blindness (verified against B42.22 bytecode):
--   IsoZombie.spottedNew/spottedOld clear the target and return when isUseless() is
--   true, so setUseless(true) removes vision at the source (clearing the target from
--   OnZombieUpdate is not enough: updateInternal calls spotted() right after the event
--   and WalkTowardState keeps re-pathing to the character).
--   Side effects of useless, handled here:
--     * RespondToSound returns early -> vanilla hearing off (the mod's own sound
--       system drives ALERT_SPRINT).
--     * ZombieIdleState skips wandering -> the mod issues its own random walks.
--     * WalkTowardState.enter sends useless zombies back to idle -> every move the
--       mod issues forces the pathfind state with setVariable("bPathfind", true).
--   TACTILE_COMBAT sets useless=false on that single zombie so vanilla attack/chase
--   logic works; releasing it sets useless=true again. `useless` is not saved.
--
-- Hot path rules: every tick only the cheap blindness guard runs. Sound scanning,
-- distance checks, pathfinding and stat changes run only when
-- (zombie:getID() + tickCounter) % THROTTLE == 0. No tables/closures are created here.

require "BSH_Config"
require "BSH_SoundListener"
require "BSH_CombatTactile"

local BSH = BSH
local Config = BSH.Config
local C = BSH.Const
local Sound = BSH.Sound
local Tactile = BSH.Tactile

local getPlayer = getPlayer
local getTimestampMs = getTimestampMs
local getSandboxOptions = getSandboxOptions
local ZombRand = ZombRand
local pcall = pcall
local print = print
local mathSqrt = math.sqrt
local mathFloor = math.floor

local STATE_IDLE    = 1
local STATE_ALERT   = 2
local STATE_TACTILE = 3
BSH.State = { IDLE_WANDER = STATE_IDLE, ALERT_SPRINT = STATE_ALERT, TACTILE_COMBAT = STATE_TACTILE }

local THROTTLE         = C.THROTTLE
local ARRIVE_DIST2     = C.ARRIVE_DIST2
local SOUND_MAX_AGE_MS = C.SOUND_MAX_AGE_MS
local SOUND_MAX_DZ     = C.SOUND_MAX_DZ
local REPATH_MS        = C.REPATH_MS
local SPEED_SPRINTER   = C.SPEED_SPRINTER
local SPEED_SHAMBLER   = C.SPEED_SHAMBLER
local WANDER_MIN_MS    = C.WANDER_MIN_MS
local WANDER_RAND_MS   = C.WANDER_RAND_MS
local WANDER_RADIUS    = C.WANDER_RADIUS
local WANDER_CHANCE    = C.WANDER_CHANCE

local SIZE = Sound.size
local sx, sy, sz, sr2, svol, st = Sound.x, Sound.y, Sound.z, Sound.r2, Sound.vol, Sound.t

local tickCounter = 0
local nowMs = 0
local sessionId = -1      -- invalidates modData state from older sessions / reused zombies
local player = nil
local speedOpt = nil
local strengthOpt = nil
local warnedNoOpts = false

---------------------------------------------------------------------------
-- Blindness / movement helpers
---------------------------------------------------------------------------

local function stopChasingCharacter(zombie)
    local pfb = zombie:getPathFindBehavior2()
    if pfb ~= nil and pfb:isGoalCharacter() then
        pfb:cancel()
        zombie:setPath2(nil)
    end
end

-- Removes vision at the source and drops whatever vanilla had already acquired.
local function makeBlind(zombie)
    zombie:setUseless(true)
    if zombie:getTarget() ~= nil then
        zombie:setTarget(nil)
        zombie:setTargetSeenTime(0)
    end
    stopChasingCharacter(zombie)
end

-- Useless zombies are kicked out of WalkTowardState, so always use the pathfind state.
local function moveToSound(zombie, x, y, z)
    zombie:pathToSound(x, y, z)
    zombie:setVariable("bPathfind", true)
end

local function moveToLocation(zombie, x, y, z)
    zombie:pathToLocation(x, y, z)
    zombie:setVariable("bPathfind", true)
end

local function scheduleWander(md)
    md.BSH_wanderMs = nowMs + WANDER_MIN_MS + ZombRand(WANDER_RAND_MS + 1)
end

local function updateWander(zombie, md)
    if nowMs < (md.BSH_wanderMs or 0) then return end
    scheduleWander(md)
    if ZombRand(100) >= WANDER_CHANCE then return end
    local span = WANDER_RADIUS * 2 + 1
    local x = mathFloor(zombie:getX()) + ZombRand(span) - WANDER_RADIUS
    local y = mathFloor(zombie:getY()) + ZombRand(span) - WANDER_RADIUS
    moveToLocation(zombie, x, y, mathFloor(zombie:getZ()))
end

---------------------------------------------------------------------------
-- Stats (speed + strength)
-- doZombieSpeed(int) shambles whenever ZombieLore.Speed == 3, and DoZombieStats reads
-- ZombieLore.Strength, so both options are swapped around the calls and restored.
---------------------------------------------------------------------------

local function doStats(zombie, speed)
    zombie:DoZombieStats()
    zombie:doZombieSpeed(speed)
end

local function applyStats(zombie, md, speed)
    md.BSH_speed = speed
    if speedOpt == nil or strengthOpt == nil then
        if not warnedNoOpts then
            warnedNoOpts = true
            print("[BlindSoundHunters] ZombieLore sandbox options not found; speed/strength changes disabled.")
        end
        return
    end

    local oldSpeed = speedOpt:getValue()
    local oldStrength = strengthOpt:getValue()
    speedOpt:setValue(speed)
    strengthOpt:setValue(Config.Strength)

    -- pcall guarantees the world options are restored even if the Java calls throw.
    local ok = pcall(doStats, zombie, speed)

    speedOpt:setValue(oldSpeed)
    strengthOpt:setValue(oldStrength)

    if not ok then
        print("[BlindSoundHunters] stat update failed for zombie " .. tostring(zombie:getID()))
    end
end

---------------------------------------------------------------------------
-- State transitions
---------------------------------------------------------------------------

local function initZombie(zombie, md)
    md.BSH_session   = sessionId
    md.BSH_state     = STATE_IDLE
    md.BSH_seq       = Sound.seq    -- do not react to sounds older than this zombie's init
    md.BSH_tx        = 0
    md.BSH_ty        = 0
    md.BSH_tz        = 0
    md.BSH_intensity = 0
    md.BSH_alertMs   = 0
    md.BSH_pathMs    = 0
    scheduleWander(md)
    makeBlind(zombie)
    applyStats(zombie, md, SPEED_SHAMBLER)
end

local function toIdle(zombie, md)
    md.BSH_state = STATE_IDLE
    md.BSH_intensity = 0
    scheduleWander(md)
    if md.BSH_speed ~= SPEED_SHAMBLER then
        applyStats(zombie, md, SPEED_SHAMBLER)
    end
end

local function startAlert(zombie, md, i, intensity)
    md.BSH_tx = sx[i]
    md.BSH_ty = sy[i]
    md.BSH_tz = sz[i]
    md.BSH_intensity = intensity
    md.BSH_alertMs = nowMs
    if md.BSH_state ~= STATE_ALERT then
        md.BSH_state = STATE_ALERT
        local speed = Config.SprintOnSound and SPEED_SPRINTER or SPEED_SHAMBLER
        if md.BSH_speed ~= speed then
            applyStats(zombie, md, speed)
        end
    end
    moveToSound(zombie, md.BSH_tx, md.BSH_ty, md.BSH_tz)
    md.BSH_pathMs = nowMs
end

local function enterTactile(zombie, target)
    local md = zombie:getModData()
    if md.BSH_session ~= sessionId or md.BSH_state == nil then
        initZombie(zombie, md)
    end
    md.BSH_state = STATE_TACTILE
    md.BSH_intensity = 0
    -- Only this zombie regains vanilla targeting, so it can attack/follow by touch.
    zombie:setUseless(false)
    zombie:setTarget(target)
    zombie:pathToCharacter(target)
end

local function releaseTactile(zombie, md)
    makeBlind(zombie)
    toIdle(zombie, md)
end

BSH.AI = {
    enterTactile   = enterTactile,
    releaseTactile = releaseTactile,
    toIdle         = toIdle,
    applyStats     = applyStats,
}

---------------------------------------------------------------------------
-- Throttled work
---------------------------------------------------------------------------

-- Scans buffered sounds this zombie has not seen yet. Picks the highest relative
-- intensity (volume / distance). While sprinting, only switches to a sound at least as
-- intense as the current one (equal intensity refreshes memory).
local function scanSounds(zombie, md, state)
    local seq = Sound.seq
    local last = md.BSH_seq or seq
    if last >= seq then return end
    md.BSH_seq = seq

    local first = last + 1
    if seq - first >= SIZE then first = seq - SIZE + 1 end

    local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()
    local bestI, bestIntensity = 0, 0

    for s = first, seq do
        local i = (s - 1) % SIZE + 1
        if nowMs - st[i] <= SOUND_MAX_AGE_MS then
            local dz = sz[i] - zz
            if dz < 0 then dz = -dz end
            if dz <= SOUND_MAX_DZ then
                local dx = sx[i] + 0.5 - zx
                local dy = sy[i] + 0.5 - zy
                local dist2 = dx * dx + dy * dy
                if dist2 <= sr2[i] then
                    local d = mathSqrt(dist2)
                    if d < 1 then d = 1 end
                    local intensity = svol[i] / d
                    if intensity > bestIntensity then
                        bestIntensity = intensity
                        bestI = i
                    end
                end
            end
        end
    end

    if bestI == 0 then return end
    if state ~= STATE_ALERT or bestIntensity >= (md.BSH_intensity or 0) then
        startAlert(zombie, md, bestI, bestIntensity)
    end
end

local function updateAlert(zombie, md)
    local dx = md.BSH_tx + 0.5 - zombie:getX()
    local dy = md.BSH_ty + 0.5 - zombie:getY()
    if dx * dx + dy * dy <= ARRIVE_DIST2 then
        toIdle(zombie, md)
        return
    end
    if nowMs - md.BSH_alertMs > Config.AlertMemoryMs then
        toIdle(zombie, md)
        return
    end
    if nowMs - md.BSH_pathMs >= REPATH_MS then
        moveToSound(zombie, md.BSH_tx, md.BSH_ty, md.BSH_tz)
        md.BSH_pathMs = nowMs
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function onZombieUpdate(zombie)
    if zombie == nil or zombie:isDead() then return end

    local md = zombie:getModData()
    local state = md.BSH_state
    if md.BSH_session ~= sessionId then state = nil end

    -- Total blindness guard (cheap): new/reused zombies get blinded on their first
    -- update, before the throttled init runs.
    if state ~= STATE_TACTILE and not zombie:isUseless() then
        makeBlind(zombie)
    end

    if (zombie:getID() + tickCounter) % THROTTLE ~= 0 then return end

    if state == nil then
        initZombie(zombie, md)
        state = STATE_IDLE
    end

    if state == STATE_TACTILE then
        Tactile.update(zombie, md, player, nowMs)
        return
    end

    if player ~= nil and not player:isDead() and Tactile.checkCollision(zombie, player) then
        enterTactile(zombie, player)
        return
    end

    scanSounds(zombie, md, state)

    if md.BSH_state == STATE_ALERT then
        updateAlert(zombie, md)
    else
        updateWander(zombie, md)
    end
end

local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter >= 1000000000 then tickCounter = 0 end
    nowMs = getTimestampMs()
    player = getPlayer()
end

local function onZombieDead(zombie)
    if zombie == nil then return end
    local md = zombie:getModData()
    md.BSH_state = nil
    md.BSH_session = nil
end

local function onGameStart()
    BSH.refreshConfig()
    sessionId = getTimestampMs()
    nowMs = sessionId
    player = getPlayer()

    local opts = getSandboxOptions()
    if opts ~= nil then
        speedOpt = opts:getOptionByName("ZombieLore.Speed")
        strengthOpt = opts:getOptionByName("ZombieLore.Strength")
    end
    print("[BlindSoundHunters] loaded (session " .. tostring(sessionId) .. ")")
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
Events.OnZombieUpdate.Add(onZombieUpdate)
Events.OnZombieDead.Add(onZombieDead)
