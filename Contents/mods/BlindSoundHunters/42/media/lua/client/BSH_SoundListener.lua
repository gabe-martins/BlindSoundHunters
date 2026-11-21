-- BlindSoundHunters - world sound filtering
-- OnWorldSound only validates the sound and writes it into a preallocated ring
-- buffer (O(1), no allocation). Zombies consume the buffer on their throttled tick
-- in BSH_ZombieAI.lua, so the per-zombie cost is spread across frames.

require "BSH_Config"

local BSH = BSH
local Config = BSH.Config
local instanceof = instanceof
local getTimestampMs = getTimestampMs
local mathFloor = math.floor

local SIZE = BSH.Const.BUFFER_SIZE

local Sound = {
    size = SIZE,
    seq = 0,               -- total number of sounds accepted (monotonic)
    lastPlayerMs = -1e12,  -- last time a player produced any sound (used for TACTILE silence)
    x = {}, y = {}, z = {},
    r2 = {},               -- effective radius squared (already multiplied by HearingMultiplier)
    vol = {},
    t = {},
}
for i = 1, SIZE do
    Sound.x[i] = 0
    Sound.y[i] = 0
    Sound.z[i] = 0
    Sound.r2[i] = 0
    Sound.vol[i] = 0
    Sound.t[i] = -1e12
end
BSH.Sound = Sound

local sx, sy, sz, sr2, svol, st = Sound.x, Sound.y, Sound.z, Sound.r2, Sound.vol, Sound.t

local function onWorldSound(x, y, z, radius, volume, source)
    -- No physical origin: ignore.
    if source == nil then return end
    -- Passive zombie noises (groans, thumps) never alert other zombies.
    if instanceof(source, "IsoZombie") then return end

    local now = getTimestampMs()

    -- Any player noise breaks the "silence" needed to escape TACTILE_COMBAT.
    if instanceof(source, "IsoPlayer") then
        Sound.lastPlayerMs = now
    end

    if x == nil or y == nil or radius == nil then return end
    if radius < Config.MinSoundRadius then return end

    local r = radius * Config.HearingMultiplier
    if r <= 0 then return end

    local seq = Sound.seq + 1
    Sound.seq = seq
    local i = (seq - 1) % SIZE + 1

    sx[i] = mathFloor(x)
    sy[i] = mathFloor(y)
    sz[i] = mathFloor(z or 0)
    sr2[i] = r * r
    svol[i] = tonumber(volume) or radius
    st[i] = now
end

Events.OnWorldSound.Add(onWorldSound)
