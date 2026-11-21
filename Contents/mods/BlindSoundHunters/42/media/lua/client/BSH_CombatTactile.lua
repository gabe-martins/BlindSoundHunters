-- BlindSoundHunters - tactile combat
-- TACTILE_COMBAT is entered only by the zombie that was hit/shoved, or by a zombie in
-- direct physical contact (<= 0.85 tiles, same floor). Only that zombie locks onto the
-- player. It lets go when the player is farther than 1.8 tiles AND has been silent.

require "BSH_Config"
require "BSH_SoundListener"

local BSH = BSH
local Config = BSH.Config
local C = BSH.Const
local Sound = BSH.Sound
local instanceof = instanceof
local mathFloor = math.floor

local TACTILE_DIST2 = C.TACTILE_DIST2
local RELEASE_DIST2 = C.RELEASE_DIST2

local Tactile = {}
BSH.Tactile = Tactile

-- True when the zombie physically touches the player (same floor, <= TACTILE_DIST).
-- Called only on the zombie's throttled tick.
function Tactile.checkCollision(zombie, player)
    if mathFloor(zombie:getZ()) ~= mathFloor(player:getZ()) then return false end
    local dx = zombie:getX() - player:getX()
    local dy = zombie:getY() - player:getY()
    return (dx * dx + dy * dy) <= TACTILE_DIST2
end

-- Throttled update for a zombie in TACTILE_COMBAT.
function Tactile.update(zombie, md, player, nowMs)
    if player == nil or player:isDead() then
        BSH.AI.releaseTactile(zombie, md)
        return
    end

    local far
    if mathFloor(zombie:getZ()) ~= mathFloor(player:getZ()) then
        far = true
    else
        local dx = zombie:getX() - player:getX()
        local dy = zombie:getY() - player:getY()
        far = (dx * dx + dy * dy) > RELEASE_DIST2
    end

    if far and (nowMs - Sound.lastPlayerMs) > Config.SilenceMs then
        BSH.AI.releaseTactile(zombie, md)
        return
    end

    -- Keep the lock on this zombie only.
    if zombie:getTarget() ~= player then
        zombie:setTarget(player)
    end
end

local function onHit(zombie, attacker)
    if zombie == nil or attacker == nil then return end
    if not instanceof(zombie, "IsoZombie") then return end
    if not instanceof(attacker, "IsoPlayer") then return end
    if zombie:isDead() then return end
    if BSH.AI == nil then return end
    BSH.AI.enterTactile(zombie, attacker)
end

-- Fires for weapon hits and shoves.
local function onWeaponHitCharacter(wielder, character, handWeapon, damage)
    onHit(character, wielder)
end

-- Extra coverage: some hit paths only raise OnHitZombie.
local function onHitZombie(zombie, attacker, bodyPartType, handWeapon)
    onHit(zombie, attacker)
end

Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
Events.OnHitZombie.Add(onHitZombie)
