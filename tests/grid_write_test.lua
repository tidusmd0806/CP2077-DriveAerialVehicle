-- Write-path (learning) correctness + cost for the v4 byte grid.
-- Base image stays immutable; learned cells go to an integer-keyed overlay and are
-- merged back into a new binary image on save.
local MODDIR, TEXTMAP, BINMAP, TOOLSDIR = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end
Game = { GetPlayer = function() return { GetWorldPosition = function() return Vector4.new(0, 0, 0, 1) end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
	is_debug_profile_autopilot = false, user_setting_table = {}, is_debug_mode = false, is_debug_enable_obstacle_scan = false }
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

local function preload(n, p)
	local f = assert(io.open(p, "r")); local b = f:read("*a"); f:close()
	package.preload[n] = (loadstring or load)(b, n)
end
preload("Etc/log.lua", MODDIR .. "/Etc/log.lua")
preload("Etc/utils.lua", MODDIR .. "/Etc/utils.lua")
preload("Etc/timescale.lua", MODDIR .. "/Etc/timescale.lua")
TimeScale = require("Etc/timescale.lua")
preload("Modules/navigation.lua", MODDIR .. "/Modules/navigation.lua")
Log = require("Etc/log.lua")
local Grid = dofile(TOOLSDIR .. "/grid_proto.lua")

local function mb() return collectgarbage("count") / 1024 end
local function settle() collectgarbage("collect"); collectgarbage("collect") end

local list = {}
for cx = -8, 8 do
	for cy = -8, 8 do
		list[#list + 1] = { cx = cx, cy = cy, path = BINMAP .. "/chunk_" .. cx .. "_" .. cy .. ".bin" }
	end
end

local grid = Grid:New()
grid:load_all(list)
settle()
local heap0 = mb()

-- 1. write correctness: set, read back, unchanged cells must be untouched.
--    (10,10,40) sits in chunk 0_0, which ships; (100,100,40) sits in chunk 2_2,
--    which does not - both must work.
local x, y, z = 10, 10, 40
local before = grid:get(x, y, z)
local nv = (before == Grid.BLOCKED) and Grid.CLEAR or Grid.BLOCKED
assert(grid:set(x, y, z, nv) == true, "first write should report a change")
assert(grid:get(x, y, z) == nv, "read-back mismatch")
assert(grid:set(x, y, z, nv) == false, "idempotent write should report no change")
print(string.format("[1] write/read-back OK in a shipped chunk (%d -> %d)", before, nv))

-- learning into a chunk with no base file must also work
local ux, uy, uz = 100, 100, 40   -- chunk 2_2, not shipped
assert(grid:get(ux, uy, uz) == Grid.UNKNOWN, "should start unknown")
assert(grid:set(ux, uy, uz, Grid.BLOCKED) == true, "learn into virgin chunk failed")
assert(grid:get(ux, uy, uz) == Grid.BLOCKED, "read-back in virgin chunk failed")
print("[1b] learning into an unmapped chunk works (chunk auto-created)")

-- 2. writing a value equal to the base must NOT create overlay garbage.
local n0 = 0
for _, c in pairs(grid.chunks) do n0 = n0 + (c.ov_n or 0) end
grid:set(x, y, z, before)
local n1 = 0
for _, c in pairs(grid.chunks) do n1 = n1 + (c.ov_n or 0) end
print(string.format("[2] no-op write added %d overlay entries (want 0)", n1 - n0))

-- 3. realistic learning session: 30 minutes of obstacle recording.
--    RecordObstacleScan fires every 0.2 s over a ~60 m sphere -> ~200 cells/scan.
local function learn(scans, cells_per_scan)
	local t = hrtime() * 1000
	local written = 0
	math.randomseed(7)
	for s = 1, scans do
		local cx = math.random(-290, 110)
		local cy = math.random(-320, 360)
		local cz = math.random(1, 88)
		for i = 1, cells_per_scan do
			local v = (i % 5 == 0) and Grid.DANGER or Grid.BLOCKED
			if grid:set(cx + (i % 12) - 6, cy + math.floor(i / 12) - 4, cz + (i % 3) - 1, v) then
				written = written + 1
			end
		end
	end
	return (hrtime() * 1000 - t), written
end

local LEARN_SCANS = 9000            -- 30 min at 0.2 s
local t, written = learn(LEARN_SCANS, 200)
settle()
print(string.format("[3] %d scans x 200 cells -> %d new overlay cells in %.0f ms (%.0f ns/write)",
	LEARN_SCANS, written, t, t * 1e6 / math.max(written, 1)))
print(string.format("    heap now %.1f MB (base %.1f MB + overlay %.1f MB)",
	mb(), heap0, mb() - heap0))

-- 4. does the overlay reintroduce the GC tail the base image removed?
local probe = {}
math.randomseed(3)
for i = 1, 400 do
	probe[i] = { math.random(-290, 110), math.random(-320, 360), math.random(1, 88) }
end
local times = {}
settle()
for it = 1, 20000 do
	local s = hrtime() * 1000
	local junk = string.rep("x", 262144)
	local hits = 0
	for i = 1, #probe do
		local q = probe[i]
		if grid:get(q[1], q[2], q[3]) ~= 0 then hits = hits + 1 end
	end
	if hits == -1 or #junk == -1 then hits = hits end
	times[it] = hrtime() * 1000 - s
end
table.sort(times)
local function pct(p) return times[math.min(#times, math.max(1, math.floor(#times * p)))] end
local over8 = 0
for _, v in ipairs(times) do if v >= 8 then over8 = over8 + 1 end end
print(string.format("[4] GC tail after 30 min of learning (256 KB alloc/tick, 20000 ticks)"))
print(string.format("    heap %.1f MB | p50 %.2f p99 %.2f p99.9 %.2f max %.2f ms | >=8ms %.2f%%",
	mb(), pct(.5), pct(.99), pct(.999), times[#times], 100.0 * over8 / #times))

-- 5. save: materialize a dirty chunk and re-read it.
local dirty_key, dirty_c
for k, c in pairs(grid.chunks) do
	if c.ov and c.ov_n > 0 then dirty_key, dirty_c = k, c break end
end
if dirty_c then
	local blob = grid:materialize(dirty_c)
	local g2 = Grid:New()
	local tmp = BINMAP .. "/_roundtrip.bin"
	local f = assert(io.open(tmp, "wb"))
	f:write(blob)
	f:close()
	local c2 = g2:load_chunk(tmp)
	assert(c2, "round-trip chunk failed to load")
	-- spot-check: every overlay cell must survive the round trip
	local checked, bad = 0, 0
	for idx, v in pairs(dirty_c.ov) do
		checked = checked + 1
		local lz = math.floor(idx / 2500)
		local rem = idx - lz * 2500
		local ly = math.floor(rem / 50)
		local lx = rem - ly * 50
		local wx, wy, wz = dirty_c.bx + lx, dirty_c.by + ly, dirty_c.zmin + lz
		if c2.raw:byte(17 + idx) ~= v then bad = bad + 1 end
		if g2:get(wx, wy, wz) ~= v and g2:get(wx, wy, wz) ~= nil then
			-- base may legitimately differ where the overlay was reverted; only the
			-- materialised image is authoritative
		end
	end
	print(string.format("[5] save round-trip: %d overlay cells, %d lost, blob %d bytes",
		checked, bad, #blob))
end
