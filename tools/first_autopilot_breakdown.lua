-- What exactly does the FIRST autopilot start cost, stage by stage?
-- io.open is instrumented so the syscall count is visible, not just the time.
local MODDIR, TESTMAP = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2) end
local gpos = Vector4.new(-1473, -1009, 46, 1)
Game = { GetPlayer = function() return { GetWorldPosition = function() return gpos end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = { user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false },
        debug_enable_obstacle_scan = false }
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

-- instrument io.open / io.popen
local raw_open, raw_popen = io.open, io.popen
local g_open_count, g_popen_count = 0, 0
io.open = function(path, mode) g_open_count = g_open_count + 1; return raw_open(path, mode) end
io.popen = function(cmd, mode) g_popen_count = g_popen_count + 1; return raw_popen(cmd, mode) end
local function reset_counters() g_open_count, g_popen_count = 0, 0 end
local function since(base_o, base_p) return g_open_count - base_o, g_popen_count - base_p end

local function preload(n)
    local f = assert(raw_open(MODDIR .. "/" .. n, "r")); local b = f:read("*a"); f:close()
    package.preload[n] = load(b, n)
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

local function nkeys(t) local c = 0; for _ in pairs(t) do c = c + 1 end return c end
local function mb() return collectgarbage("count") / 1024 end

local DEST = Vector4.new(-1207, -404, 38, 1)   -- ~1.5 km, as in the real log

print(string.format("route ~1.5km   corridor %.1fms/tick   window %.1fms/tick\n",
    nav.obstacle_route_load_budget_ms, nav.obstacle_map_load_budget_ms))

-- ==== THE CLICK: PrepareRouteChunks is all that runs synchronously ==========
collectgarbage("collect")
reset_counters()
local t0 = os.clock()
local pending = nav:PrepareRouteChunks(gpos, DEST)
local click_ms = (os.clock() - t0) * 1000
local o, p = since(0, 0)
print(string.format("CLICK  PrepareRouteChunks      %7.3f ms   io.open=%d  io.popen=%d   (%d chunks to stream)",
    click_ms, o, p, pending))

-- ==== the silent hover: corridor streaming =================================
reset_counters()
local route_budget = nav.obstacle_route_load_budget_ms / 1000
local route_total, route_ticks = 0, 0
while true do
    local t = os.clock()
    local rem = nav:DrainRouteCorridor(route_budget)
    route_total = route_total + (os.clock() - t) * 1000
    route_ticks = route_ticks + 1
    if rem == 0 then break end
    if route_ticks > 2000 then break end
end
local o2, p2 = since(0, 0)
print(string.format("HOVER  corridor stream        %7.0f ms over %3d ticks = %.2fs   io.open=%d  io.popen=%d",
    route_total, route_ticks, route_ticks * nav.obstacle_route_tick, o2, p2))

-- ==== after departure: the radius window fill =============================
reset_counters()
nav:StartObstacleMapFill()
local win_total, win_ticks = 0, 0
while win_ticks < 4000 do
    local t = os.clock()
    local done = nav:MaintainObstacleMapCache()
    win_total = win_total + (os.clock() - t) * 1000
    win_ticks = win_ticks + 1
    if done then break end
end
local o3, p3 = since(0, 0)
print(string.format("WINDOW radius-%d fill          %7.0f ms over %3d ticks = %.1fs   io.open=%d  io.popen=%d",
    nav.obstacle_map_resident_radius, win_total, win_ticks,
    win_ticks * nav.obstacle_map_preload_tick, o3, p3))
print(string.format("       resident: %d chunks / %d cells, heap %.1f MB",
    nkeys(nav.obstacle_map_chunk_index), nkeys(nav.obstacle_map), mb()))

-- ==== steady state ========================================================
reset_counters()
local idle_total = 0
for _ = 1, 400 do
    local t = os.clock()
    nav:MaintainObstacleMapCache()
    idle_total = idle_total + (os.clock() - t) * 1000
end
local o4, p4 = since(0, 0)
print(string.format("STEADY maintenance          %7.2f ms avg/tick over 400 ticks   io.open=%d  io.popen=%d",
    idle_total / 400, o4, p4))

print(string.format("\nTOTAL first-autopilot: %.0f ms   (corridor %.0f + window %.0f + click %.0f)",
    route_total + win_total + click_ms, route_total, win_total, click_ms))

-- ==== what the old full sweep would have cost on the click ==================
reset_counters()
local t1 = os.clock()
nav:GetAllChunksCached(true)
local sweep_ms = (os.clock() - t1) * 1000
local o5, p5 = since(0, 0)
print(string.format("for reference, full inventory sweep: %.1f ms, io.open=%d", sweep_ms, o5))
print(string.format("click-path reduction: %.1f ms -> %.3f ms  (%.0fx fewer ms), io.open %d -> %d",
    sweep_ms, click_ms, sweep_ms / math.max(click_ms, 0.001), o5, o))
