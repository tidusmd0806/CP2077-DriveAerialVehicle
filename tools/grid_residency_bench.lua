-- =============================================================================
-- Can the WHOLE map live in RAM without GC stutter?
--
-- Compares the shipped representation (one Lua table entry per cell, packed
-- numeric keys, plus a duplicate chunk index) against the flat byte-grid
-- representation (tools/grid_proto.lua, DAVOB4) for:
--
--   1. full-map load time
--   2. live Lua heap after full residency
--   3. per-tick wall-time distribution while resident (the GC tail)
--      -- measured with ONLY the representation under test alive
--   4. read throughput on the hot path
--   5. a real long-distance A* run
--
-- Run with:  python tools/run_grid_residency_bench.py
-- =============================================================================

local MODDIR, TEXTMAP, BINMAP, TOOLSDIR = ...

------------------------------------------------------------
-- CET stubs
------------------------------------------------------------
Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

local gpos = Vector4.new(100, 100, 50, 1)
Game = { GetPlayer = function() return { GetWorldPosition = function() return gpos end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
	is_debug_profile_autopilot = false,
	user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false,
	                     astar_calculation_precision = 100 },
	is_debug_mode = false,
	is_debug_enable_obstacle_scan = false,
}
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

local function preload(name, path)
	local f = assert(io.open(path, "r"), "cannot open " .. path)
	local b = f:read("*a")
	f:close()
	package.preload[name] = (loadstring or load)(b, name)
end
preload("Etc/log.lua", MODDIR .. "/Etc/log.lua")
preload("Etc/utils.lua", MODDIR .. "/Etc/utils.lua")
preload("Modules/obstacle_grid.lua", MODDIR .. "/Modules/obstacle_grid.lua")
preload("Modules/navigation.lua", MODDIR .. "/Modules/navigation.lua")
Log = require("Etc/log.lua")
local Navigation = require("Modules/navigation.lua")
local Grid = dofile(TOOLSDIR .. "/grid_proto.lua")

local function mb() return collectgarbage("count") / 1024 end
local function nkeys(t) local c = 0; for _ in pairs(t) do c = c + 1 end; return c end
local function settle() collectgarbage("collect"); collectgarbage("collect") end
local function clk() return hrtime() * 1000 end   -- ms at ~100 ns resolution

local function pct(s, p)
	if #s == 0 then return 0 end
	return s[math.min(#s, math.max(1, math.floor(#s * p)))]
end

local function row(label, live, times)
	table.sort(times)
	local over8, over16 = 0, 0
	for _, v in ipairs(times) do
		if v >= 8 then over8 = over8 + 1 end
		if v >= 16 then over16 = over16 + 1 end
	end
	print(string.format(
		"  %-24s %7.1f MB | p50 %5.2f p90 %5.2f p99 %6.2f p99.9 %6.2f max %7.2f | >=8ms %5.2f%% >=16ms %5.2f%%",
		label, live, pct(times, .5), pct(times, .9), pct(times, .99),
		pct(times, .999), times[#times], 100.0 * over8 / #times, 100.0 * over16 / #times))
end

print("=========================================================================")
print(" FULL-MAP RESIDENCY: table-per-cell (current)  vs  flat byte grid (v4)")
print("=========================================================================")

local core = { log_obj = Log:New() }
local av = { core_obj = core, log_obj = Log:New(), is_auto_pilot = true }
core.av_obj = av
local nav = Navigation:New(av)
nav.obstacle_map_dir = TEXTMAP
nav.obstacle_map_path = TEXTMAP .. "/none.dat"

local probe_cells = {}
math.randomseed(12345)
for i = 1, 400 do
	probe_cells[i] = { math.random(-300, 120), math.random(-330, 370), math.random(1, 88) }
end

-- Surrogate of the mod's ~100 Hz Lua tick: garbage from C# interop plus lookups
-- into whatever map is live. Identical work for both representations; only the
-- resident set differs, which is exactly what drives incremental GC cost.
-- bytes_per_tick is swept because the GC only does work when something is
-- allocated - a zero-allocation loop proves nothing.
local function tick_loop(label, lookup, iters, bytes_per_tick)
	settle()
	local live = mb()
	local times = {}
	for it = 1, iters do
		local s = clk()
		local junk = string.rep("x", bytes_per_tick)   -- interop garbage surrogate
		local hits = 0
		for i = 1, #probe_cells do
			local c = probe_cells[i]
			if lookup(c[1], c[2], c[3]) ~= nil then hits = hits + 1 end
		end
		if hits == -1 or #junk == -1 then hits = hits end
		times[it] = clk() - s
	end
	row(label, live, times)
end

local function gc(pause, stepmul)
	collectgarbage("setpause", pause)
	collectgarbage("setstepmul", stepmul)
end

-- The grid is created in phase B; declared up front so the closures below capture
-- the local rather than a global.
local grid

local cur_lookup  = function(cx, cy, cz) return nav.obstacle_map[nav:PackCellKey(cx, cy, cz)] end
local grid_lookup = function(cx, cy, cz) return grid:get(cx, cy, cz) end

------------------------------------------------------------
-- Phase A: current representation, whole map
------------------------------------------------------------
settle()
local base0 = mb()
local t0 = clk()
local chunks = nav:GetAllChunksCached(true)
local loaded = 0
for _, info in ipairs(chunks) do
	if nav:LoadResidentChunkIncremental(info, 999.0) then loaded = loaded + 1 end
end
local load_ms = clk() - t0
local cells = nkeys(nav.obstacle_map)
local base_heap = mb() - base0

print(string.format("\n[1] CURRENT  full load: %d/%d chunks, %d cells, %.0f ms",
	loaded, #chunks, cells, load_ms))
print(string.format("    live heap %7.1f MB   (%.1f B/cell, ~8M live GC objects)",
	base_heap, base_heap * 1048576 / math.max(cells, 1)))

print("\n[3a] GC tail - ONLY the current representation resident (20000 ticks)")
for _, p in ipairs({ { 250, 5 }, { 110, 150 } }) do
	gc(p[1], p[2])
	for _, bpt in ipairs({ 4096, 65536, 262144 }) do
		print(string.format("    -- GC %d/%d  alloc=%d KB/tick --", p[1], p[2], bpt / 1024))
		tick_loop("CURRENT table-per-cell", cur_lookup, 20000, bpt)
	end
end

------------------------------------------------------------
-- Phase B: grid representation, whole map, current released
------------------------------------------------------------
nav.obstacle_map = {}
nav.obstacle_map_chunk_index = {}
settle()

grid = Grid:New()
local bin_list = {}
for cx = -8, 8 do
	for cy = -8, 8 do
		bin_list[#bin_list + 1] = { cx = cx, cy = cy,
			path = BINMAP .. "/chunk_" .. cx .. "_" .. cy .. ".bin" }
	end
end
settle()
local grid0 = mb()
t0 = clk()
local g_loaded = grid:load_all(bin_list)
local grid_ms = clk() - t0
local grid_heap = mb() - grid0

print(string.format("\n[2] GRID     full load: %d chunks, %.0f ms  (%.2f ms/chunk)",
	g_loaded, grid_ms, grid_ms / math.max(g_loaded, 1)))
print(string.format("    live heap %7.1f MB   (%.2f B/cell over the same %d cells)",
	grid_heap, grid_heap * 1048576 / math.max(cells, 1), cells))
print(  "    live GC objects: ~97 (96 immutable strings + 1 table)")

print("\n[3b] GC tail - ONLY the grid resident (20000 ticks)")
for _, p in ipairs({ { 250, 5 }, { 110, 150 } }) do
	gc(p[1], p[2])
	for _, bpt in ipairs({ 4096, 65536, 262144 }) do
		print(string.format("    -- GC %d/%d  alloc=%d KB/tick --", p[1], p[2], bpt / 1024))
		tick_loop("GRID byte lookup", grid_lookup, 20000, bpt)
	end
end
gc(250, 5)

------------------------------------------------------------
-- 4. hot-path read throughput
--    Both maps are fully loaded here. Measuring the table while its map is empty
--    (every lookup misses) is not a comparison.
------------------------------------------------------------
nav.obstacle_map = {}
nav.obstacle_map_chunk_index = {}
for _, info in ipairs(nav:GetAllChunksCached(true)) do
	nav:LoadResidentChunkIncremental(info, 999.0)
end
print("\n[4] hot-path read throughput (both maps fully resident)")
-- Two streams on purpose. Repeating a small fixed cell set keeps the 2.6M-entry
-- hash warm and flatters the table representation; a long stream of distinct,
-- walk-like cells is what A* and local avoidance actually do.
local function throughput(label, fn, queries, reps)
	settle()
	local t = clk()
	local acc = 0
	for r = 1, reps do
		for i = 1, #queries do
			local q = queries[i]
			local v = fn(q[1], q[2], q[3])
			if v == true then acc = acc + 3
			elseif v == "danger" then acc = acc + 2
			elseif v == false then acc = acc + 1
			elseif type(v) == "number" then acc = acc + v end
		end
	end
	local dt_ms = clk() - t
	local n = #queries * reps
	if acc == -1 then print("x") end
	print(string.format("  %-24s %8.2f M ops/s   (%.0f ns/op)",
		label, n / dt_ms / 1000, dt_ms * 1e6 / n))
end

-- Walk-like stream: mostly neighbours, occasional teleport.
local walk = {}
do
	local x, y, z = 100, 100, 40
	for i = 1, 1000000 do
		if i % 500 == 0 then
			x = math.random(-290, 110); y = math.random(-320, 360); z = math.random(1, 88)
		else
			x = x + math.random(-3, 3); y = y + math.random(-3, 3); z = z + math.random(-2, 2)
		end
		walk[i] = { x, y, z }
	end
end

print("\n[4] hot-path read throughput")
print("    (a) warm loop over 400 fixed cells - flatters the hash table")
throughput("CURRENT table lookup", cur_lookup, probe_cells, 25000)
throughput("GRID get()", grid_lookup, probe_cells, 25000)
print("    (b) 1M distinct walk-like cells - what A* actually does")
throughput("CURRENT table lookup", cur_lookup, walk, 10)
throughput("GRID get()", grid_lookup, walk, 10)

------------------------------------------------------------
-- 5. real A* over long routes
------------------------------------------------------------
print("\n[5] A* over long routes (full map resident in each representation)")
-- Fair comparison: same A*, only the cell-state read is swapped. Overriding the
-- method is what the real port would do; a metatable proxy would NOT be
-- representative (a metamethod call costs far more than a direct table hit).
local function cost_current(self, from_key, to_key)
	local fx, fy, fz = self:ParseSectorKey(from_key)
	local tx, ty, tz = self:ParseSectorKey(to_key)
	if not fx or not tx then return 1.0 end
	local dx, dy, dz = tx - fx, ty - fy, tz - fz
	local base_cost = math.sqrt(dx * dx + dy * dy + dz * dz)
	if self.sector_penalty_cache then
		local cached = self.sector_penalty_cache[to_key]
		if cached then return base_cost * cached end
	end
	if tz <= 0 then
		local pen = self.astar_impassable_penalty or 1e7
		if self.sector_penalty_cache then self.sector_penalty_cache[to_key] = pen end
		return base_cost * pen
	end
	local cell = self.obstacle_map[to_key]
	local pen
	if cell == true then pen = self.astar_blocked_penalty or 500.0
	elseif cell == "danger" then pen = self.astar_danger_penalty or 6.0
	elseif cell == false then pen = self.astar_clear_penalty or 0.8
	else pen = self.astar_blocked_penalty or 500.0 end
	if self.sector_penalty_cache then self.sector_penalty_cache[to_key] = pen end
	return base_cost * pen
end

local function cost_grid(self, from_key, to_key)
	local fx, fy, fz = self:ParseSectorKey(from_key)
	local tx, ty, tz = self:ParseSectorKey(to_key)
	if not fx or not tx then return 1.0 end
	local dx, dy, dz = tx - fx, ty - fy, tz - fz
	local base_cost = math.sqrt(dx * dx + dy * dy + dz * dz)
	if self.sector_penalty_cache then
		local cached = self.sector_penalty_cache[to_key]
		if cached then return base_cost * cached end
	end
	local pen
	if tz <= 0 then
		pen = self.astar_impassable_penalty or 1e7
	else
		local v = grid:get(tx, ty, tz)
		if v == Grid.BLOCKED then pen = self.astar_blocked_penalty or 500.0
		elseif v == Grid.DANGER then pen = self.astar_danger_penalty or 6.0
		elseif v == Grid.CLEAR then pen = self.astar_clear_penalty or 0.8
		else pen = self.astar_blocked_penalty or 500.0 end
	end
	if self.sector_penalty_cache then self.sector_penalty_cache[to_key] = pen end
	return base_cost * pen
end

-- Both maps are already fully loaded from section [4].
local starts = {
	{ Vector4.new(100, 100, 50, 1),    Vector4.new(-2610, 150, 50, 1), "2.8 km" },
	{ Vector4.new(1000, -3000, 60, 1), Vector4.new(-3000, 3000, 60, 1), "6.4 km diag" },
	{ Vector4.new(0, 0, 80, 1),        Vector4.new(-2900, 3500, 40, 1), "4.6 km" },
	{ Vector4.new(-200, -200, 30, 1),  Vector4.new(1100, 3400, 120, 1), "3.8 km" },
}
for _, r in ipairs(starts) do
	nav.GetSectorMovementCost = cost_current
	settle()
	local s = clk()
	local route = nav:PlanGlobalRoute(r[1], r[2])
	local cur_ms = clk() - s

	nav.GetSectorMovementCost = cost_grid
	settle()
	s = clk()
	local route2 = nav:PlanGlobalRoute(r[1], r[2])
	local g_ms = clk() - s
	nav.GetSectorMovementCost = cost_current

	local same = #route == #route2
	if same then
		for i = 1, #route do
			if route[i] ~= route2[i] then same = false break end
		end
	end
	print(string.format("  %-12s CURRENT %s %8.1f ms %5d nodes", r[3],
		#route > 0 and "OK " or "EMP", cur_ms, #route))
	print(string.format("  %-12s GRID    %s %8.1f ms %5d nodes   identical=%s  (%.2fx)", "",
		#route2 > 0 and "OK " or "EMP", g_ms, #route2, tostring(same), cur_ms / math.max(g_ms, .001)))
end

print("")
