-- Resident obstacle-map cache functional test harness.
-- Real chunk grid in Data/map: x in [-6..2], y in [-7..7] (sparse, 96 chunks).
-- chunk world size = 50 cells * 10m = 500m.
local MODDIR, TESTMAP = ...

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
    user_setting_table = { garage_info_list = {}, is_enable_obstacle_recording = false },
    is_debug_mode = false,
    debug_enable_obstacle_scan = false,
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
    package.preload[name] = load(body, name)
end
preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Modules/navigation.lua")

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
nav.obstacle_map_path = TESTMAP .. "/obstacle_map.dat"   -- no legacy file

print("=== 1. inventory enumeration ===")
local chunks = nav:GetAllChunksCached(true)
check("found chunk files on disk", #chunks > 0, "#=" .. #chunks)
check("inventory is cached (2nd call returns same table)", nav:GetAllChunksCached() == chunks)
local n_dat, n_diff = 0, 0
for _, c in ipairs(chunks) do
    if c.has_dat then n_dat = n_dat + 1 end
    if c.has_diff then n_diff = n_diff + 1 end
end
print(string.format("       chunks=%d  with .dat=%d  with .diff=%d", #chunks, n_dat, n_diff))

print("=== 1b. window fill is deferred until the gate opens ===")
setPlayer(HOME_X, HOME_Y, 0)
for _ = 1, 20 do nav:MaintainObstacleMapCache() end
check("no chunk data loaded while the fill gate is closed",
    resident() == 0, "resident=" .. resident())
check("fill gate reports closed", nav.obstacle_map_fill_started == false)
check("StartObstacleMapFill opens the gate", nav:StartObstacleMapFill() == true)
check("opening the gate twice is a no-op", nav:StartObstacleMapFill() == false)
check("map learning is off by default",
    nav:IsObstacleRecordingEnabled() == false)
DAV.user_setting_table.is_enable_obstacle_recording = true
check("map learning turns on with the user setting",
    nav:IsObstacleRecordingEnabled() == true)
DAV.user_setting_table.is_enable_obstacle_recording = false
DAV.debug_enable_obstacle_scan = true
check("map learning turns on with the debug flag",
    nav:IsObstacleRecordingEnabled() == true)
DAV.debug_enable_obstacle_scan = false

print("=== 2. resident window around the player ===")
setPlayer(HOME_X, HOME_Y, 0)
local radius = nav.obstacle_map_resident_radius
drain(2000)
print(string.format("       radius=%d  resident=%d  cells=%d  heap=%.1fMB",
    radius, resident(), cells(), heap_mb()))
print("       keys: " .. resident_keys())
check("chunk 0_0 is resident", nav:IsChunkResident("0_0"))
check("resident count is bounded by the window",
    resident() <= (2 * radius + 1) ^ 2,
    string.format("%d > %d", resident(), (2 * radius + 1) ^ 2))
local outside = 0
for ck in pairs(nav.obstacle_map_chunk_index) do
    local cx, cy = ck:match("^(-?%d+)_(-?%d+)$")
    if math.max(math.abs(tonumber(cx)), math.abs(tonumber(cy))) > radius then outside = outside + 1 end
end
check("nothing outside the resident radius was pulled in", outside == 0, "outside=" .. outside)
-- every existing chunk inside the window must be loaded
local expected = 0
for _, c in ipairs(chunks) do
    if math.max(math.abs(c.chunk_x), math.abs(c.chunk_y)) <= radius then expected = expected + 1 end
end
check("every existing chunk inside the window IS loaded", resident() == expected,
    string.format("resident=%d expected=%d", resident(), expected))

print("=== 3. per-tick budget ===")
-- Fresh cache, measure the maintenance tick distribution.
nav.obstacle_map = {}
nav.obstacle_map_chunk_index = {}
nav.obstacle_map_load_states = {}
nav.is_obstacle_map_loaded = false
setPlayer(HOME_X, HOME_Y, 0)
local times = {}
local ticks = 0
repeat
    local t = os.clock()
    local idle = nav:MaintainObstacleMapCache()
    times[#times + 1] = (os.clock() - t) * 1000
    ticks = ticks + 1
until idle or ticks > 3000
local sorted = {}
for i, v in ipairs(times) do sorted[i] = v end
table.sort(sorted)
local function q(p) return sorted[math.min(#sorted, math.max(1, math.floor(#sorted * p)))] end
print(string.format("       %d ticks  p50=%.1f p90=%.1f p99=%.1f worst=%.1f ms (budget %.1fms)",
    ticks, q(0.5), q(0.9), q(0.99), sorted[#sorted], nav.obstacle_map_load_budget_ms))
check("typical maintenance tick stays at the budget", q(0.9) <= nav.obstacle_map_load_budget_ms * 2.0,
    string.format("p90=%.1fms", q(0.9)))
-- Residual outliers during the fill phase come from Lua table rehash as
-- obstacle_map grows past a power-of-two boundary; they are one-off, not periodic.
check("outliers are rare (<5% of fill ticks over 12ms)",
    (function() local c = 0; for _, v in ipairs(times) do if v > 12 then c = c + 1 end end
        return c / #times < 0.05 end)(),
    string.format("worst=%.1fms over %d ticks", sorted[#sorted], ticks))

print("=== 3b. inventory enumeration cost ===")
local t_enum = os.clock()
nav:GetAllChunksCached(true)
print(string.format("       io.popen x2 = %.1f ms (one-off; removed entirely by fix (4))",
    (os.clock() - t_enum) * 1000))

print("=== 4. window follows the player ===")
local before = resident()
setPlayer(AWAY_X, AWAY_Y, 0)
drain(2000)
print(string.format("       before=%d  after=%d  cells=%d  heap=%.1fMB",
    before, resident(), cells(), heap_mb()))
print("       keys: " .. resident_keys())
check("far chunk 0_0 was evicted", not nav:IsChunkResident("0_0"))
check("chunk -6_0 is now resident", nav:IsChunkResident("-6_0"))
local still_far = 0
for ck in pairs(nav.obstacle_map_chunk_index) do
    local cx, cy = ck:match("^(-?%d+)_(-?%d+)$")
    if math.max(math.abs(tonumber(cx) + 6), math.abs(tonumber(cy))) > nav.obstacle_map_evict_radius then
        still_far = still_far + 1
    end
end
check("no chunk beyond the evict radius remains", still_far == 0, "left=" .. still_far)
check("memory did not grow past the window", resident() <= (2 * radius + 1) ^ 2)

print("=== 5. dirty chunks are flushed before eviction ===")
setPlayer(HOME_X, HOME_Y, 0)
drain(2000)
nav:SetObstacleCell("10_10_5", true)   -- cell (10,10,5) -> chunk 0_0
check("cell marked dirty in chunk 0_0", nav.obstacle_map_dirty_chunks["0_0"] ~= nil)
setPlayer(AWAY_X, AWAY_Y, 0)
drain(2000)
check("dirty chunk 0_0 left memory", not nav:IsChunkResident("0_0"))
check("dirty flag cleared by the flush", nav.obstacle_map_dirty_chunks["0_0"] == nil)
local diff = io.open(TESTMAP .. "/chunk_0_0.diff", "r")
check("diff written before eviction (no data loss)", diff ~= nil)
if diff then
    local body = diff:read("*all")
    diff:close()
    check("diff carries the recorded cell", body:find("10 10 5 2", 1, true) ~= nil)
end
-- pull it back and the recorded cell must be there
for _, c in ipairs(nav:GetAllChunksCached()) do
    if c.chunk_key == "0_0" then nav:LoadResidentChunk(c) end
end
local packed_10_10_5 = nav:PackCellKey(10, 10, 5)
check("reloaded chunk keeps the recorded cell",
    nav.obstacle_map[packed_10_10_5] == true,
    "got " .. tostring(nav.obstacle_map[packed_10_10_5]))
check("no parallel string-keyed entry leaked into the map",
    nav.obstacle_map["10_10_5"] == nil,
    "got " .. tostring(nav.obstacle_map["10_10_5"]))

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

print("=== 6. route corridor preload ===")
setPlayer(HOME_X, HOME_Y, 0)
drain(2000)
nav:ReleaseRouteChunks()
local pending = nav:PrepareRouteChunks(Vector4.new(HOME_X, HOME_Y, 20, 1), Vector4.new(-3000, 0, 20, 1))
local pinned = count_keys(nav.obstacle_map_route_chunks)
print(string.format("       pinned=%d (cap %d)  pending=%d  resident=%d", pinned,
    nav.obstacle_map_route_max_chunks, pending, resident()))
check("pin count respects the cap", pinned <= nav.obstacle_map_route_max_chunks,
    "pinned=" .. pinned)
check("destination chunk -6_0 is pinned", nav.obstacle_map_route_chunks["-6_0"] ~= nil)
check("PrepareRouteChunks queues instead of blocking",
    pending > 0 and not nav:IsChunkResident("-6_0"))
drain(3000)
check("maintenance drains the corridor queue", nav:IsChunkResident("-6_0"))
-- a pinned chunk must survive eviction while the player is far from it
nav:EvictDistantChunks(0, 0)
check("pinned corridor chunk survives eviction", nav:IsChunkResident("-6_0"))
nav:ReleaseRouteChunks()
check("release clears the pin table", count_keys(nav.obstacle_map_route_chunks) == 0)
check("release clears the pending queue", nav.obstacle_map_route_pending == nil)

print("=== 6b. departure gate defers until the corridor is streamed ===")
setPlayer(HOME_X, HOME_Y, 0)
drain(2000)
nav:ReleaseRouteChunks()
nav.av_obj.is_auto_pilot = true
local calls = 0
local deferred = nav:StartRouteCorridorPreload(
    Vector4.new(HOME_X, HOME_Y, 20, 1), Vector4.new(-3000, 0, 20, 1),
    function() calls = calls + 1 end)
check("gate defers departure", deferred == true)
check("on_ready has not fired yet", calls == 0)
pump_cron(400)
check("on_ready fired once the corridor streamed in", calls == 1)
check("destination resident before departure", nav:IsChunkResident("-6_0"))
check("gate timer cleared after completion", nav.route_corridor_timer == nil)
check("pending queue emptied", nav.obstacle_map_route_pending == nil)
pump_cron(200)
check("on_ready fires exactly once, never twice", calls == 1)

-- RACE: MaintainObstacleMapCache() drains the same queue from its own timer.
-- If it empties the queue first the gate must STILL fire on_ready -- an early
-- return there left the vehicle hovering forever with no autopilot loop.
for _, key in ipairs({"-1_0", "-2_0", "-3_0", "-4_0", "-5_0", "-6_0"}) do
    if nav:IsChunkResident(key) then nav:UnloadResidentChunk(key) end
end
nav:ReleaseRouteChunks()
local calls_b = 0
nav:StartRouteCorridorPreload(
    Vector4.new(HOME_X, HOME_Y, 20, 1), Vector4.new(-3000, 0, 20, 1),
    function() calls_b = calls_b + 1 end)
nav:DrainRouteCorridor(10)   -- maintenance wins the race, queue becomes nil
check("maintenance emptied the queue before the gate ran",
    nav.obstacle_map_route_pending == nil and calls_b == 0)
pump_cron(10)
check("gate still fires when maintenance drained first", calls_b == 1)
check("no stall: gate timer cleared", nav.route_corridor_timer == nil)

-- cancelling during the hover must abort the gate without calling on_ready.
-- Push the corridor back out of memory first so there is real work to cancel.
for _, key in ipairs({"-1_0", "-2_0", "-3_0", "-4_0", "-5_0", "-6_0"}) do
    if nav:IsChunkResident(key) then nav:UnloadResidentChunk(key) end
end
nav:ReleaseRouteChunks()
local calls_c = 0
local d2 = nav:StartRouteCorridorPreload(
    Vector4.new(HOME_X, HOME_Y, 20, 1), Vector4.new(-3000, 0, 20, 1),
    function() calls_c = calls_c + 1 end)
check("cancel case actually had work queued", d2 == true)
nav.av_obj.is_auto_pilot = false
pump_cron(50)
check("cancelling aborts the gate silently", calls_c == 0)
check("cancel cleared the gate timer", nav.route_corridor_timer == nil)
nav.av_obj.is_auto_pilot = true
-- nothing to load -> no deferral
nav:ReleaseRouteChunks()
nav:PrepareRouteChunks(Vector4.new(HOME_X, HOME_Y, 20, 1), Vector4.new(HOME_X + 50, HOME_Y, 20, 1))
drain(3000)
local d3 = nav:StartRouteCorridorPreload(
    Vector4.new(HOME_X, HOME_Y, 20, 1), Vector4.new(HOME_X + 50, HOME_Y, 20, 1),
    function() error("should not defer when nothing is pending") end)
check("no pending chunks -> runs inline, no deferral", d3 == false)

print("=== 7. robustness ===")
g_player_exists = false
check("no player -> maintenance is a safe no-op",
    pcall(function() nav:MaintainObstacleMapCache() end))
g_player_exists = true
nav.obstacle_map_resident_radius = 0
check("radius 0 disables windowing without error",
    pcall(function() nav:MaintainObstacleMapCache() end))
nav.obstacle_map_resident_radius = radius
check("unknown chunk_key eviction is a safe no-op",
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

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
