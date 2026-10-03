-- =============================================================================
-- Control-loop gate test (docs/PERF_PLAN_event_driven.md, A群)
--
-- A群 stops the control-loop BODY from running when the situation has nothing
-- for it to do. What has to hold:
--
--   * Idle / Normal sleep: neither CheckAllEvents nor GetActions runs.
--   * The garage safety heartbeat and any pending input still open the gate.
--   * Waiting paces CheckAllEvents to ~20 Hz but keeps GetActions at full rate
--     (AV:MoveThruster integrates per call against DAV.dt_scale).
--   * Landing / TalkingOff / InVehicle never skip.
--   * A situation change seen inside CheckAllEvents re-opens the gate.
--   * The measured-dt sampler keeps ticking while asleep -- no spike on wake.
--   * The Cron timer itself is never paused, so Cron.After still fires.
--
-- Core is driven off the shipped metatable with a counting event_obj / queue_obj
-- so ControlTick and ControlLoopState are the real shipped methods.
--
-- Run:  python tests/run_loop_gate_test.py
-- =============================================================================

local MODDIR = ...

-- ---------------------------------------------------------------- stubs ----
Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
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

-- A Cron we can drive by hand. init.lua calls Cron.Update(delta) from onUpdate;
-- the mod's own timers are registered with Cron.Every / Cron.After.
local timers = {}
Cron = {}
function Cron.Every(period, a, b)
    local cb = (type(a) == "function") and a or b
    local state = (type(a) == "table") and a or nil
    local t = { period = period, cb = cb, state = state, alive = true }
    timers[#timers + 1] = t
    return t
end
function Cron.After(delay, cb)
    local t = { period = delay, cb = cb, state = nil, alive = true,
                is_after = true, remaining = delay }
    timers[#timers + 1] = t
    return t
end
function Cron.Halt(t)
    if t ~= nil then t.alive = false end
end
function Cron.Pause(t)
    if t ~= nil then t.paused = true end
end
function Cron.Resume(t)
    if t ~= nil then t.paused = false end
end

--- Mirror of the Cron.Update(delta) that init.lua drives every frame.
--- After-timers are one-shot, matching the real Cron.
local function cron_update(dt)
    for _, t in ipairs(timers) do
        if t.alive and t.is_after and not t.paused then
            t.remaining = t.remaining - dt
            if t.remaining <= 0 then
                t.alive = false
                t.cb()
            end
        end
    end
end

DAV = {
    frame_seq = 0,
    model_index = 1,
    model_type_index = 1,
    time_resolution = 0.01,
    dt_scale = 1.0,
    is_debug_mode = false,
    user_setting_table = {
        time_resolution = 0.01,
        time_scale_mode = "nominal",
        garage_info_list = {},
    },
}

Game = {
    GetPlayer = function()
        return { GetWorldPosition = function() return Vector4.new(0, 0, 0, 1) end }
    end,
}

-- lupa is stock Lua 5.1 and rejects `goto` / `::label::`, which LuaJIT (what
-- CET actually embeds) accepts. Same neutralisation as the other suites.
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
    package.preload[(name:gsub("%.lua$", ""))] = chunk
end

preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Etc/timescale.lua")
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
local TimeScale = require("Etc/timescale.lua")
local Core = require("Modules/core.lua")

-- ------------------------------------------------------------- harness -----
local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1; print("  [PASS] " .. name)
    else fail = fail + 1; print("  [FAIL] " .. name .. (detail and ("  " .. detail) or "")) end
end

-- Virtual clock: the gate reads os.clock(), so drive it rather than trusting
-- how fast the test machine happens to run.
local vtime = 0
os.clock = function() return vtime end

--- A Core whose heavy collaborators are counters. Only the fields ControlTick
--- and ControlLoopState touch are provided, so the shipped gate logic runs
--- unchanged against a stub world.
local counters
local function new_core(situation)
    counters = { check_all = 0, get_actions = 0 }
    local core = setmetatable({}, Core)
    core.log_obj = Log:New()
    core.waiting_loop_interval = 0.05
    core.last_waiting_loop_time = 0
    core.is_control_loop_sleeping = false
    core.garage_update_interval = 30.0
    -- Deliberately in the future so the heartbeat is NOT what opens the gate.
    core.last_garage_update_time = 1e6
    -- Keep the measured-dt sampler honest: a stale value here would make the
    -- first tick measure the whole time since the test started.
    core.last_control_time = vtime
    core.queue_obj = {
        _items = {},
        IsEmpty = function(self) return #self._items == 0 end,
    }
    core.event_obj = {
        current_situation = situation or Def.Situation.Normal,
        CheckAllEvents = function()
            counters.check_all = counters.check_all + 1
        end,
    }
    core.GetActions = function()
        counters.get_actions = counters.get_actions + 1
    end
    return core
end

--- Run n control ticks, advancing the virtual clock 0.01 s each and driving the
--- Cron the same way init.lua does.
local function run_ticks(core, n)
    for _ = 1, n do
        vtime = vtime + 0.01
        core:ControlTick()
        cron_update(0.01)
    end
end

local function enqueue(core, action)
    table.insert(core.queue_obj._items, action)
end

-- ===================================================================== 1 ===
print("== 1. Idle / Normal sleep ==")
local core = new_core(Def.Situation.Normal)
run_ticks(core, 100)
print(string.format("    Normal, 100 ticks: CheckAllEvents=%d GetActions=%d",
    counters.check_all, counters.get_actions))
check("Normal runs neither half of the body",
    counters.check_all == 0 and counters.get_actions == 0,
    string.format("checks=%d actions=%d", counters.check_all, counters.get_actions))
check("Normal is flagged as sleeping", core.is_control_loop_sleeping == true)
check("ControlLoopState reports sleep", core:ControlLoopState() == "sleep")

core = new_core(Def.Situation.Idle)
run_ticks(core, 100)
check("Idle runs neither half either",
    counters.check_all == 0 and counters.get_actions == 0,
    string.format("checks=%d actions=%d", counters.check_all, counters.get_actions))

-- ===================================================================== 2 ===
print("")
print("== 2. the garage heartbeat still opens the gate ==")
core = new_core(Def.Situation.Normal)
-- Put the last refresh 31 s in the past so the 30 s safety net is due.
core.last_garage_update_time = vtime - 31.0
run_ticks(core, 1)
check("a due heartbeat runs the body", counters.check_all == 1 and counters.get_actions == 1,
    string.format("checks=%d actions=%d", counters.check_all, counters.get_actions))
-- The heartbeat is only useful if it does not stay open forever.
core.last_garage_update_time = vtime
run_ticks(core, 50)
check("it closes again once refreshed", counters.check_all == 1, "got " .. counters.check_all)

-- ===================================================================== 3 ===
print("")
print("== 3. pending input outranks the gate ==")
core = new_core(Def.Situation.Normal)
run_ticks(core, 10)
check("still asleep before input", counters.check_all == 0)
enqueue(core, { Def.ActionList.Enter, 1 })
run_ticks(core, 1)
check("a queued action opens the gate", counters.check_all == 1 and counters.get_actions == 1,
    string.format("checks=%d actions=%d", counters.check_all, counters.get_actions))
check("state says run", core:ControlLoopState() == "run")

-- ===================================================================== 4 ===
print("")
print("== 4. Waiting: CheckAllEvents paced, GetActions kept at full rate ==")
core = new_core(Def.Situation.Waiting)
run_ticks(core, 100)
print(string.format("    Waiting, 100 ticks: CheckAllEvents=%d GetActions=%d",
    counters.check_all, counters.get_actions))
-- vtime is built by repeated +0.01 so the accumulated float never lands exactly
-- on the booked next-time and a slot slips now and then; what matters is that the
-- rate is ~20 Hz and not 100 Hz.
check("CheckAllEvents drops to ~20 per 100 ticks",
    counters.check_all >= 15 and counters.check_all <= 20, "got " .. counters.check_all)
check("GetActions still runs every tick", counters.get_actions == 100,
    "got " .. counters.get_actions)
check("Waiting is not flagged as sleeping", core.is_control_loop_sleeping == false)

-- A hotkey while Waiting must not wait for the pacing slot.
core = new_core(Def.Situation.Waiting)
run_ticks(core, 3)
local checks_before = counters.check_all
enqueue(core, { Def.ActionList.Enter, 1 })
run_ticks(core, 1)
check("input during a paced window runs immediately",
    counters.check_all == checks_before + 1,
    string.format("before=%d after=%d", checks_before, counters.check_all))

-- ===================================================================== 5 ===
print("")
print("== 5. Landing / TalkingOff / InVehicle never skip ==")
for _, s in ipairs({ Def.Situation.Landing, Def.Situation.TalkingOff, Def.Situation.InVehicle }) do
    core = new_core(s)
    run_ticks(core, 100)
    check("situation " .. tostring(s) .. " runs both halves every tick",
        counters.check_all == 100 and counters.get_actions == 100,
        string.format("checks=%d actions=%d", counters.check_all, counters.get_actions))
end

-- ===================================================================== 6 ===
print("")
print("== 6. a situation change re-opens the gate ==")
core = new_core(Def.Situation.InVehicle)
core.event_obj.CheckAllEvents = function(self)
    counters.check_all = counters.check_all + 1
    -- stand in for the real transition the shipped checks would perform
    self.current_situation = Def.Situation.Waiting
end
run_ticks(core, 1)
check("the transition tick ran", counters.check_all == 1, "got " .. counters.check_all)
check("the transition woke the loop", core.last_waiting_loop_time == 0,
    "got " .. tostring(core.last_waiting_loop_time))
run_ticks(core, 1)
check("the very next tick runs too", counters.check_all == 2, "got " .. counters.check_all)
run_ticks(core, 1)
check("and the pacing then takes hold", counters.check_all == 2, "got " .. counters.check_all)

-- ===================================================================== 7 ===
print("")
print("== 7. the measured-dt sampler keeps ticking through a sleep ==")
TimeScale:Set(0.01, TimeScale.MODE_MEASURED)
core = new_core(Def.Situation.Normal)
run_ticks(core, 1)
local t1 = core.last_control_time
local dt_before = DAV.dt_scale
run_ticks(core, 100)
check("the sampler keeps updating last_control_time while asleep",
    math.abs(core.last_control_time - (t1 + 1.0)) < 1e-6,
    string.format("t1=%.3f now=%.3f", t1, core.last_control_time))
check("dt_scale settles and stays put across 1 s of sleeping",
    math.abs(DAV.dt_scale - dt_before) < 1e-6,
    string.format("before=%.6f after=%.6f", dt_before, DAV.dt_scale))
-- Waking must not integrate the whole sleep as one dt: the measured dt on the
-- first awake tick is one Cron period, not the sleep length.
core.event_obj.current_situation = Def.Situation.InVehicle
run_ticks(core, 1)
local dt_after_wake = DAV.dt_scale
check("waking from a 1 s sleep does not spike dt_scale",
    math.abs(dt_after_wake - dt_before) < 1e-6,
    string.format("sleep=%.6f wake=%.6f", dt_before, dt_after_wake))
TimeScale:Set(0.01, TimeScale.MODE_NOMINAL)

-- ===================================================================== 8 ===
print("")
print("== 8. the Cron timer itself is untouched, so deferred work survives ==")
local fired = 0
Cron.After(0.5, function() fired = fired + 1 end)
local loop_timer = Cron.Every(0.01, function() end)
core = new_core(Def.Situation.Normal)
core.main_loop_timer = loop_timer
run_ticks(core, 100)
check("Cron.After fired while the body was asleep", fired == 1, "got " .. fired)
check("the main loop timer was never halted", loop_timer.alive == true)
check("the main loop timer was never paused", loop_timer.paused ~= true)

print("")
print(string.format("loop_gate_test: %d passed, %d failed", pass, fail))
if fail > 0 then error("loop_gate_test failed") end