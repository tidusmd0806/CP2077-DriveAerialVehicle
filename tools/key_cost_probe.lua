-- Measure the resident window's live heap, optionally dropping the duplicate
-- chunk index. One mode per process so nothing keeps the dropped table alive.
local MODDIR, TESTMAP, DROP_INDEX = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
Game = { GetPlayer = function() return { GetWorldPosition = function() return Vector4.new(100, 100, 50, 1) end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = { user_setting_table = { garage_info_list = {}, astar_calculation_precision = 100 } }
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end, After = function() return 1 end }

local function preload(n)
    local f = assert(io.open(MODDIR .. "/" .. n, "r")); local b = f:read("*a"); f:close()
    package.preload[n] = load(b, n)
end
preload("Etc/log.lua"); preload("Etc/utils.lua"); preload("Modules/navigation.lua")
Log = require("Etc/log.lua")
local Navigation = require("Modules/navigation.lua")
local core = { log_obj = Log:New() }
local av = { core_obj = core, log_obj = Log:New(), is_auto_pilot = true }
core.av_obj = av
local nav = Navigation:New(av)
nav.obstacle_map_dir = TESTMAP
nav.obstacle_map_path = TESTMAP .. "/none.dat"

local function nkeys(t) local c = 0; for _ in pairs(t) do c = c + 1 end return c end

local it = 0
while it < 6000 do it = it + 1; if nav:MaintainObstacleMapCache() then break end end
local cells = nkeys(nav.obstacle_map)

if DROP_INDEX == "1" then
    -- Clear the session aliases too, or they keep the index alive and the
    -- measurement reads zero.
    nav.obstacle_map_chunk_index = nil
    core.session_obstacle_map_chunk_index = nil
    nav.av_obj = nil
end

collectgarbage("collect"); collectgarbage("collect"); collectgarbage("collect")
local mb = collectgarbage("count") / 1024
print(string.format("%-16s %d cells  %7.1f MB  %6.1f B/cell",
    DROP_INDEX == "1" and "map only" or "map + index", cells, mb, mb * 1048576 / cells))
