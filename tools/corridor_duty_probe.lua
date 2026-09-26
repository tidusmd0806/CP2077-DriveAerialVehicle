-- How expensive is the first-autopilot corridor preload, and what does the
-- budget/tick pair actually cost the game thread?
local MODDIR, TESTMAP = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2) end
local gpos = Vector4.new(100, 100, 50, 1)
Game = { GetPlayer = function() return { GetWorldPosition = function() return gpos end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
    user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false },
    debug_enable_obstacle_scan = false,
}
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

local function preload(n)
    local f = assert(io.open(MODDIR .. "/" .. n, "r")); local b = f:read("*a"); f:close()
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

-- Routes roughly matching the real sessions in the log.
local ROUTES = {
    { "0.6 km", Vector4.new(-1209, -406, 10, 1),  Vector4.new(-1150, -350, 38, 1) },
    { "1.5 km", Vector4.new(-1473, -1009, 46, 1), Vector4.new(-1207, -404, 38, 1) },
    { "2.8 km", Vector4.new(-2400, -1800, 40, 1), Vector4.new(400, 600, 38, 1) },
}

-- budget_ms / tick_ms pairs to evaluate. duty = budget / (tick*1000)
local SETTINGS = {
    { "live (current)   ", nil, nil },
    { "old       15ms/20ms", 15.0, 0.02 },
    { "gentle-A   8ms/50ms",  8.0, 0.05 },
    { "gentle-B   4ms/50ms",  4.0, 0.05 },
}

print(string.format("chunk world size = %dm\n",
    nav.obstacle_map_chunk_cells * nav.obstacle_cell_size))
print(string.format("LIVE CONFIG: budget %.1fms / tick %.2fs = %.1f%% duty, timeout %.0fs, cap %d chunks\n",
    nav.obstacle_route_load_budget_ms,
    nav.obstacle_route_tick,
    nav.obstacle_route_load_budget_ms / (nav.obstacle_route_tick * 1000) * 100,
    nav.obstacle_route_wait_timeout,
    nav.obstacle_map_route_max_chunks))

for _, r in ipairs(ROUTES) do
    local label, a, b = r[1], r[2], r[3]
    print("=== " .. label .. " ===")

    -- Measure the raw work: load every corridor chunk with an unlimited budget.
    -- Keep the default resident radius but leave the fill gate closed, so the
    -- corridor chunks really are not resident yet (that is the real case).
    local fresh = Navigation:New(av)
    fresh.obstacle_map_dir = TESTMAP
    fresh.obstacle_map_path = TESTMAP .. "/none.dat"
    fresh:EnsureChunkInventoryFresh()
    local t0 = os.clock()
    local pending = fresh:PrepareRouteChunks(a, b)
    local prep_ms = (os.clock() - t0) * 1000
    local work_ms = 0
    local n = 0
    while true do
        local s = os.clock()
        local rem = fresh:DrainRouteCorridor(10.0)
        work_ms = work_ms + (os.clock() - s) * 1000
        if rem == 0 then break end
        n = n + 1
        if n > 500 then break end
    end
    print(string.format("  corridor: %d chunks queued, prep %.1fms, total parse %.0fms",
        pending, prep_ms, work_ms))

    for _, st in ipairs(SETTINGS) do
        local name = st[1]
        local budget = st[2] or nav.obstacle_route_load_budget_ms
        local tick = st[3] or nav.obstacle_route_tick
        local duty = budget / (tick * 1000) * 100
        local ticks = math.ceil(work_ms / budget)
        local wall = ticks * tick
        local capped = wall > nav.obstacle_route_wait_timeout
        print(string.format("    %-20s duty %5.1f%%  hover %5.2fs%s",
            name, duty, wall, capped and "  (hits the 15s timeout!)" or ""))
    end
    print("")
end
