-- Verify the v4 byte grid agrees with the current table representation, cell by
-- cell, over the whole shipped map. Any mismatch explains divergent A* routes.
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

-- Normalise both sides to a 4-state name and compare.
local function tbl_state(v)
	if v == true then return "BLOCKED" end
	if v == "danger" then return "DANGER" end
	if v == false then return "CLEAR" end
	return "UNKNOWN"
end
local names = { [0] = "UNKNOWN", "CLEAR", "DANGER", "BLOCKED" }
local function grid_state(v) return names[v] or ("BAD:" .. tostring(v)) end

local mismatches, checked = {}, 0
local by_kind = {}
for k, v in pairs(nav.obstacle_map) do
	local x, y, z = nav:UnpackCellKey(k)
	if x then
		checked = checked + 1
		local a, b = tbl_state(v), grid_state(grid:get(x, y, z))
		if a ~= b then
			by_kind[a .. " -> " .. b] = (by_kind[a .. " -> " .. b] or 0) + 1
			if #mismatches < 12 then mismatches[#mismatches + 1] = { x, y, z, a, b } end
		end
	end
end

print(string.format("checked %d cells from the table side", checked))
if checked == 0 then
	print("nothing to compare")
	return
end
print("table-side mismatches: " .. (next(by_kind) and "" or "NONE"))
for k, n in pairs(by_kind) do print(string.format("  %-24s %d", k, n)) end
for _, m in ipairs(mismatches) do
	print(string.format("   e.g. (%d,%d,%d) table=%s grid=%s", m[1], m[2], m[3], m[4], m[5]))
end

-- Reverse direction: every non-UNKNOWN grid cell must exist in the table.
local rev_mismatch, rev_checked = 0, 0
for cx = -8, 8 do
	for cy = -8, 8 do
		local c = grid.chunks[Grid.chunk_key(cx, cy)]
		if c and c.raw then
			local body = #c.raw - 16
			for i = 0, body - 1 do
				local b = c.raw:byte(17 + i)
				if b ~= 0 then
					rev_checked = rev_checked + 1
					local lz = math.floor(i / 2500)
					local rem = i - lz * 2500
					local ly = math.floor(rem / 50)
					local lx = rem - ly * 50
					local x = c.bx + lx
					local y = c.by + ly
					local z = c.zmin + lz
					local a = names[b]
					local bt = tbl_state(nav.obstacle_map[nav:PackCellKey(x, y, z)])
					if a ~= bt then
						rev_mismatch = rev_mismatch + 1
						if rev_mismatch <= 8 then
							print(string.format("  rev (%d,%d,%d) grid=%s table=%s", x, y, z, a, bt))
						end
					end
				end
			end
		end
	end
end
print(string.format("reverse-checked %d non-unknown grid cells, %d mismatches", rev_checked, rev_mismatch))

-- z coverage: does the fixed window clip anything?
local zmin, zmax = math.huge, -math.huge
for k in pairs(nav.obstacle_map) do
	local _, _, z = nav:UnpackCellKey(k)
	if z then if z < zmin then zmin = z end; if z > zmax then zmax = z end end
end
print(string.format("table z range [%s, %s]", tostring(zmin), tostring(zmax)))
