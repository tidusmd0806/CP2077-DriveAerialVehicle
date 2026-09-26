-- What does a FULL map load actually cost with the current packed-key code?
local MODDIR, TESTMAP = ...

Vector4 = {}
function Vector4.new(x,y,z,w) return {x=x,y=y,z=z,w=w or 1} end
function Vector4.Zero() return Vector4.new(0,0,0,1) end
function Vector4.Length(v) return math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) end
function Vector4.Distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local gpos = Vector4.new(100,100,50,1)
Game = { GetPlayer = function() return { GetWorldPosition = function() return gpos end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = { user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false },
        debug_enable_obstacle_scan = false }
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

local function preload(n)
    local f = assert(io.open(MODDIR.."/"..n,"r")); local b = f:read("*a"); f:close()
    package.preload[n] = load(b,n)
end
preload("Etc/log.lua"); preload("Etc/utils.lua"); preload("Modules/navigation.lua")
Log = require("Etc/log.lua")
local Navigation = require("Modules/navigation.lua")

local core = { log_obj = Log:New() }
function core:EnsureObstacleMapPreloadTimer(t) return true end
local av = { core_obj = core, log_obj = Log:New() } core.av_obj = av
local nav = Navigation:New(av)
nav.obstacle_map_dir = TESTMAP
nav.obstacle_map_path = TESTMAP .. "/none.dat"

local function nkeys(t) local c=0; for _ in pairs(t) do c=c+1 end return c end
local function mb() return collectgarbage("count") / 1024 end

-- Load every chunk on disk with an effectively unlimited budget.
collectgarbage("collect"); collectgarbage("collect")
local chunks = nav:GetAllChunksCached(true)
local t0 = os.clock()
local loaded, cells_before = 0, nkeys(nav.obstacle_map)
for _, info in ipairs(chunks) do
    if nav:LoadResidentChunkIncremental(info, 999.0) then loaded = loaded + 1 end
end
local load_ms = (os.clock() - t0) * 1000
local cells = nkeys(nav.obstacle_map)
local heap = mb()

print(string.format("FULL LOAD: %d/%d chunks, %d cells, %.0f ms", loaded, #chunks, cells, load_ms))
print(string.format("  heap total          %.1f MB", heap))
print(string.format("  per cell            %.1f B", heap * 1048576 / math.max(cells,1)))

-- Split: how much is the duplicate chunk index?
local map_only = mb()
nav.obstacle_map_chunk_index = {}
collectgarbage("collect"); collectgarbage("collect")
local map_only_heap = mb()
print(string.format("  obstacle_map only   %.1f MB  (%.1f B/cell)",
    map_only_heap, map_only_heap * 1048576 / math.max(cells,1)))
print(string.format("  chunk index dup   + %.1f MB  (%.1f B/cell)",
    map_only - map_only_heap, (map_only - map_only_heap) * 1048576 / math.max(cells,1)))

-- Restore the index for the query/GC tests below.
nav = Navigation:New(av)
nav.obstacle_map_dir = TESTMAP
nav.obstacle_map_path = TESTMAP .. "/none.dat"
for _, info in ipairs(nav:GetAllChunksCached(true)) do
    nav:LoadResidentChunkIncremental(info, 999.0)
end
collectgarbage("collect"); collectgarbage("collect")
local live = mb()
print(string.format("\nlive heap with full map: %.1f MB", live))

-- Query throughput on the full map.
local k = nav:PositionToSectorKey(Vector4.new(-1200, -400, 40, 1))
local q0 = os.clock(); local n = 0; local sink
for i = 1, 2000000 do
    sink = nav.obstacle_map[k + (i % 7)]
    n = n + 1
end
local qms = (os.clock() - q0) * 1000
print(string.format("  2,000,000 table lookups: %.0f ms  (%.0f k ops/s)", qms, n / qms))

-- GC pressure: a light allocation loop on top of the full-map heap,
-- which is what the 100 Hz autopilot/event loop does.
local worst, over8, samples = 0, 0, {}
for i = 1, 20000 do
    local s = os.clock()
    local junk = { i, i*2, i*3 }                       -- per-tick garbage
    local probe = nav.obstacle_map[k + (i % 11)]
    if junk[1] == -1 then probe = nil end
    local ms = (os.clock() - s) * 1000
    samples[#samples+1] = ms
    if ms > worst then worst = ms end
    if ms >= 8 then over8 = over8 + 1 end
end
table.sort(samples)
local function q(p) return samples[math.min(#samples, math.max(1, math.floor(#samples * p)))] end
print(string.format("\n100Hz-style loop on the %.1f MB heap (20,000 ticks):", live))
print(string.format("  p50 %.2f  p90 %.2f  p99 %.2f  max %.2f ms | >=8ms %.2f%%",
    q(.5), q(.9), q(.99), worst, 100 * over8 / #samples))

-- How long would the load take if spread over the maintenance budget?
for _, b in ipairs({3.0, 8.0, 15.0}) do
    local ticks = math.ceil(load_ms / b)
    print(string.format("spread at %.0fms/tick: %d ticks = %.1fs at 50ms period", b, ticks, ticks * 0.05))
end
