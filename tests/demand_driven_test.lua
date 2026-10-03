-- =============================================================================
-- Demand-driven timer test (docs/PERF_PLAN_event_driven.md, B-1 / B-2 / B-3)
--
-- B群 is about NOT firing work that has nothing to do. What matters:
--
--   B-2  Navigation:HasPendingMapWork() is a pure-Lua gate, and the obstacle
--        map maintenance timer parks itself the moment that gate goes false,
--        then restarts on an explicit wake.
--   B-3  The LTBF compatibility poll exists only while the player is aboard.
--   B-1  The garage refresh is throttled to a slow safety net driven by
--        explicit RequestGarageRefresh() calls.
--
-- The real modules are loaded with the CET API stubbed. The Core / Event
-- instances are built straight off the shipped metatables so the methods under
-- test are the shipped ones, without needing a whole game session.
--
-- Run:  python tests/run_demand_driven_test.py
-- =============================================================================

local MODDIR = ...

-- ---------------------------------------------------------------- stubs ----
Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Vector3To4(v) return Vector4.new(v.x, v.y, v.z, 0) end
Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
EulerAngles = { new = function(p, y, r) return { pitch = p, yaw = y, roll = r } end }
Quaternion = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }
CName = { new = function(s) return { value = s } end }
ResRef = { new = function(s) return { value = s } end, FromName = function(s) return { value = s } end }
QueryFilter = { new = function() return { mask2 = 0 } end, AddGroup = function() return { mask2 = 1 } end }
DynamicEntitySpec = { new = function() return {} end }
SaveLocksManager = { RequestSaveLockAdd = function() end, RequestSaveLockRemove = function() end }
GameObjectEffectHelper = { StartEffectEvent = function() end, StopEffectEvent = function() end }
json = { decode = function() return {} end, encode = function() return "{}" end }
spdlog = { info = function() end }

-- A Cron we can actually drive. Every Every() is recorded so the test can fire
-- timers by hand and watch which ones are still alive.
local timers = {}
Cron = {}
function Cron.Every(period, a, b)
    local cb = (type(a) == "function") and a or b
    local state = (type(a) == "table") and a or nil
    local t = { period = period, cb = cb, state = state, alive = true }
    timers[#timers + 1] = t
    return t
end
function Cron.Halt(t)
    if t ~= nil then t.alive = false end
end
function Cron.After(delay, cb)
    timers[#timers + 1] = { period = delay, cb = cb, state = nil, alive = true, is_after = true }
end

--- Fire every live repeating timer n times.
local function fire(n)
    for _ = 1, n do
        for _, t in ipairs(timers) do
            if t.alive and not t.is_after then t.cb(t.state or t) end
        end
    end
end

local function live_timer_count()
    local c = 0
    for _, t in ipairs(timers) do if t.alive then c = c + 1 end end
    return c
end

local function clear_timers() timers = {} end

DAV = {
    frame_seq = 0,
    model_index = 1,
    model_type_index = 1,
    is_debug_mode = false,
    is_debug_enable_obstacle_scan = false,
    is_debug_profile_autopilot = false,
    is_valid_ltbf = false,
    time_resolution = 0.01,
    axis_dead_zone = 0.1,
    user_setting_table = {
        is_enable_landing_vfx = false,
        is_enable_obstacle_recording = true,
        garage_info_list = {},
        astar_calculation_precision = 100,
    },
}

-- LTBF stub: fs() is the global the compatibility poll reads.
local ltbf_state = { active = false, thrusters_stopped = 0 }
function fs()
    local function stop_one()
        ltbf_state.thrusters_stopped = ltbf_state.thrusters_stopped + 1
    end
    return {
        ctlr = ltbf_state,
        playerComponent = {
            configuration = {
                thrusters = {
                    { Stop = stop_one }, { Stop = stop_one },
                    { Stop = stop_one }, { Stop = stop_one },
                },
            },
        },
    }
end

local player_calls = 0
Game = {
    FindEntityByID = function(id) return nil end,
    GetPlayer = function()
        player_calls = player_calls + 1
        return {
            GetWorldPosition = function() return Vector4.new(0, 0, 0, 1) end,
            PSIsInDriverCombat = function() return false end,
        }
    end,
    GetTimeSystem = function() return { GetGameTimeStamp = function() return 0 end } end,
    GetDynamicEntitySystem = function()
        return { CreateEntity = function(_, spec) return { hash = 1234 } end, DeleteEntity = function() end }
    end,
    GetSpatialQueriesSystem = function()
        return { SyncRaycastByQueryFilter = function() return false, nil end }
    end,
    GetVehicleSystem = function()
        return { GetPlayerUnlockedVehicles = function() return {} end }
    end,
    IsSavingLocked = function() return false, nil end,
}

-- lupa is stock Lua 5.1 and rejects `goto` / `::label::`, which LuaJIT (what
-- CET actually embeds) accepts. Same neutralisation as tools/check_lua_syntax.py
-- and situation_cost_test; the only goto in the tree is in Core:LoadLanguageFiles,
-- which nothing here drives.
local LUAJIT_EXT = "%f[%w]goto%s+[A-Za-z_][A-Za-z0-9_]*%f[^%w]"
local LUAJIT_LBL = "::%s*[A-Za-z_][A-Za-z0-9_]*%s*::"

local function preload(name)
    local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
    local b = f:read("*a"); f:close()
    b = b:gsub(LUAJIT_EXT, "do end")
    b = b:gsub(LUAJIT_LBL, "do end")
    local chunk, err = (loadstring or load)(b, name)
    assert(chunk, "failed to compile " .. name .. ": " .. tostring(err))
    package.preload[name] = chunk
    -- Modules disagree on whether the ".lua" suffix belongs in the require path
    -- (sound.lua wants "Etc/utils", core.lua wants "Etc/utils.lua"). Register
    -- both so one loader covers the whole tree.
    package.preload[(name:gsub("%.lua$", ""))] = chunk
end

preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Etc/timescale.lua")
TimeScale = require("Etc/timescale.lua")
preload("Etc/def.lua")
preload("Etc/queue.lua")
preload("External/GameUI.lua")
preload("External/GameHUD.lua")
preload("External/GameSettings.lua")
preload("Modules/profprobe.lua")
preload("Modules/obstacle_grid.lua")
preload("Modules/camera.lua")
preload("Modules/engine.lua")
preload("Modules/navigation.lua")
preload("Modules/av.lua")
preload("Modules/hud.lua")
preload("Modules/sound.lua")
preload("Modules/ui.lua")
preload("Modules/event.lua")
preload("Modules/core.lua")

Log = require("Etc/log.lua")
local Def = require("Etc/def.lua")
local AV = require("Modules/av.lua")
local Navigation = require("Modules/navigation.lua")
local Event = require("Modules/event.lua")
local Core = require("Modules/core.lua")

-- ------------------------------------------------------------- harness -----
local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1; print("  [PASS] " .. name)
    else fail = fail + 1; print("  [FAIL] " .. name .. (detail and ("  " .. detail) or "")) end
end

--- A real Navigation bound to a real AV whose core_obj is a real Core instance.
--- Built off the metatables so the shipped methods run unchanged.
local function new_trio()
    -- Navigation:New reads session fields straight off core_obj, so the Core
    -- instance has to exist before the Navigation one.
    local core = setmetatable({}, Core)
    core.log_obj = Log:New()
    core.is_obstacle_map_preload_timer_active = false
    core.obstacle_map_maintenance_timer = nil
    core.obstacle_map_maintenance_tick = nil
    core.has_started_obstacle_map_preload = false
    core.last_garage_update_time = nil
    core.current_purchased_vehicle_count = 0
    core.session_obstacle_map_cache = nil
    core.session_obstacle_cell_size = nil
    core.session_obstacle_map_chunk_index = nil

    local av = setmetatable({ log_obj = Log:New(), core_obj = core }, AV)
    av.navigation_obj = Navigation:New(av)
    core.av_obj = av
    return av.navigation_obj, core, av
end


-- =========================================================== B-2 gate ====
print("== 1. HasPendingMapWork is a pure-Lua gate ==")
local nav, core = new_trio()

nav.obstacle_map_resident_radius = 0
check("radius 0 -> no work", nav:HasPendingMapWork() == false)

nav.obstacle_map_resident_radius = 10
nav.is_base_image_loaded = false
nav.base_image_pending = nil
check("base image still pending -> work", nav:HasPendingMapWork() == true)

nav.base_image_pending = false
check("no packed data on disk -> no work", nav:HasPendingMapWork() == false)

nav.is_base_image_loaded = true
nav.obstacle_map_learned_flush_cells = 200000
nav.obstacle_map_learned_count = 0
check("resident + nothing learned -> no work", nav:HasPendingMapWork() == false)

nav.obstacle_map_learned_count = 200000
check("exactly at the limit -> no work", nav:HasPendingMapWork() == false)

nav.obstacle_map_learned_count = 200001
check("over the limit -> work", nav:HasPendingMapWork() == true)

nav.obstacle_map_learned_flush_cells = 0
check("flush disabled -> no work", nav:HasPendingMapWork() == false)

print("")
print("== 2. the maintenance timer parks itself when there is nothing to do ==")
nav, core = new_trio()
nav.obstacle_map_resident_radius = 10
nav.is_base_image_loaded = true
nav.obstacle_map_learned_flush_cells = 200000
nav.obstacle_map_learned_count = 0

local maintain_calls = 0
nav.MaintainObstacleMapCache = function(self)
    maintain_calls = maintain_calls + 1
end

clear_timers()
core:EnsureObstacleMapPreloadTimer(0.05)
check("timer registered", live_timer_count() == 1, "got " .. live_timer_count())
check("flag active after register", core.is_obstacle_map_preload_timer_active == true)
fire(1)
check("idle tick did NOT reach MaintainObstacleMapCache", maintain_calls == 0,
    "got " .. maintain_calls)
check("timer parked itself", core.is_obstacle_map_preload_timer_active == false)
check("timer is dead", live_timer_count() == 0, "got " .. live_timer_count())
fire(5)
check("parked timer stays parked", maintain_calls == 0, "got " .. maintain_calls)

print("")
print("== 3. the maintenance timer works while there IS work ==")
nav.obstacle_map_learned_count = 200001
core:WakeObstacleMapMaintenance()
check("wake re-armed the timer", core.is_obstacle_map_preload_timer_active == true)
check("exactly one new timer", live_timer_count() == 1, "got " .. live_timer_count())
fire(3)
check("maintenance ran once per fire", maintain_calls == 3, "got " .. maintain_calls)
check("still active while busy", core.is_obstacle_map_preload_timer_active == true)

print("")
print("== 4. wake is a no-op while already active ==")
local woke = core:WakeObstacleMapMaintenance()
check("wake returns false when active", woke == false)
check("no duplicate timer", live_timer_count() == 1, "got " .. live_timer_count())

print("")
print("== 5. StopObstacleMapMaintenance tears it down ==")
core:StopObstacleMapMaintenance()
check("flag cleared", core.is_obstacle_map_preload_timer_active == false)
check("timer handle cleared", core.obstacle_map_maintenance_timer == nil)
check("timer halted", live_timer_count() == 0, "got " .. live_timer_count())
fire(3)
check("nothing runs after stop", maintain_calls == 3, "got " .. maintain_calls)


print("")
print("== 6. recording past the flush threshold wakes the parked timer ==")
clear_timers()
nav.obstacle_map_learned_count = 0
nav.obstacle_map_learned_flush_cells = 3
core:EnsureObstacleMapPreloadTimer(0.05)
fire(1)
check("parked first", core.is_obstacle_map_preload_timer_active == false)

for i = 1, 3 do
    nav:SetObstacleCell("10_" .. i .. "_0", true)
end
check("at the threshold still parked", core.is_obstacle_map_preload_timer_active == false,
    "learned=" .. tostring(nav.obstacle_map_learned_count))
nav:SetObstacleCell("10_4_0", true)
check("crossing the threshold woke it", core.is_obstacle_map_preload_timer_active == true,
    "learned=" .. tostring(nav.obstacle_map_learned_count))
fire(1)
check("maintenance ran after the wake", maintain_calls >= 1, "got " .. maintain_calls)

print("")
print("== 7. StartObstacleMapFill wakes a parked timer ==")
clear_timers()
core:StopObstacleMapMaintenance()
nav.obstacle_map_learned_count = 0
nav.obstacle_map_learned_flush_cells = 200000
core:EnsureObstacleMapPreloadTimer(0.05)
fire(1)
check("parked again", core.is_obstacle_map_preload_timer_active == false)
nav:StartObstacleMapFill()
check("fill start woke the timer", core.is_obstacle_map_preload_timer_active == true)

print("")
print("== 8. the real maintenance short-circuits before any C# call ==")
nav.obstacle_map_learned_count = 0
player_calls = 0
Navigation.MaintainObstacleMapCache(nav)
check("idle maintenance never reads Game.GetPlayer", player_calls == 0,
    "got " .. player_calls)
nav.obstacle_map_learned_count = 200001
Navigation.MaintainObstacleMapCache(nav)
check("busy maintenance does read the player", player_calls >= 1, "got " .. player_calls)

print("")
print("== 9. B-3: the LTBF poll only exists while aboard ==")
DAV.is_valid_ltbf = false
local ev = setmetatable({ log_obj = Log:New() }, Event)
check("invalid LTBF -> no poll", ev:StartLTBFCompatPoll() == false)
check("no timer created", ev.ltbf_poll_timer == nil)

DAV.is_valid_ltbf = true
clear_timers()
local blocked = nil
local widget_deleted = nil
ev.hud_obj = {
    SetDeleteWidgetFlag = function(_, v) widget_deleted = v end,
}
ev.av_obj = {
    BlockOperation = function(_, v) blocked = v end,
    entity_id = { hash = 9 },
    GetEntity = function()
        return { FindComponentByName = function() return nil end }
    end,
}
check("valid LTBF -> poll starts", ev:StartLTBFCompatPoll() == true)
check("poll timer recorded", ev.ltbf_poll_timer ~= nil)
check("one timer", live_timer_count() == 1, "got " .. live_timer_count())
check("starting twice is a no-op", ev:StartLTBFCompatPoll() == false)
check("still one timer", live_timer_count() == 1, "got " .. live_timer_count())

ltbf_state.active = true
fire(1)
check("LTBF takeover blocked the AV", blocked == true)
check("widget delete flag raised", widget_deleted == true)
check("thruster check started", ev.ltbf_thruster_timer ~= nil)
ltbf_state.active = false
fire(1)
check("LTBF release unblocked the AV", blocked == false)

ev:StopLTBFCompatPoll()
check("poll timer cleared", ev.ltbf_poll_timer == nil)
check("thruster timer cleared", ev.ltbf_thruster_timer == nil)
check("all timers halted", live_timer_count() == 0, "got " .. live_timer_count())

print("")
print("== 10. B-3: stopping unwinds an active LTBF takeover ==")
ltbf_state.active = true
ev:StartLTBFCompatPoll()
fire(1)
check("takeover active before stop", ev.is_ltbf_flight_active == true)
ev:StopLTBFCompatPoll()
check("stop cleared the flag", ev.is_ltbf_flight_active == false)
check("stop unblocked the AV", blocked == false)
check("stop cleared the widget flag", widget_deleted == false)
ltbf_state.active = false

print("")
print("== 11. B-1: the garage poll is a slow safety net ==")
-- The shipped default lives in Core:New(), so build a real one rather than a
-- bare metatable instance.
local ok_new, gcore = pcall(function() return Core:New() end)
check("Core:New() succeeded", ok_new, tostring(gcore))
if ok_new then
    check("safety-net interval is 30 s", gcore.garage_update_interval == 30.0,
        "got " .. tostring(gcore.garage_update_interval))
end

local refresh_forced = nil
local refresh_calls = 0
gcore.UpdateGarageInfo = function(self, is_force)
    refresh_calls = refresh_calls + 1
    refresh_forced = is_force
end
gcore:RequestGarageRefresh("unit-test")
check("RequestGarageRefresh reached UpdateGarageInfo", refresh_calls == 1,
    "got " .. refresh_calls)
check("RequestGarageRefresh forced the refresh", refresh_forced == true,
    "got " .. tostring(refresh_forced))

print("")
print("== 12. B-3: Event:Init drops an inherited LTBF poll ==")
ltbf_state.active = false
DAV.is_ready = true
ev.ui_obj = { Init = function() end }
ev.hud_obj.Init = function() end
ev.sound_obj = { Init = function() end }
ev:StartLTBFCompatPoll()
check("poll running before Init", ev.ltbf_poll_timer ~= nil)
local ok_init = pcall(function() ev:Init(ev.av_obj) end)
check("Event:Init did not error", ok_init)
check("Init cleared the inherited poll", ev.ltbf_poll_timer == nil,
    "still " .. tostring(ev.ltbf_poll_timer))
check("no orphan timer left", live_timer_count() == 0, "got " .. live_timer_count())
DAV.is_ready = false

-- ------------------------------------------------------- virtual clock ----
-- The 1.5 gate and the C-group throttles read os.clock(). Drive it by hand so
-- the cadence is a property of the code and not of how fast the machine that
-- runs the test happens to be.
local vtime = 0
os.clock = function() return vtime end

local function run_ticks(n, fn)
    for _ = 1, n do
        vtime = vtime + 0.01
        fn()
    end
end

-- ============================================ 1.5: Engine dead-entity gate ==
print("== 13. 1.5: Engine:Update stops at a dead entity ==")
local Engine = require("Modules/engine.lua")
local engine = setmetatable({ log_obj = Log:New() }, Engine)
engine.is_finished_init = true
engine.engine_control_type = Def.EngineControlType.ChangeVelocity
local menu_probes, physics_probes, velocity_writes = 0, 0, 0
engine.GetPhysicsState = function() physics_probes = physics_probes + 1; return 0 end
engine.UnsetPhysicsState = function() end
engine.ChangeVelocity = function() velocity_writes = velocity_writes + 1 end

engine.av_obj = nil
engine:Update(0.01)
check("no av_obj -> nothing runs", menu_probes == 0 and physics_probes == 0)

engine.av_obj = { entity_id = nil }
engine:Update(0.01)
check("despawned AV -> no menu probe", menu_probes == 0, "got " .. menu_probes)
check("despawned AV -> no physics probe", physics_probes == 0, "got " .. physics_probes)

engine.av_obj = {
    entity_id = { hash = 7 },
    core_obj = {
        event_obj = {
            IsInMenuOrPopupOrPhoto = function()
                menu_probes = menu_probes + 1
                return false
            end,
        },
    },
}
engine:Update(0.01)
check("live entity -> menu probe ran", menu_probes == 1, "got " .. menu_probes)
check("live entity -> velocity control ran", velocity_writes == 1, "got " .. velocity_writes)

-- ============================================ C-group: throttled checks ====
print("")
print("== 14. C-group: the always-on checks are paced ==")
EVehicleDoor = EVehicleDoor or { seat_front_left = 1 }
VehicleDoorState = VehicleDoorState or { Closed = 1, Open = 2 }

local c = {}
local function bump(k) c[k] = (c[k] or 0) + 1 end
local function reset_counts() for k in pairs(c) do c[k] = nil end end

local ok_ev, ev2 = pcall(function() return Event:New() end)
check("Event:New() succeeded", ok_ev, tostring(ev2))
check("shipped C-group intervals",
    ev2.mount_check_interval == 0.05
    and ev2.door_check_interval == 0.1
    and ev2.engine_check_interval == 0.2
    and ev2.destroyed_check_interval == 0.1
    and ev2.combat_check_interval == 0.2
    and ev2.consume_slot_check_interval == 1.0,
    string.format("mount=%s door=%s engine=%s destroyed=%s combat=%s consume=%s",
        tostring(ev2.mount_check_interval), tostring(ev2.door_check_interval),
        tostring(ev2.engine_check_interval), tostring(ev2.destroyed_check_interval),
        tostring(ev2.combat_check_interval), tostring(ev2.consume_slot_check_interval)))

ev2.current_situation = Def.Situation.Normal
ev2.hud_obj = {
    IsVisibleConsumeItemSlot = function() bump("consume"); return false end,
    SetVisibleConsumeItemSlot = function() end,
    SetHPDisplay = function() end,
    ToggleOriginalMPHDisplay = function() end,
    EnableManualMeter = function() end,
    SetSpeedMeterValue = function() end,
    SetRPMMeterValue = function() end,
}
ev2.av_obj = {
    is_enable_manual_rpm_meter = false,
    is_combat = false,
    IsPlayerIn = function() bump("mount"); return false end,
    GetDoorState = function() bump("door"); return VehicleDoorState.Closed end,
    IsEngineOn = function() bump("engine"); return true end,
    IsDestroyed = function() bump("destroyed"); return false end,
    GetCurrentSpeed = function() return 0 end,
    IsPlayerInEntryArea = function() return false end,
    engine_obj = { GetRPMCount = function() return 0 end },
}
DAV.core_obj = { event_obj = ev2, StopAllButtonHolds = function() end }

local function reset_throttles(e)
    e.last_mount_check_time = 0
    e.last_door_check_time = 0
    e.last_engine_check_time = 0
    e.last_destroyed_check_time = 0
    e.last_combat_check_time = 0
    e.last_consume_slot_check_time = 0
end

reset_counts(); reset_throttles(ev2)
run_ticks(100, function() ev2:CheckInAV() end)
check("C-1 CheckInAV runs 20x per 100 ticks", c.mount == 20, "got " .. tostring(c.mount))

reset_counts(); reset_throttles(ev2)
run_ticks(100, function() ev2:CheckDoor() end)
check("C-2 CheckDoor runs 10x per 100 ticks", c.door == 10, "got " .. tostring(c.door))

reset_counts(); reset_throttles(ev2)
run_ticks(100, function() ev2:CheckEngine() end)
check("C-3 CheckEngine runs 5x per 100 ticks", c.engine == 5, "got " .. tostring(c.engine))

reset_counts(); reset_throttles(ev2)
run_ticks(100, function() ev2:CheckDestroyed() end)
check("C-3 CheckDestroyed runs 10x per 100 ticks", c.destroyed == 10, "got " .. tostring(c.destroyed))

reset_counts(); reset_throttles(ev2)
local pc_before = player_calls
run_ticks(100, function() ev2:CheckCombat() end)
check("C-4 CheckCombat runs 5x per 100 ticks", player_calls - pc_before == 5,
    "got " .. (player_calls - pc_before))

reset_counts(); reset_throttles(ev2)
run_ticks(100, function() ev2:CheckHUD() end)
check("C-5 consume-slot check runs 1x per 100 ticks", c.consume == 1, "got " .. tostring(c.consume))

-- ============================================ C-6: entry-area pacing =======
print("")
print("== 15. C-6: the entry-area re-resolve is paced ==")
local av2 = setmetatable({ log_obj = Log:New() }, AV)
av2.entry_area_check_interval = 0.05
av2._entry_area = nil
av2._entry_area_frame = -1
av2._entry_area_next_time = 0
local computes = 0
av2.ComputePlayerInEntryArea = function()
    computes = computes + 1
    return computes % 2 == 0
end

DAV.frame_seq = 0
run_ticks(100, function()
    DAV.frame_seq = DAV.frame_seq + 1
    av2:IsPlayerInEntryArea()
end)
-- vtime is built by repeated +0.01, so the accumulated float never lands
-- exactly on the booked next-time and a few slots slip per second. The same
-- drift shows up as 17/100 in situation_cost_test. What matters is that the
-- rate is ~20 Hz and not 100 Hz.
check("C-6 recomputes ~20x per 100 ticks, not 100x",
    computes >= 15 and computes <= 20, "got " .. computes)

DAV.frame_seq = 5000
av2:InvalidateEntryAreaCache()
computes = 0
av2:IsPlayerInEntryArea()
av2:IsPlayerInEntryArea()
av2:IsPlayerInEntryArea()
check("same frame still caches to one compute", computes == 1, "got " .. computes)

av2:InvalidateEntryAreaCache()
computes = 0
av2:IsPlayerInEntryArea()
check("invalidate drops the throttle and recomputes", computes == 1, "got " .. computes)

print("")
print(string.format("demand_driven_test: %d passed, %d failed", pass, fail))
if fail > 0 then error("demand_driven_test failed") end

