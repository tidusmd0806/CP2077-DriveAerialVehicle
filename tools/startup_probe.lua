-- What actually runs after a load with the MOD enabled?
-- Mirrors: GetAllChunksCached(true) -> resident-window fill -> steady state idle.
local MODDIR, TESTMAP = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local gpos = Vector4.new(100, 100, 50, 1)
Game = { GetPlayer = function() return { GetWorldPosition = function() return gpos end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
    user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false },
    debug_enable_obstacle_scan = false,
}
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

local function preload(n)
    local f = assert(io.open(MODDIR .. "/" .. n, "r")); local b = f:read("*a"); f:close()
    package.preload[n] = load(b, n)
end
preload("Etc/log.lua"); preload("Etc/utils.lua"); preload("Modules/navigation.lua")
Log = require("Etc/log.lua")
local Navigation = require("Modules/navigation.lua")
local core = { log_obj = Log:New() }
function core:EnsureObstacleMapPreloadTimer(tick) return true end
local av = { core_obj = core, log_obj = Log:New() } core.av_obj = av
local nav = Navigation:New(av)
nav.obstacle_map_dir = TESTMAP
nav.obstacle_map_path = TESTMAP .. "/none.dat"

local function nkeys(t) local c = 0; for _ in pairs(t) do c = c + 1 end return c end
local function mb() return collectgarbage("count") / 1024 end
local function stats(name, times)
    table.sort(times)
    local q = function(p) return times[math.min(#times, math.max(1, math.floor(#times * p)))] end
    local over = 0
    for _, v in ipairs(times) do if v >= 8 then over = over + 1 end end
    print(string.format("  %-30s n=%-5d p50 %5.2f  p90 %6.2f  p99 %6.2f  max %7.2f ms | >=8ms %5.2f%%",
        name, #times, q(.5), q(.9), q(.99), times[#times], 100 * over / #times))
end

print(string.format("config: preload_tick=%.2fs  budget=%.1fms  radius=%d\n",
    nav.obstacle_map_preload_tick, nav.obstacle_map_load_budget_ms, nav.obstacle_map_resident_radius))

-- 1. The real SessionStart path. Should now do essentially nothing.
collectgarbage("collect"); collectgarbage("collect")
local t0 = os.clock()
nav:StartObstacleMapSessionPreload()
local ss_ms = (os.clock() - t0) * 1000
print(string.format("1. StartObstacleMapSessionPreload(): %.1f ms, heap %.1f MB, chunks seen=%d",
    ss_ms, mb(), #nav:GetAllChunksCached()))

-- 2. Gate CLOSED: what a general user gets after a load with no autopilot.
--    14 seconds of the 50ms maintenance timer, the window that used to fill here.
local closed_times = {}
for _ = 1, 280 do
    local s = os.clock()
    nav:MaintainObstacleMapCache()
    closed_times[#closed_times + 1] = (os.clock() - s) * 1000
end
print(string.format("2. fill gate CLOSED, 280 ticks (14s of play): %d chunks / %d cells, heap %.1f MB",
    nkeys(nav.obstacle_map_chunk_index), nkeys(nav.obstacle_map), mb()))
stats("gate closed", closed_times)

-- 3. Gate OPEN: first autopilot departure opens it, the window fills.
local f0 = os.clock()
nav:StartObstacleMapFill()
print(string.format("3a. StartObstacleMapFill (lazy inventory): %.1f ms", (os.clock() - f0) * 1000))
local fill_times, wall = {}, 0.0
local ticks = 0
while ticks < 5000 do
    ticks = ticks + 1
    local s = os.clock()
    local done = nav:MaintainObstacleMapCache()
    fill_times[#fill_times + 1] = (os.clock() - s) * 1000
    wall = wall + nav.obstacle_map_preload_tick
    if done then break end
end
print(string.format("3. fill gate OPEN: %d ticks x %.0fms = %.1fs wall, %d chunks / %d cells, heap %.1f MB",
    #fill_times, nav.obstacle_map_preload_tick * 1000, wall,
    nkeys(nav.obstacle_map_chunk_index), nkeys(nav.obstacle_map), mb()))
stats("during fill", fill_times)

-- 3. steady state: what the maintenance timer costs once settled
local idle_times = {}
for _ = 1, 400 do
    local s = os.clock()
    nav:MaintainObstacleMapCache()
    idle_times[#idle_times + 1] = (os.clock() - s) * 1000
end
stats("maintenance, settled", idle_times)

-- 4. the 100 Hz loop's own footprint is not in navigation.lua, but the heap it
--    now lives on is 44 MB. Measure GC step cost on that heap with a light loop.
collectgarbage("collect")
local live = mb()
local gc_times = {}
for _ = 1, 20000 do
    local s = os.clock()
    local junk = { 1, 2, 3 }              -- small per-tick allocation
    local probe = nav.obstacle_map[next(nav.obstacle_map)]
    if junk[1] == -1 then probe = nil end
    gc_times[#gc_times + 1] = (os.clock() - s) * 1000
end
print(string.format("4. light 100Hz-style loop on the %.1f MB heap:", live))
stats("   per-tick", gc_times)
