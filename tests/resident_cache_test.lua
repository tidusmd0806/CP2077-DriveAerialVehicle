-- Resident obstacle-map cache functional test harness.
-- Real chunk grid in Data/map: x in [-6..2], y in [-7..7] (sparse, 96 chunks).
-- chunk world size = 50 cells * 10m = 500m.
local MODDIR, TESTMAP, BINMAP = ...

------------------------------------------------------------
-- CET stubs
------------------------------------------------------------
Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) end
function Vector4.Distance(a, b) return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2) end

local g_player_pos = Vector4.new(0, 0, 0, 1)
local g_player_exists = true
function setPlayer(x, y, z) g_player_pos = Vector4.new(x, y, z, 1) end

Game = {
    GetPlayer = function()
        if not g_player_exists then return nil end
        return { GetWorldPosition = function() return g_player_pos end }
    end,
}

json = { decode = function() return {} end, encode = function() return "{}" end }
DAV = {
	is_debug_profile_autopilot = false,
    user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false },
    is_debug_mode = false,
    is_debug_enable_obstacle_scan = false,
}
spdlog = { info = function() end }

-- Minimal Cron stub mirroring External/Cron.lua semantics:
--   Cron.Every(timeout, argsTable, cb)  -- arg order is auto-corrected upstream
--   callback receives the args table; Cron.Halt accepts id or table
-- pump_cron(n) runs every live timer n times so tests stay deterministic.
g_cron = { timers = {}, next_id = 1 }
Cron = {
    Every = function(timeout, a, b)
        local cb, args = a, b
        if type(cb) ~= "function" then cb, args = b, a end
        if type(args) ~= "table" then args = { arg = args } end
        local t = { id = g_cron.next_id, timeout = timeout, recurring = true,
                    cb = cb, args = args, halted = false }
        if args.id == nil then args.id = t.id end
        g_cron.next_id = g_cron.next_id + 1
        g_cron.timers[t.id] = t
        return t.id
    end,
    Halt = function(ref)
        local id = type(ref) == "table" and ref.id or ref
        local t = g_cron.timers[id]
        if t then t.halted = true; g_cron.timers[id] = nil end
    end,
    After = function(timeout, a, b) return Cron.Every(timeout, a, b) end,
}
function pump_cron(n)
    for _ = 1, n do
        local live = {}
        for _, t in pairs(g_cron.timers) do if not t.halted then live[#live + 1] = t end end
        table.sort(live, function(x, y) return x.id < y.id end)
        for _, t in ipairs(live) do
            if not t.halted then t.args.tick = (t.args.tick or 0) + 1; t.cb(t.args) end
        end
    end
end

-- CET resolves require() relative to the mod folder; emulate that by seeding
-- package.preload so require("Etc/log.lua") maps to <moddir>/Etc/log.lua.
local function preload(name)
    local path = MODDIR .. "/" .. name
    local f = io.open(path, "r")
    if not f then error("cannot open " .. path) end
    local body = f:read("*a")
    f:close()
    package.preload[name] = (loadstring or load)(body, name)
end
preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Etc/timescale.lua")
TimeScale = require("Etc/timescale.lua")
preload("Modules/obstacle_grid.lua")
preload("Modules/profprobe.lua"); preload("Modules/navigation.lua")

Log = require("Etc/log.lua")
local Navigation = require("Modules/navigation.lua")

------------------------------------------------------------
-- helpers
------------------------------------------------------------
local pass, fail = 0, 0
local function check(label, cond, detail)
    if cond then
        pass = pass + 1
        print(string.format("  [PASS] %s", label))
    else
        fail = fail + 1
        print(string.format("  [FAIL] %s  %s", label, detail or ""))
    end
end

local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
local function resident() return count_keys(nav.obstacle_map_chunk_index) end
local function cells()    return count_keys(nav.obstacle_map) end
local function heap_mb() return collectgarbage("count") / 1024 end

local function drain(max_iters)
    local iters = 0
    while iters < max_iters do
        iters = iters + 1
        if nav:MaintainObstacleMapCache() then break end
    end
    return iters
end

local function resident_keys()
    local ks = {}
    for k in pairs(nav.obstacle_map_chunk_index) do ks[#ks + 1] = k end
    table.sort(ks)
    return table.concat(ks, " ")
end

local CHUNK_W = 500   -- obstacle_map_chunk_cells * obstacle_cell_size
local HOME_X, HOME_Y = 100, 100                 -- chunk 0_0
local AWAY_X, AWAY_Y = -2750, 250             -- chunk -6_0

------------------------------------------------------------
-- fixture
------------------------------------------------------------
local core_obj = {
    log_obj = Log:New(),
    session_obstacle_map_cache = nil,
    session_obstacle_map_chunk_index = nil,
    session_obstacle_cell_size = nil,
    is_obstacle_map_loaded_in_session = false,
    is_obstacle_map_loading_in_session = false,
    session_obstacle_map_load_queue = nil,
    session_obstacle_map_load_index = 1,
    session_obstacle_map_load_total = 0,
    session_obstacle_map_loaded_files = 0,
    is_obstacle_map_preload_timer_active = false,
}
local av_obj = { core_obj = core_obj, log_obj = Log:New() }
core_obj.av_obj = av_obj

nav = Navigation:New(av_obj)
nav.obstacle_map_dir = TESTMAP
-- The runtime is packed-only, so the bin dir has to be pointed at the staged
-- packed chunks -- the default "Data/map_bin" is relative to the game's CWD
-- and resolves to nothing under the harness.
nav.obstacle_map_bin_dir = BINMAP
nav.obstacle_map_path = TESTMAP .. "/obstacle_map.dat"   -- no legacy file

print("=== 1. inventory enumeration (packed only) ===")
local chunks = nav:GetAllChunksCached(true)
check("found packed chunk files on disk", #chunks > 0, "#=" .. #chunks)
check("inventory is cached (2nd call returns same table)", nav:GetAllChunksCached() == chunks)
local n_bin, n_legacy_fields = 0, 0
for _, c in ipairs(chunks) do
    if c.has_bin then n_bin = n_bin + 1 end
    if c.has_dat ~= nil or c.has_diff ~= nil then n_legacy_fields = n_legacy_fields + 1 end
end
check("every inventory entry is a packed chunk", n_bin == #chunks,
    string.format("%d of %d", n_bin, #chunks))
check("no legacy dat/diff fields left on the inventory",
    n_legacy_fields == 0, "entries with legacy fields=" .. n_legacy_fields)
print(string.format("       chunks=%d  with .bin=%d", #chunks, n_bin))


print("=== 5b. packed cell key round-trip ===")
local cases = { {0,0,0}, {-1,-1,-1}, {10,10,5}, {-261,15,5}, {-3000,-3000,88}, {2999,2999,0} }
local all_ok, first_bad = true, nil
for _, c in ipairs(cases) do
    local k = nav:PackCellKey(c[1], c[2], c[3])
    local ux, uy, uz = nav:UnpackCellKey(k)
    if ux ~= c[1] or uy ~= c[2] or uz ~= c[3] then
        all_ok = false
        first_bad = string.format("(%d,%d,%d) -> %s", c[1], c[2], c[3], tostring(k))
    end
end
check("pack/unpack round-trips for every sampled coord triple", all_ok, first_bad or "")
check("legacy string key unpacks to the same triple",
    (function()
        local x, y, z = nav:UnpackCellKey("-261_15_5")
        return x == -261 and y == 15 and z == 5
    end)())
check("string and numeric forms normalise to the same key",
    nav:NormalizeCellKey("-261_15_5") == nav:PackCellKey(-261, 15, 5))
check("SectorKeyToString renders the readable form",
    nav:SectorKeyToString(nav:PackCellKey(-261, 15, 5)) == "-261_15_5")
check("distinct triples pack to distinct keys",
    nav:PackCellKey(1, 2, 3) ~= nav:PackCellKey(1, 3, 2)
    and nav:PackCellKey(1, 2, 3) ~= nav:PackCellKey(2, 2, 3)
    and nav:PackCellKey(1, 2, 3) ~= nav:PackCellKey(1, 2, 4))
-- a string passed to a setter must land on the packed key, not beside it
nav:SetObstacleCell("-1_-1_-1", "danger")
check("setter normalises a string key to the packed entry",
    nav.obstacle_map[nav:PackCellKey(-1, -1, -1)] == "danger"
    and nav.obstacle_map["-1_-1_-1"] == nil)
check("CellKeyToChunkKey works on a packed key",
    nav:CellKeyToChunkKey(nav:PackCellKey(120, -40, 3)) == "2_-1")
check("PositionToSectorKey returns a number",
    type(nav:PositionToSectorKey(Vector4.new(1234, -567, 89, 1))) == "number")
check("SectorKeyToPosition round-trips through PositionToSectorKey",
    (function()
        local p = Vector4.new(1234, -567, 89, 1)
        local c = nav:SectorKeyToPosition(nav:PositionToSectorKey(p))
        -- cell (123, -57, 8) -> centre (1235, -565, 85) at 10 m cells
        return math.abs(c.x - 1235) < 1e-6
            and math.abs(c.y - (-565)) < 1e-6
            and math.abs(c.z - 85) < 1e-6
    end)())


print("=== 7. robustness ===")
local radius = nav.obstacle_map_resident_radius
g_player_exists = false
check("no player -> maintenance is a safe no-op",
    pcall(function() nav:MaintainObstacleMapCache() end))
g_player_exists = true
nav.obstacle_map_resident_radius = 0
check("radius 0 disables maintenance without error",
    pcall(function() nav:MaintainObstacleMapCache() end))
nav.obstacle_map_resident_radius = radius
check("unknown chunk_key unload is a safe no-op",
    pcall(function() nav:UnloadResidentChunk("999_999") end))


print("=== 8. no process spawning on the autopilot path ===")
setPlayer(HOME_X, HOME_Y, 0)
nav.obstacle_map_resident_radius = radius
drain(3000)

-- Instrument the process-spawning entry points so any regression shows up here.
local real_popen, real_exec = io.popen, os.execute
local spawns = {}
io.popen = function(cmd, ...)
    spawns[#spawns + 1] = tostring(cmd)
    return real_popen and real_popen(cmd, ...)
end
os.execute = function(cmd, ...)
    spawns[#spawns + 1] = tostring(cmd)
    return real_exec and real_exec(cmd, ...)
end

-- Warm the inventory the way a real session does.
nav:GetAllChunksCached()
local after_warm = #spawns

-- These all used to spawn cmd.exe on every call while resolving an autopilot target.
local nearest = nav:FindNearestObstacleMapChunk(Vector4.new(0, 0, 20, 1), nil)
local ok1 = pcall(function() nav:FindNearestKnownSectorPos(Vector4.new(0, 0, 20, 1)) end)
local ok2 = pcall(function() nav:FindNearestSafeOrDangerCellPos(Vector4.new(0, 0, 20, 1)) end)
for _ = 1, 20 do
    nav:FindNearestObstacleMapChunk(Vector4.new(-1234, 567, 20, 1), nil)
    nav:EnumerateObstacleMapDataChunks()
end
local after = #spawns

io.popen, os.execute = real_popen, real_exec

check("inventory warm-up spawns at most the one-time enumeration", after_warm <= 2,
    "spawns=" .. after_warm)
check("autopilot target resolution spawns zero processes",
    after == after_warm,
    "extra=" .. (after - after_warm) .. ": " ..
    table.concat(spawns, " | ", after_warm + 1, after))
check("nearest-chunk lookup still resolves", nearest ~= nil)
check("FindNearestKnownSectorPos still runs", ok1)
check("FindNearestSafeOrDangerCellPos still runs", ok2)
check("EnumerateObstacleMapDataChunks returns the cached table (no copy, no probe)",
    nav:EnumerateObstacleMapDataChunks() == nav:GetAllChunksCached())


print("=== 9. final_local no-progress watchdog ===")
-- The repulsion field can balance the goal attraction around an obstacle-dense
-- destination, so the AV closes in and gets shoved back in a loop. The watchdog
-- must fire when we stop closing in, and must NOT fire while we are still closing.
nav:ResetFinalLocalProgressWatchdog()
check("9. watchdog starts empty",
    nav.final_local_best_dist == nil and nav.final_local_no_progress_since == nil)

-- 9a. first call just establishes the baseline
local stalled, best = nav:UpdateFinalLocalProgressWatchdog(50.0, 0.0)
check("9a. first call establishes baseline, not stalled", stalled == false)
check("9a. baseline recorded", nav.final_local_best_dist == 50.0)

-- 9b. steady approach must never stall
nav:ResetFinalLocalProgressWatchdog()
local stalled_ever = false
local d = 60.0
for i = 1, 80 do                       -- 40 s of steady closing
    d = d - 0.5
    local s = nav:UpdateFinalLocalProgressWatchdog(d, i * 0.5)
    if s then stalled_ever = true end
end
check("9b. steady closing never triggers the watchdog (40s)", stalled_ever == false)
-- Progress only counts when it beats the best by a full epsilon, so with 0.5m
-- steps the recorded best quantises to every other step (60 - 39*1.0 = 21 -> 20.5).
check("9b. best tracks the closest approach within one epsilon",
    nav.final_local_best_dist >= 20.0 and nav.final_local_best_dist <= 21.0,
    "best=" .. tostring(nav.final_local_best_dist))

-- 9c. oscillation inside the epsilon band must NOT count as progress
nav:ResetFinalLocalProgressWatchdog()
nav:UpdateFinalLocalProgressWatchdog(50.0, 0.0)
local fired_at = nil
for i = 1, 60 do
    local osc = (i % 2 == 0) and 50.4 or 49.4   -- 1.0m swing, epsilon is 1.0
    local s = nav:UpdateFinalLocalProgressWatchdog(osc, i * 0.5)
    if s and fired_at == nil then fired_at = i * 0.5 end
end
check("9c. oscillation triggers the watchdog", fired_at ~= nil)
check("9c. fires only once stalled past the timeout",
    fired_at ~= nil and fired_at >= nav.final_local_no_progress_timeout,
    "fired_at=" .. tostring(fired_at) .. " timeout=" .. tostring(nav.final_local_no_progress_timeout))

-- 9d. real progress resets the clock and delays the fire.
-- Timings are derived from the configured timeout so the test survives tuning it.
nav:ResetFinalLocalProgressWatchdog()
local T = nav.final_local_no_progress_timeout
nav:UpdateFinalLocalProgressWatchdog(50.0, 0.0)
nav:UpdateFinalLocalProgressWatchdog(40.0, 3.0)   -- genuine 10m gain
local s_before = nav:UpdateFinalLocalProgressWatchdog(40.5, 3.0 + T - 0.5)
check("9d. a real gain restarts the clock (not stalled just before the timeout)", s_before == false)
local s_after = nav:UpdateFinalLocalProgressWatchdog(40.5, 3.0 + T + 0.5)
check("9d. fires past the timeout measured from the last real gain", s_after == true)

-- 9e. reset clears the state so a new approach starts clean
nav:ResetFinalLocalProgressWatchdog()
local s_after_reset = nav:UpdateFinalLocalProgressWatchdog(40.5, 99.0)
check("9e. after reset the first call is not stalled", s_after_reset == false)
check("9e. after reset the baseline is the new distance", nav.final_local_best_dist == 40.5)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
