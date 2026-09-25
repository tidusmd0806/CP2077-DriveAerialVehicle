-- Does the corridor's extra live heap reintroduce micro-stutter?
-- Holds the resident map, then runs a 100Hz-style allocation loop and reports
-- the per-tick wall-time distribution. GC pauses show up as the tail.
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
local timers, nid = {}, 1
Cron = { Every = function(to,a,b) local cb,args=a,b if type(cb)~="function" then cb,args=b,a end
        if type(args)~="table" then args={arg=args} end local t={id=nid,cb=cb,args=args,halted=false}
        if args.id==nil then args.id=t.id end nid=nid+1 timers[t.id]=t return t.id end,
    Halt = function(r) local t=timers[type(r)=="table" and r.id or r] if t then t.halted=true timers[t.id]=nil end end }

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

local function nkeys(t) local c=0; for _ in pairs(t) do c=c+1 end return c end
local function settle() local i=0; while i<6000 do i=i+1; if nav:MaintainObstacleMapCache() then break end end end

-- Representative per-tick Lua work: a handful of table writes plus lookups into
-- the live obstacle map, which is what the autopilot/idle loop keeps touching.
local probe_keys = {}
local function build_probe(n)
    probe_keys = {}
    local i = 0
    for k in pairs(nav.obstacle_map) do
        i = i + 1
        probe_keys[#probe_keys + 1] = k
        if i >= n then break end
    end
end

local function bench(label, iters)
    collectgarbage("collect"); collectgarbage("collect")
    local live_mb = collectgarbage("count") / 1024
    local times = {}
    local t0 = os.clock()
    for it = 1, iters do
        local s = os.clock()
        local scratch = { it, it * 2, it * 3 }
        local hits = 0
        for _, k in ipairs(probe_keys) do
            if nav.obstacle_map[k] ~= nil then hits = hits + 1 end
        end
        if scratch[1] == -1 then hits = hits end
        times[it] = (os.clock() - s) * 1000
    end
    local total = (os.clock() - t0) * 1000
    table.sort(times)
    local function q(p) return times[math.min(#times, math.max(1, math.floor(#times * p)))] end
    local over8 = 0
    for _, v in ipairs(times) do if v >= 8 then over8 = over8 + 1 end end
    print(string.format("  %-34s %3d chunks %6.0f MB | p50 %.2f  p90 %.2f  p99 %.2f  p99.9 %.2f  max %6.2f ms | >=8ms %5.2f%%",
        label, nkeys(nav.obstacle_map_chunk_index), live_mb,
        q(0.50), q(0.90), q(0.99), q(0.999), times[#times], 100.0 * over8 / iters))
end

print("allocation-loop surrogate for the 100 Hz Lua tick (20000 iters)\n")

settle()
build_probe(400)
bench("window only (radius 2)", 20000)

-- Now stream a real 2.8 km corridor on top of the window.
nav:ReleaseRouteChunks()
nav:PrepareRouteChunks(Vector4.new(100, 100, 50, 1), Vector4.new(-2610, 150, 50, 1))
settle()
build_probe(400)
bench("window + 2.8 km corridor", 20000)

-- Worst realistic case: a long corridor across the mapped area.
nav:ReleaseRouteChunks()
nav:PrepareRouteChunks(Vector4.new(1000, -3000, 50, 1), Vector4.new(-3000, 3000, 50, 1))
nav.obstacle_map_resident_radius = 3
settle()
build_probe(400)
bench("long corridor + radius 3 window", 20000)
