-- Micro-benchmark of the cell-read hot path. What does each formulation cost?
-- 10M random-but-spatially-local lookups per variant.
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
preload("Modules/navigation.lua", MODDIR .. "/Modules/navigation.lua")
Log = require("Etc/log.lua")
local Navigation = require("Modules/navigation.lua")
local Grid = dofile(TOOLSDIR .. "/grid_proto.lua")

local nav = Navigation:New({ core_obj = { log_obj = Log:New() }, log_obj = Log:New() })
nav.obstacle_map_dir = TEXTMAP
nav.obstacle_map_path = TEXTMAP .. "/none.dat"
for _, info in ipairs(nav:GetAllChunksCached(true)) do
	nav:LoadResidentChunkIncremental(info, 999.0)
end

local grid = Grid:New()
local list = {}
for cx = -8, 8 do
	for cy = -8, 8 do
		list[#list + 1] = { cx = cx, cy = cy, path = BINMAP .. "/chunk_" .. cx .. "_" .. cy .. ".bin" }
	end
end
grid:load_all(list)

-- A walk-like query stream: mostly neighbouring cells, occasional jump. This is
-- what A* neighbour expansion actually looks like, and it is what makes or breaks
-- a chunk cache.
math.randomseed(99)
local Q = {}
local qx, qy, qz = 100, 100, 40
for i = 1, 1000000 do
	if i % 500 == 0 then
		qx = math.random(-290, 110); qy = math.random(-320, 360); qz = math.random(1, 88)
	else
		qx = qx + math.random(-3, 3); qy = qy + math.random(-3, 3); qz = qz + math.random(-2, 2)
	end
	Q[i] = { qx, qy, qz }
end

local SLICE, HDR = 2500, 16
local byte = string.byte

-- Variant A: current representation.
local function v_table(x, y, z)
	return nav.obstacle_map[nav:PackCellKey(x, y, z)]
end

-- Variant B: math.floor + string method (the naive grid).
local function v_naive(x, y, z)
	local c = grid.chunks[((math.floor(x / 50) + 512) * 1024) + (math.floor(y / 50) + 512)]
	if c == nil then return 0 end
	local lz = z - c.zmin
	if lz < 0 or lz >= c.zlevels then return 0 end
	return c.raw:byte(HDR + lz * SLICE + (y - c.by) * 50 + (x - c.bx) + 1)
end

-- Variant C: // + bound byte + 1-entry chunk cache (Grid:get).
local function v_cached(x, y, z)
	return grid:get(x, y, z)
end

-- Variant D: // + bound byte, no chunk cache.
local function v_nocache(x, y, z)
	local c = grid.chunks[((math.floor(x / 50) + 512) * 1024) + (math.floor(y / 50) + 512)]
	if c == nil then return 0 end
	local lz = z - c.zmin
	if lz < 0 or lz >= c.zlevels then return 0 end
	return byte(c.raw, HDR + lz * SLICE + (y - c.by) * 50 + (x - c.bx) + 1)
end

-- Variant E: one global dense image, index is pure arithmetic, no chunk lookup.
-- Built once from the grid; reads are a single string.byte.
local GX, GY, GZ = 1024, 1024, 128   -- covers x,y in [-512,511], z in [0,127]
local XMIN, YMIN, ZMIN = -512, -512, -16
local function build_global()
	local rows = {}
	local total = GZ * GY * GX
	local buf = {}
	for i = 1, total do buf[i] = 0 end
	for _, e in ipairs(list) do
		local c = grid.chunks[Grid.chunk_key(e.cx, e.cy)]
		if c and c.raw then
			for lz = 0, c.zlevels - 1 do
				local gz = c.zmin + lz - ZMIN
				if gz >= 0 and gz < GZ then
					for ly = 0, 49 do
						local gy = c.by + ly - YMIN
						if gy >= 0 and gy < GY then
							local src = HDR + lz * SLICE + ly * 50
							local dst = gz * GY * GX + gy * GX + (c.bx - XMIN) + 1
							for lx = 0, 49 do
								buf[dst + lx] = byte(c.raw, src + lx + 1)
							end
						end
					end
				end
			end
		end
	end
	return table.concat(buf, "")
end

local function bench(label, fn)
	collectgarbage("collect"); collectgarbage("collect")
	local t = hrtime() * 1000
	local acc = 0
	for i = 1, #Q do
		local q = Q[i]
		local v = fn(q[1], q[2], q[3])
		if v == true then acc = acc + 3
		elseif v == "danger" then acc = acc + 2
		elseif v == false then acc = acc + 1
		elseif type(v) == "number" then acc = acc + v end
	end
	local dt = hrtime() * 1000 - t
	print(string.format("  %-38s %7.2f M ops/s  %5.0f ns/op", label, #Q / dt / 1000, dt * 1e6 / #Q))
	if acc == -1 then print("x") end
end

print("read-path micro-benchmark, 1M spatially-local lookups per variant")
bench("A  table lookup (current)", v_table)
bench("B  grid: math.floor + s:byte (naive)", v_naive)
bench("C  grid: // + string.byte + chunk cache", v_cached)
bench("D  grid: // + string.byte, no cache", v_nocache)
