-- Performance of the SHIPPED full-residency path through the real
-- Navigation/ObstacleGrid code.
--
-- Takes a MODE so each representation is measured in a clean process: sharing a
-- process makes the GC state of the second run depend on the first one's 180 MB
-- of freed tables, which swamps the effect being measured.
--
--   MODE = "legacy"  Data/map v3 text  -> obstacle_map tables
--   MODE = "packed"  Data/map_bin v4   -> resident base image
--
-- Run with:  python tools/run_full_residency_bench.py
local MODDIR, TEXTMAP, BINMAP, EMPTYMAP, MODE = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end
local gpos = Vector4.new(100, 100, 50, 1)
Game = { GetPlayer = function() return { GetWorldPosition = function() return gpos end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
	debug_profile_autopilot = false, user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false,
	                          astar_calculation_precision = 100 },
	is_debug_mode = false, debug_enable_obstacle_scan = false }
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

local function preload(name)
	local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
	local b = f:read("*a")
	f:close()
	package.preload[name] = (loadstring or load)(b, name)
end
preload("Etc/log.lua"); preload("Etc/utils.lua")
preload("Modules/obstacle_grid.lua"); preload("Modules/profprobe.lua"); preload("Modules/navigation.lua")
Log = require("Etc/log.lua")
local Navigation = require("Modules/navigation.lua")

local function mb() return collectgarbage("count") / 1024 end
local function settle() collectgarbage("collect"); collectgarbage("collect") end
local function clk() return hrtime() * 1000 end
local function pct(s, p) return s[math.min(#s, math.max(1, math.floor(#s * p)))] end

local function row(label, live, times)
	table.sort(times)
	local o8, o16 = 0, 0
	for _, v in ipairs(times) do
		if v >= 8 then o8 = o8 + 1 end
		if v >= 16 then o16 = o16 + 1 end
	end
	print(string.format("  %s %7.1f MB | p50 %5.2f p90 %5.2f p99 %6.2f p99.9 %6.2f max %7.2f | >=8ms %5.2f%% >=16ms %5.2f%%",
		label, live, pct(times, .5), pct(times, .9), pct(times, .99),
		pct(times, .999), times[#times], 100 * o8 / #times, 100 * o16 / #times))
end

local packed = (MODE == "packed")
local nav
do
	local t = Navigation:New({ core_obj = { log_obj = Log:New() }, log_obj = Log:New() })
	t.obstacle_map_dir = packed and BINMAP or TEXTMAP
	t.obstacle_map_bin_dir = packed and BINMAP or EMPTYMAP
	t.obstacle_map_path = (packed and BINMAP or TEXTMAP) .. "/none.dat"
	t:ReleaseObstacleMapSessionCache()
	local core_obj = { log_obj = Log:New() }
	local av = { core_obj = core_obj, log_obj = Log:New(), is_auto_pilot = true }
	core_obj.av_obj = av
	nav = Navigation:New(av)
	nav.obstacle_map_dir = packed and BINMAP or TEXTMAP
	nav.obstacle_map_bin_dir = packed and BINMAP or EMPTYMAP
	nav.obstacle_map_path = (packed and BINMAP or TEXTMAP) .. "/none.dat"
end

print(string.format("=== MODE = %s ===", MODE))
settle()
local base = mb()
local t0 = clk()
nav:LoadObstacleMap()
local load_ms = clk() - t0
settle()
local live = mb() - base
print(string.format("  load %7.0f ms | map heap %7.1f MB | full residency %s | chunks %d | known %d",
	load_ms, live, tostring(nav:IsFullResidencyActive()),
	nav.obstacle_grid.chunk_n, nav.obstacle_grid.cells_known))

-- Query stream. Built as four parallel number arrays rather than 400k small
-- tables: the tables would themselves be several MB of live data and would show
-- up in every GC row.
math.randomseed(99)
local N = 400000
local wx, wy, wz = {}, {}, {}
local x, y, z = 100, 100, 40
for i = 1, N do
	if i % 500 == 0 then
		x = math.random(-290, 110); y = math.random(-320, 360); z = math.random(1, 88)
	else
		x = x + math.random(-3, 3); y = y + math.random(-3, 3); z = z + math.random(-2, 2)
	end
	wx[i] = x; wy[i] = y; wz[i] = z
end
settle()

local lookup
if packed then
	lookup = function(a, b, c) return nav:CellStateAtKey(nav:PackCellKey(a, b, c)) end
else
	lookup = function(a, b, c) return nav.obstacle_map[nav:PackCellKey(a, b, c)] end
end

print("  GC tail (20000 ticks, 400 map reads each)")
for _, p in ipairs({ { 250, 5 }, { 110, 150 } }) do
	for _, bpt in ipairs({ 65536, 262144 }) do
		settle()
		collectgarbage("setpause", p[1])
		collectgarbage("setstepmul", p[2])
		local lv = mb()
		local times = {}
		for it = 1, 20000 do
			local s = clk()
			local junk = string.rep("x", bpt)
			local hits = 0
			local off = (it * 7) % N
			for k = 1, 400 do
				local j = ((off + k) % N) + 1
				if lookup(wx[j], wy[j], wz[j]) ~= nil then hits = hits + 1 end
			end
			if hits == -1 or #junk == -1 then hits = hits end
			times[it] = clk() - s
		end
		collectgarbage("setpause", 250)
		collectgarbage("setstepmul", 5)
		row(string.format("    GC %3d/%-3d alloc=%3dKB", p[1], p[2], bpt / 1024), lv, times)
	end
end

-- Read throughput
settle()
local t = clk()
local acc = 0
for i = 1, N do
	local v = lookup(wx[i], wy[i], wz[i])
	if v == true then acc = acc + 3
	elseif v == "danger" then acc = acc + 2
	elseif v == false then acc = acc + 1 end
end
local dt = clk() - t
if acc == -1 then print("x") end
print(string.format("  read throughput  %8.2f M ops/s  %5.0f ns/op", N / dt / 1000, dt * 1e6 / N))

-- A*
local routes = {
	{ Vector4.new(100, 100, 50, 1),    Vector4.new(-2610, 150, 50, 1), "2.8 km" },
	{ Vector4.new(1000, -3000, 60, 1), Vector4.new(-3000, 3000, 60, 1), "6.4 km" },
	{ Vector4.new(0, 0, 80, 1),        Vector4.new(-2900, 3500, 40, 1), "4.6 km" },
}
for _, r in ipairs(routes) do
	settle()
	local s = clk()
	local rt = nav:PlanGlobalRoute(r[1], r[2])
	print(string.format("  A* %-8s %7.1f ms  %4d nodes", r[3], clk() - s, #rt))
end
print("")
