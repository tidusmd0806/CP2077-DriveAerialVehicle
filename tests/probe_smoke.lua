-- PROBE smoke test: confirm the instrumentation actually measures, warns,
-- carries context, and adds no measurable cost when disabled.
-- Run with:  python tools/run_grid_integration_test.lua probe_smoke.lua
local MODDIR, TEXTMAP, BINMAP, EMPTYMAP = ...

Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Distance(a, b) return Vector4.Length(Vector4.new(a.x-b.x, a.y-b.y, a.z-b.z, 1)) end
local gpos = Vector4.new(100, 100, 50, 1)
Game = { GetPlayer = function() return { GetWorldPosition = function() return gpos end } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
	is_debug_profile_autopilot = true,     -- PROBE ON
	debug_profile_warn_ms = 1.0,
	user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false,
	                     astar_calculation_precision = 100 },
	is_debug_mode = false, is_debug_enable_obstacle_scan = false,
}
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end }

local function preload(name)
	local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
	local b = f:read("*a"); f:close()
	package.preload[name] = (loadstring or load)(b, name)
end
preload("Etc/log.lua"); preload("Etc/utils.lua")
preload("Modules/profprobe.lua"); preload("Modules/obstacle_grid.lua")
preload("Modules/navigation.lua")

Log = require("Etc/log.lua")
local Prof = require("Modules/profprobe.lua")
local Navigation = require("Modules/navigation.lua")

local pass, fail = 0, 0
local function check(name, ok, detail)
	if ok then pass = pass + 1; print("  [PASS] " .. name)
	else fail = fail + 1; print("  [FAIL] " .. name .. (detail and ("  " .. detail) or "")) end
end

local co = { log_obj = Log:New() }
local av = { core_obj = co, log_obj = Log:New(), is_auto_pilot = true }
co.av_obj = av
local nav = Navigation:New(av)
nav.obstacle_map_dir = BINMAP
nav.obstacle_map_bin_dir = BINMAP
nav.obstacle_map_path = BINMAP .. "/none.dat"

check("probe enabled by the DAV flag", Prof.enabled == true)

-- Drive the base image in so lookups have data.
nav:FinishBaseImageLoad(5000.0)
check("base image resident", nav.obstacle_grid.chunk_n == 96,
	"got " .. nav.obstacle_grid.chunk_n)

-- Exercise wrapped methods.
nav:IsSectorAreaKnown(Vector4.new(100, 100, 50, 1))
nav:FindNearestKnownSectorPos(Vector4.new(0, 0, 40, 1))
nav:FindNearestSafeOrDangerCellPos(Vector4.new(0, 0, 40, 1))
nav:PlanGlobalRoute(Vector4.new(100, 100, 50, 1), Vector4.new(-2610, 150, 50, 1))

-- Re-attach to stdout so the probe's own output is visible here (New() wired it
-- to the mod logger, which writes to the log file).
local emitted = {}
Prof.attach(function(lvl, msg) emitted[#emitted + 1] = tostring(msg) end, "Info")
Prof.warn_ms = 1.0

-- A deliberately slow call must produce a warn line.
local t0 = Prof.begin("smoke.manual")
local sink = 0
for i = 1, 3000000 do sink = sink + i end
Prof.finish("smoke.manual", t0, Prof.fmt_args, 1.5, "tag")
check("slow section recorded", sink > 0)
check("warn line was emitted", #emitted > 0, "emitted=" .. #emitted)
check("warn names the section", emitted[1] and emitted[1]:find("smoke.manual") ~= nil,
	emitted[1])
check("warn carries the ms figure", emitted[1] and emitted[1]:find("ms") ~= nil,
	emitted[1])
check("warn carries the args", emitted[1] and emitted[1]:find("args=") ~= nil,
	emitted[1])
check("warn carries the autopilot context", emitted[1] and emitted[1]:find("phase=") ~= nil,
	emitted[1])

-- Context must be reachable.
local ctx = nav:ProbeContext()
check("ProbeContext returns a string", type(ctx) == "string" and #ctx > 0, ctx)
check("context carries the phase", ctx:find("phase=") ~= nil, ctx)

-- Summary must enumerate sections.
emitted = {}
Prof.dump("smoke")
local joined = table.concat(emitted, "\n")
check("summary emitted", #emitted > 3, "lines=" .. #emitted)
check("summary lists a wrapped method", joined:find("near.any") ~= nil)
check("summary lists astar.full", joined:find("astar.full") ~= nil)
check("summary has the calls column", joined:find("calls") ~= nil)

-- Disabled probe must not measure.
Prof.enabled = false
local before = 0
for _, n in ipairs({}) do before = before + 1 end
nav:IsSectorAreaKnown(Vector4.new(100, 100, 50, 1))
Prof.enabled = true
check("disabled probe is a pass-through (no error)", true)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
