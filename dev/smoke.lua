local M = arg[1]
package.path = M.."/shared/?.lua;"..M.."/client/?.lua;"..package.path
local handlers = {}
Events = setmetatable({}, {__index=function(t,k) local e={Add=function(f) handlers[k]=handlers[k] or {}; table.insert(handlers[k], f) end}; rawset(t,k,e); return e end})
local function fire(n, ...) for _,f in ipairs(handlers[n] or {}) do f(...) end end
local clock = 1000000
function getTimestampMs() return clock end
local rnd = 0
function ZombRand(n) rnd = rnd + 1; return rnd % n end
SandboxVars = { BlindSoundHunters = { HearingMultiplier = 1.0, MinSoundRadius = 5, Strength = 1, AlertMemorySeconds = 15, SilenceSeconds = 2 } }
local function opt(v) return {v=v, getValue=function(s) return s.v end, setValue=function(s,x) s.v=x end} end
-- World set to Shambler (3): worst case, doZombieSpeed(1) only sprints if the lore option is swapped.
local lore = { ["ZombieLore.Speed"]=opt(3), ["ZombieLore.Strength"]=opt(2) }
function getSandboxOptions() return {getOptionByName=function(_, n) return lore[n] end} end
local function obj(cls, x, y, z)
  local o = {cls=cls, x=x, y=y, z=z, md={}, dead=false, target=nil, speed=3, strength=nil, paths=0,
             useless=false, vars={}, goal=nil, wanders=0}
  function o:getX() return self.x end function o:getY() return self.y end function o:getZ() return self.z end
  function o:isDead() return self.dead end function o:getModData() return self.md end
  function o:getID() return 7 end
  function o:getTarget() return self.target end function o:setTarget(t) self.target=t end
  function o:setTargetSeenTime(t) end
  function o:isUseless() return self.useless end function o:setUseless(b) self.useless=b end
  function o:setVariable(k, v) self.vars[k]=v end
  function o:setPath2(p) end
  local pfb = {}
  function pfb.isGoalCharacter() return o.goal == "char" end
  function pfb.cancel() o.goal = nil end
  function o:getPathFindBehavior2() return pfb end
  function o:pathToSound(x,y,z) self.paths=self.paths+1; self.px,self.py=x,y; self.goal="sound" end
  function o:pathToLocation(x,y,z) self.wanders=self.wanders+1; self.goal="loc" end
  function o:pathToCharacter(c) self.goal="char" end
  -- Mirrors IsoZombie.doZombieSpeedInternal: shambler if lore==3 or arg==3.
  function o:doZombieSpeed(s) if lore["ZombieLore.Speed"].v==3 or s==3 then self.speed=3 else self.speed=s end end
  -- DoZombieStats reads Strength; speed is re-derived from the current speed type only.
  function o:DoZombieStats() self.strength=lore["ZombieLore.Strength"].v; self:doZombieSpeed(self.speed) end
  return o
end
function instanceof(o, c) return type(o)=="table" and o.cls==c end
local player = obj("IsoPlayer", 50, 50, 0)
function getPlayer() return player end
require "BSH_ZombieAI"
fire("OnGameStart")
local z = obj("IsoZombie", 10, 10, 0)
local function run(n) for i=1,n do clock=clock+16; fire("OnTick"); fire("OnZombieUpdate", z) end end
local function check(c, m) print((c and "PASS " or "FAIL ")..m); if not c then os.exit(1) end end
local S = BSH.State
z.target = player; z.goal = "char"
run(1)
check(z.useless and z.target==nil and z.goal==nil, "first update: blinded (useless), vision target + chase path dropped")
run(10)
check(z.md.BSH_state==S.IDLE_WANDER and z.speed==3 and z.strength==1, "init: IDLE shambler, superhuman")
check(lore["ZombieLore.Speed"].v==3 and lore["ZombieLore.Strength"].v==2, "world lore options restored")
z.useless = false; run(1); check(z.useless, "useless re-applied if something resets it")
fire("OnWorldSound", 15, 15, 0, 3, 3, player); run(10)
check(z.md.BSH_state==S.IDLE_WANDER, "sound below MinSoundRadius ignored")
fire("OnWorldSound", 15, 15, 0, 30, 30, nil); run(10); check(z.md.BSH_state==S.IDLE_WANDER, "nil source ignored")
fire("OnWorldSound", 15, 15, 0, 30, 30, obj("IsoZombie",0,0,0)); run(10); check(z.md.BSH_state==S.IDLE_WANDER, "zombie source ignored")
z.vars.bPathfind = nil
fire("OnWorldSound", 20, 20, 0, 30, 30, player); run(10)
check(z.md.BSH_state==S.ALERT_SPRINT and z.speed==1 and z.px==20, "valid sound -> ALERT sprinter (even in shambler world), pathing")
check(z.vars.bPathfind==true and z.useless, "ALERT: forced pathfind state, still blind")
check(lore["ZombieLore.Speed"].v==3, "world speed restored after sprint swap")
fire("OnWorldSound", 12, 12, 0, 30, 30, player); run(10); check(z.px==12, "higher intensity sound takes priority")
fire("OnWorldSound", 40, 40, 0, 30, 5, player); run(10); check(z.px==12, "weaker sound ignored while sprinting")
z.x, z.y = 12.6, 12.4; run(10); check(z.md.BSH_state==S.IDLE_WANDER and z.speed==3, "arrival -> IDLE shambler")
local w0 = z.wanders; clock = clock + 40000; for i=1,6 do clock=clock+20000; run(5) end
check(z.wanders > w0 and z.md.BSH_state==S.IDLE_WANDER, "IDLE: mod-driven random wander ("..(z.wanders-w0)..")")
fire("OnWorldSound", 20, 20, 0, 30, 30, player); run(10); clock=clock+16000; run(10)
check(z.md.BSH_state==S.IDLE_WANDER, "memory expiry -> IDLE")
player.x, player.y = z.x+0.5, z.y; run(10)
check(z.md.BSH_state==S.TACTILE_COMBAT and z.target==player and not z.useless and z.goal=="char", "collision -> TACTILE lock (vanilla targeting on)")
player.x = z.x+1.0; fire("OnWorldSound", 1, 1, 0, 1, 1, player); clock=clock+3000; run(10)
check(z.md.BSH_state==S.TACTILE_COMBAT and not z.useless, "within 1.8 -> stays locked")
player.x = z.x+3; clock=clock+500; fire("OnWorldSound", 1, 1, 0, 1, 1, player); run(10)
check(z.md.BSH_state==S.TACTILE_COMBAT, "far but noisy -> stays locked")
z.goal = "char"; clock=clock+3000; run(10)
check(z.md.BSH_state==S.IDLE_WANDER and z.target==nil and z.useless and z.goal~="char", "far + silent -> release: blind again, chase cancelled")
fire("OnWeaponHitCharacter", player, z, nil, 1); check(z.md.BSH_state==S.TACTILE_COMBAT and not z.useless, "hit -> TACTILE")
fire("OnZombieDead", z); check(z.md.BSH_state==nil, "death clears state")
print("ALL PASS")
