-- BlindSoundHunters - shared configuration
-- Lua 5.1 / Kahlua. Values are read from SandboxVars with safe fallbacks.

BSH = BSH or {}

-- Fixed behaviour thresholds (tiles / ms / ticks).
BSH.Const = {
    THROTTLE         = 5,     -- heavy work runs when (zombie:getID() + tick) % THROTTLE == 0
    ARRIVE_DIST      = 1.2,   -- ALERT_SPRINT -> IDLE_WANDER when this close to the sound origin
    TACTILE_DIST     = 0.85,  -- physical collision distance that triggers TACTILE_COMBAT
    RELEASE_DIST     = 1.8,   -- player must be farther than this (and silent) to escape TACTILE_COMBAT
    SOUND_MAX_AGE_MS = 1500,  -- buffered sounds older than this are ignored
    SOUND_MAX_DZ     = 1,     -- max floor difference for a sound to be heard
    REPATH_MS        = 2000,  -- re-issue pathToSound while sprinting at most this often
    BUFFER_SIZE      = 32,    -- world sound ring buffer size

    -- IDLE_WANDER: blind zombies have vanilla idle wandering disabled (setUseless),
    -- so the mod issues its own short random walks.
    WANDER_MIN_MS    = 6000,  -- min delay between random walks
    WANDER_RAND_MS   = 12000, -- extra random delay (0..WANDER_RAND_MS)
    WANDER_RADIUS    = 6,     -- tiles around the current position
    WANDER_CHANCE    = 60,    -- % chance to actually walk when the delay elapses

    SPEED_SPRINTER   = 1,     -- ZombieLore.Speed values
    SPEED_SHAMBLER   = 3,
}

local C = BSH.Const
C.ARRIVE_DIST2  = C.ARRIVE_DIST * C.ARRIVE_DIST
C.TACTILE_DIST2 = C.TACTILE_DIST * C.TACTILE_DIST
C.RELEASE_DIST2 = C.RELEASE_DIST * C.RELEASE_DIST

-- Defaults mirror 42/media/sandbox-options.txt.
BSH.Config = {
    HearingMultiplier  = 1.0,
    MinSoundRadius     = 5,
    Strength           = 1,   -- 1 Superhuman, 2 Normal, 3 Weak
    SprintOnSound      = true, -- false: alerted zombies walk to the sound instead of sprinting
    AlertMemorySeconds = 15,
    SilenceSeconds     = 2,
    -- derived
    AlertMemoryMs      = 15000,
    SilenceMs          = 2000,
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function BSH.refreshConfig()
    local cfg = BSH.Config
    local sv = SandboxVars and SandboxVars.BlindSoundHunters
    if sv == nil then
        cfg.AlertMemoryMs = cfg.AlertMemorySeconds * 1000
        cfg.SilenceMs = cfg.SilenceSeconds * 1000
        return
    end

    cfg.HearingMultiplier  = clamp(tonumber(sv.HearingMultiplier) or 1.0, 0.1, 5.0)
    cfg.MinSoundRadius     = clamp(tonumber(sv.MinSoundRadius) or 5, 0, 100)
    cfg.Strength           = clamp(math.floor(tonumber(sv.Strength) or 1), 1, 3)
    cfg.SprintOnSound      = sv.SprintOnSound ~= false
    cfg.AlertMemorySeconds = clamp(tonumber(sv.AlertMemorySeconds) or 15, 1, 120)
    cfg.SilenceSeconds     = clamp(tonumber(sv.SilenceSeconds) or 2, 0, 30)

    cfg.AlertMemoryMs = cfg.AlertMemorySeconds * 1000
    cfg.SilenceMs     = cfg.SilenceSeconds * 1000
end
