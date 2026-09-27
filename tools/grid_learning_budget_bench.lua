-- How much map *learning* can the byte-grid afford before the GC tail comes back?
--
-- The base image is 30 MB of immutable strings and is GC-invisible. Learned cells
-- go into an integer-keyed overlay, which IS live GC data. This measures the knee.
-- Each scenario runs with nothing else alive so the heap figure is the real one.
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

local Grid = dofile(TOOLSDIR .. "/grid_proto.lua")

local function mb() return collectgarbage("count") / 1024 end
local function settle() collectgarbage("collect"); collectgarbage("collect") end
local function clk() return hrtime() * 1000 end

local list = {}
for cx = -8, 8 do
	for cy = -8, 8 do
		list[#list + 1] = { cx = cx, cy = cy, path = BINMAP .. "/chunk_" .. cx .. "_" .. cy .. ".bin" }
	end
end

-- A realistic learning stream: writes are concentrated along a flight path in a
-- small z band, which is what RecordObstacleScan actually produces (32 rays in a
-- ~60 m sphere, every 0.2 s). Cells that already match the base are rejected by
-- set() and cost nothing, so `new` counts only genuine new knowledge.
local function learn(g, n_cells, seed)
	math.randomseed(seed)
	local t = clk()
	local new = 0
	local x, y, z = 0, 0, 40
	for i = 1, n_cells do
		if i % 200 == 0 then
			x = math.random(-290, 110); y = math.random(-320, 360); z = math.random(1, 88)
		else
			x = x + math.random(-4, 4); y = y + math.random(-4, 4); z = z + math.random(-1, 1)
		end
		local v = (i % 4 == 0) and g.DANGER or g.BLOCKED
		if g:set(x, y, z, v) then new = new + 1 end
	end
	return clk() - t, new
end

local probe = {}
math.randomseed(3)
for i = 1, 400 do
	probe[i] = { math.random(-290, 110), math.random(-320, 360), math.random(1, 88) }
end

local function gc_tail(label)
	settle()
	local live = mb()
	collectgarbage("setpause", 110)
	collectgarbage("setstepmul", 150)
	local times = {}
	for it = 1, 20000 do
		local s = clk()
		local junk = string.rep("x", 262144)     -- 256 KB/tick interop garbage
		local hits = 0
		for i = 1, #probe do
			local q = probe[i]
			if CUR_GET(q[1], q[2], q[3]) ~= 0 then hits = hits + 1 end
		end
		if hits == -1 or #junk == -1 then hits = hits end
		times[it] = clk() - s
	end
	collectgarbage("setpause", 250)
	collectgarbage("setstepmul", 5)
	table.sort(times)
	local function pct(p) return times[math.min(#times, math.max(1, math.floor(#times * p)))] end
	local over8 = 0
	for _, v in ipairs(times) do if v >= 8 then over8 = over8 + 1 end end
	print(string.format("  %-30s %6.1f MB | p50 %.2f p99 %5.2f p99.9 %6.2f max %6.2f | >=8ms %.2f%%",
		label, live, pct(.5), pct(.99), pct(.999), times[#times], 100.0 * over8 / #times))
end

print("learning budget of the byte grid (GC 110/150, 256 KB alloc/tick, 20000 ticks)")
print("  base image = 30 MB immutable strings; overlay = learned cells only\n")

-- Scenario 0: base image only, no learning at all.
local g = Grid:New()
g:load_all(list)
CUR_GET = function(a, b, c) return g:get(a, b, c) end
gc_tail("base only (no learning)")

-- Growing overlay: each scenario starts from a clean process-level state by
-- dropping the previous grid first.
for _, target in ipairs({ 50000, 200000, 500000, 1000000 }) do
	g = nil
	settle()
	g = Grid:New()
	g:load_all(list)
	CUR_GET = function(a, b, c) return g:get(a, b, c) end
	local base = mb()
	local t, new = learn(g, target * 2, 42 + target)
	local pend = 0
	for _, c in pairs(g.chunks) do pend = pend + (c.ov_n or 0) end
	print(string.format("  learned %7d new cells in %6.0f ms (%.0f ns/write), overlay delta %.1f MB",
		new, t, t * 1e6 / math.max(new, 1), mb() - base))
	gc_tail(string.format("overlay %7d cells", new))
end
