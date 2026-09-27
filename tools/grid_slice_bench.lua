-- Single-image grid vs z-slice copy-on-write grid: read cost, write cost, GC tail.
local MODDIR, TEXTMAP, BINMAP, TOOLSDIR = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end
Game = { GetPlayer = function() return { GetWorldPosition = function() return Vector4.new(0, 0, 0, 1) end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
	debug_profile_autopilot = false, user_setting_table = {}, is_debug_mode = false, debug_enable_obstacle_scan = false }
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

local Grid  = dofile(TOOLSDIR .. "/grid_proto.lua")
local Slice = dofile(TOOLSDIR .. "/grid_slice_proto.lua")

local function mb() return collectgarbage("count") / 1024 end
local function settle() collectgarbage("collect"); collectgarbage("collect") end
local function clk() return hrtime() * 1000 end
local function ms() return clk() end

local list = {}
for cx = -8, 8 do
	for cy = -8, 8 do
		list[#list + 1] = { cx = cx, cy = cy, path = BINMAP .. "/chunk_" .. cx .. "_" .. cy .. ".bin" }
	end
end

-- walk-like read stream
math.randomseed(99)
local walk = {}
do
	local x, y, z = 100, 100, 40
	for i = 1, 500000 do
		if i % 500 == 0 then
			x = math.random(-290, 110); y = math.random(-320, 360); z = math.random(1, 88)
		else
			x = x + math.random(-3, 3); y = y + math.random(-3, 3); z = z + math.random(-2, 2)
		end
		walk[i] = { x, y, z }
	end
end

local function read_bench(label, g)
	settle()
	local t = clk()
	local acc = 0
	for i = 1, #walk do
		local q = walk[i]
		acc = acc + g:get(q[1], q[2], q[3])
	end
	local dt = clk() - t
	print(string.format("  %-34s %7.2f M ops/s  %5.0f ns/op   (sum=%d)",
		label, #walk / dt / 1000, dt * 1e6 / #walk, acc))
end

print("=== correctness: slice variant must read identically to the single image ===")
local g1 = Grid:New()
g1:load_all(list)
local g2 = Slice:New()
g2:load_all(list)
local diff = 0
for _, q in ipairs(walk) do
	if g1:get(q[1], q[2], q[3]) ~= g2:get(q[1], q[2], q[3]) then diff = diff + 1 end
end
print("  mismatches over 500k walk cells: " .. diff)

print("\n=== read throughput ===")
read_bench("single image (grid_proto)", g1)
read_bench("z-slice COW (grid_slice_proto)", g2)

-- ---------------------------------------------------------------------------
-- learning: 30 min of obstacle recording, worst case (all cells new)
-- ---------------------------------------------------------------------------
local function learn(g, scans, cells_per_scan, seed)
	math.randomseed(seed)
	local t = clk()
	local written = 0
	for s = 1, scans do
		local cx = math.random(-290, 110)
		local cy = math.random(-320, 360)
		local cz = math.random(1, 88)
		for i = 1, cells_per_scan do
			local v = (i % 5 == 0) and g.DANGER or g.BLOCKED
			if g:set(cx + (i % 12) - 6, cy + math.floor(i / 12) - 4, cz + (i % 3) - 1, v) then
				written = written + 1
			end
		end
	end
	return clk() - t, written
end

local function gc_tail(label, g)
	settle()
	local live = mb()
	local probe = {}
	math.randomseed(3)
	for i = 1, 400 do
		probe[i] = { math.random(-290, 110), math.random(-320, 360), math.random(1, 88) }
	end
	local times = {}
	for it = 1, 20000 do
		local s = clk()
		local junk = string.rep("x", 262144)
		local hits = 0
		for i = 1, #probe do
			local q = probe[i]
			if g:get(q[1], q[2], q[3]) ~= 0 then hits = hits + 1 end
		end
		if hits == -1 or #junk == -1 then hits = hits end
		times[it] = clk() - s
	end
	table.sort(times)
	local function pct(p) return times[math.min(#times, math.max(1, math.floor(#times * p)))] end
	local over8 = 0
	for _, v in ipairs(times) do if v >= 8 then over8 = over8 + 1 end end
	print(string.format("  %-34s %6.1f MB | p50 %.2f p99 %.2f p99.9 %.2f max %6.2f | >=8ms %.2f%%",
		label, live, pct(.5), pct(.99), pct(.999), times[#times], 100.0 * over8 / #times))
end

print("\n=== 30 min worst-case learning (9000 scans x 200 cells, all new) ===")
for _, cm in ipairs({ 64, 512 }) do
	local g = Slice:New()
	g.COMPACT_MIN = cm
	g:load_all(list)
	settle()
	local base = mb()
	local t, w = learn(g, 9000, 200, 11 + cm)
	print(string.format("  COMPACT_MIN=%-4d %d cells learned in %6.0f ms (%5.0f ns/write), %d slice rebuilds",
		cm, w, t, t * 1e6 / math.max(w, 1), g.rebuilds))
	settle()
	print(string.format("    heap base %.1f MB -> %.1f MB (delta %.1f MB), pending cells %d",
		base, mb(), mb() - base, g:pending_cells()))
	gc_tail(string.format("slice COW COMPACT_MIN=%d after learning", cm), g)
end

-- baseline: the unbounded-overlay single-image design, same workload
local g3 = Grid:New()
g3:load_all(list)
settle()
local base3 = mb()
local t3, w3 = learn(g3, 9000, 200, 11 + 64)
print(string.format("  single image + overlay  %d cells learned in %6.0f ms (%5.0f ns/write)",
	w3, t3, t3 * 1e6 / math.max(w3, 1)))
settle()
print(string.format("    heap base %.1f MB -> %.1f MB (delta %.1f MB)", base3, mb(), mb() - base3))
gc_tail("single image + overlay after learning", g3)
