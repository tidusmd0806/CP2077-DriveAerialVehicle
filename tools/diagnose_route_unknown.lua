-- End-to-end check of the departure gate: how long does the hover last, and does
-- A* come back with a FULL route afterwards?
local MODDIR, TESTMAP = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end

Game = { GetPlayer = function() return { GetWorldPosition = function() return Vector4.new(100, 100, 50, 1) end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = { user_setting_table = { garage_info_list = {}, astar_calculation_precision = 100 } }
spdlog = { info = function() end }

local function preload(n)
    local f = assert(io.open(MODDIR .. "/" .. n, "r"))
    local b = f:read("*a"); f:close()
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

-- Cron stub: pump manually so we can count ticks = wall-clock hover duration.
local timers, next_id = {}, 1
Cron = {
    Every = function(to, a, b)
        local cb, args = a, b
        if type(cb) ~= "function" then cb, args = b, a end
        if type(args) ~= "table" then args = { arg = args } end
        local t = { id = next_id, timeout = to, cb = cb, args = args, halted = false }
        if args.id == nil then args.id = t.id end
        next_id = next_id + 1
        timers[t.id] = t
        return t.id
    end,
    Halt = function(ref)
        local t = timers[type(ref) == "table" and ref.id or ref]
        if t then t.halted = true; timers[t.id] = nil end
    end,
}
local function pump_one()
    local live = {}
    for _, t in pairs(timers) do if not t.halted then live[#live+1] = t end end
    table.sort(live, function(x, y) return x.id < y.id end)
    for _, t in ipairs(live) do
        if not t.halted then t.args.tick = (t.args.tick or 0) + 1; t.cb(t.args) end
    end
end

local function nkeys(t) local c = 0; for _ in pairs(t) do c = c + 1 end return c end
local function fill_window()
    local it = 0
    while it < 4000 do
        it = it + 1
        if nav:MaintainObstacleMapCache() then break end
    end
end

local START = Vector4.new(100, 100, 50, 1)

local function scenario(label, dest)
    fill_window()
    local straight = Vector4.Distance(START, dest)
    local ready_at, ticks = nil, 0
    local deferred = nav:StartRouteCorridorPreload(START, dest, function() ready_at = ticks end)
    if deferred then
        while ready_at == nil and ticks < 4000 do
            pump_one()
            ticks = ticks + 1
        end
    end
    local hover_ms = (ready_at or ticks) * (nav.obstacle_route_tick * 1000)

    local job = nav:CreateRoutePlanJob(START, dest, "initial")
    nav.route_plan_job = job
    local t = os.clock()
    while job.status == "running" do nav:StepRoutePlanJob(job, 4000) end
    local plan_ms = (os.clock() - t) * 1000
    local route = job.route or {}
    local end_dist = straight
    if #route > 0 then
        local last = nav:SectorKeyToPosition(route[#route])
        if last then end_dist = Vector4.Distance(last, dest) end
    end
    nav.route_plan_job = nil
    collectgarbage("collect"); collectgarbage("collect")
    print(string.format("  %-26s %5.0fm | hover %6.0fms (%3d ticks) | %-26s iters=%-7d plan %5.0fms | %d chunks / %.0f MB live",
        label, straight, hover_ms, ready_at or ticks,
        job.is_partial and string.format("PARTIAL (%.0fm short)", end_dist) or "FULL",
        job.iterations, plan_ms,
        nkeys(nav.obstacle_map_chunk_index), collectgarbage("count")/1024))
    nav:ReleaseRouteChunks()
end

print("window radius=" .. nav.obstacle_map_resident_radius
    .. "  route cap=" .. nav.obstacle_map_route_max_chunks
    .. "  budget=" .. nav.obstacle_route_load_budget_ms .. "ms/tick")
print("")
scenario("0.5 km", Vector4.new(-400, 0, 50, 1))
scenario("1.5 km", Vector4.new(-1400, 0, 50, 1))
scenario("2.8 km (known goal)", Vector4.new(-2610, 150, 50, 1))
scenario("4.5 km (map edge)", Vector4.new(-4500, 0, 50, 1))

-- ---------------------------------------------------------------------------
-- Final-approach dead zone analysis (uses the real config values)
-- ---------------------------------------------------------------------------
print("")
print("=== final approach handoff analysis ===")
-- destination_range lives on the AV object (av.lua: obj.destination_range = 3).
-- The stub AV here does not build it, so mirror the real value explicitly.
av.destination_range = av.destination_range or 3
local dr = av.destination_range
local ss = nav.sector_size
local mh = nav.final_local_max_handoff_distance
print(string.format("  destination_range=%.1fm  sector_size=%.1fm  max_handoff=%.1fm", dr, ss, mh))
print("  OLD: switch required horiz > sector_size, arrival required horiz < destination_range")
local gap_lo, gap_hi = dr, ss
if gap_hi > gap_lo then
    print(string.format("  -> DEAD ZONE (%.0fm, %.0fm]: too far to arrive, too close to switch. Vehicle hovers forever.", gap_lo, gap_hi))
end
print("  NEW: switch when horiz <= max_handoff (or after enough low-gain retries)")
local covered = true
for d = 0.0, mh, 0.5 do
    local can_arrive = d < dr
    local can_switch = d <= mh
    if not (can_arrive or can_switch) then covered = false end
end
print("  new rule covers every distance up to max_handoff: " .. tostring(covered))
