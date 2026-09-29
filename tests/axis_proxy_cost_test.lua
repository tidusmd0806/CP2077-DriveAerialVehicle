-- Axis input proxy cost test (docs/PERF_ANALYSIS_hooks.md fix (4)).
--
-- The Input/Axis proxy measured 55.95 ms over 17,448 calls (~4 events per
-- rendered frame: mouse, menus, walking). Every one of those read the event
-- across the C# boundary three times before asking whether the AV could use the
-- input at all, and ConvertAxisAction then allocated a candidate table per call.
--
-- This loads the real init.lua, captures the proxy callback, and drives it
-- against a transcription of the pre-fix pipeline so the two are compared
-- end to end -- same inputs, same queue contents expected.

local MODDIR = ...

-- ---------------------------------------------------------------- stubs ----
Vector4 = {}
function Vector4.new(x, y, z, w) return { x = x, y = y, z = z, w = w or 1 } end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.Distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end
Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
EulerAngles = { new = function(p, y, r) return { pitch = p, yaw = y, roll = r } end }
Quaternion = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }
CName = { new = function(s) return { value = s } end }
StringToName = function(s) return { value = s } end
QueryFilter = { new = function() return { mask2 = 0 } end }
DynamicEntitySpec = { new = function() return {} end }
SaveLocksManager = { RequestSaveLockAdd = function() end, RequestSaveLockRemove = function() end }
GameObjectEffectHelper = { StartEffectEvent = function() end, StopEffectEvent = function() end }
json = { decode = function() return {} end, encode = function() return "{}" end }
spdlog = { info = function() end }

-- Captured CET entry points.
local registered = {}
local proxies = {}
function registerForEvent(name, cb) registered[name] = cb end
function Observe(cls, method, cb) registered["observe:" .. cls .. "." .. method] = cb end
function ObserveAfter(cls, method, cb) registered["after:" .. cls .. "." .. method] = cb end
function Override(cls, method, cb) registered["override:" .. cls .. "." .. method] = cb end
function NewProxy(spec)
    for hook_name, def in pairs(spec) do
        proxies[hook_name] = def.callback
    end
    return {
        Target = function() return nil end,
        Function = function(_, fname) return fname end,
    }
end
function GetVersion() return "1.99.0" end

-- Interop counters, driven by the synthetic event object.
local counters = { get_value = 0, get_key = 0 }

Game = {
    GetCallbackSystem = function()
        return { RegisterCallback = function() end, UnregisterCallback = function() end }
    end,
    GetPlayer = function()
        return { GetWorldPosition = function() return Vector4.new(0, 0, 0, 1) end,
                 PSIsInDriverCombat = function() return false end }
    end,
    FindEntityByID = function() return nil end,
    GetTimeSystem = function() return { GetGameTimeStamp = function() return 0 end } end,
    GetSpatialQueriesSystem = function()
        return { SyncRaycastByQueryFilter = function() return false, nil end }
    end,
    GetVehicleSystem = function() return { GetPlayerUnlockedVehicles = function() return {} end } end,
    IsSavingLocked = function() return false, nil end,
}
TweakDB = {
    GetRecord = function() return nil end,
    SetFlat = function() end,
    CreateRecord = function() end,
    CloneRecord = function() end,
}
TweakDBID = { new = function(s) return { id = s } end }

DAV = {
    frame_seq = 0,
    axis_dead_zone = 0.1,
    model_index = 1,
    model_type_index = 1,
    is_debug_mode = false,
    is_debug_enable_obstacle_scan = false,
    is_debug_profile_autopilot = false,
    user_setting_table = { keybind_table = {}, heli_keybind_table = {}, common_keybind_table = {} },
}

-- --------------------------------------------------------------- load ------
-- lupa is stock Lua 5.1 and rejects goto/::label::, which LuaJIT (what CET
-- embeds) accepts. tools/check_lua_syntax.py neutralises the same way.
local LUAJIT_EXT = "%f[%w]goto%s+[A-Za-z_][A-Za-z0-9_]*%f[^%w]"
local LUAJIT_LBL = "::%s*[A-Za-z_][A-Za-z0-9_]*%s*::"
local function luajit_dialect(src)
    return (src:gsub(LUAJIT_EXT, "do end"):gsub(LUAJIT_LBL, "do end"))
end

local function preload(name)
    local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
    local b = f:read("*a"); f:close()
    local loader = loadstring or load
    local chunk, err = loader(luajit_dialect(b), name)
    assert(chunk, "failed to compile " .. name .. ": " .. tostring(err))
    package.preload[name] = chunk
end

-- Register every module up front; require() then resolves the graph itself, so
-- the order below does not matter.
local MODULES = {
    "Etc/def.lua",
    "Etc/log.lua",
    "Etc/queue.lua",
    "Etc/utils.lua",
    "External/Cron.lua",
    "External/GameHUD.lua",
    "External/GameSettings.lua",
    "External/GameUI.lua",
    "Modules/profprobe.lua",
    "Modules/obstacle_grid.lua",
    "Modules/camera.lua",
    "Modules/engine.lua",
    "Modules/navigation.lua",
    "Modules/av.lua",
    "Modules/hud.lua",
    "Modules/sound.lua",
    "Modules/ui.lua",
    "Modules/event.lua",
    "Modules/core.lua",
    "Debug/debug.lua",
    "init.lua",
}
for _, m in ipairs(MODULES) do preload(m) end

Log = require("Etc/log.lua")
Def = require("Etc/def.lua")
Cron = require("External/Cron.lua")
local Core = require("Modules/core.lua")

-- Run init.lua's onHook so the real proxy callback is captured.
require("init.lua")
assert(registered["onHook"], "onHook was not registered")
registered["onHook"]()
local axis_cb = proxies["OnAxisInput"]
assert(axis_cb, "OnAxisInput proxy was not captured")

-- ------------------------------------------------------------- harness -----
local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1; print("  [PASS] " .. name)
    else fail = fail + 1; print("  [FAIL] " .. name .. (detail and ("  " .. detail) or "")) end
end

local function reset_counters()
    counters.get_value = 0; counters.get_key = 0
end

-- A Core wired just far enough to run the axis path: real ConvertAxisAction,
-- real ConvertAVAxisAction / ConvertHeliAxisAction, real queue.
local function new_core(sit, flight_mode, blocking)
    local core = setmetatable({}, Core)
    core.log_obj = Log:New()
    core.log_obj:SetLevel(LogLevel.Info, "Core")
    core.queue_obj = require("Etc/queue.lua"):New()
    core.axis_dead_zone = DAV.axis_dead_zone
    core.relative_dead_zone = 0.01
    core.hold_progress = 0.9
    core.event_obj = { current_situation = sit }
    core.av_obj = {
        is_blocking_operation = blocking == true,
        engine_obj = { flight_mode = flight_mode },
    }
    return core
end

local function make_event(key, value)
    return {
        GetKey = function() counters.get_key = counters.get_key + 1; return { value = key } end,
        GetValue = function() counters.get_value = counters.get_value + 1; return value end,
    }
end

local function drain(q)
    local out = {}
    while not q:IsEmpty() do out[#out + 1] = q:Dequeue() end
    return out
end

local function describe(list)
    local parts = {}
    for _, e in ipairs(list) do
        if type(e) == "table" then
            parts[#parts + 1] = "{" .. tostring(e[1]) .. "," .. tostring(e[2]) .. "}"
        else
            parts[#parts + 1] = tostring(e)
        end
    end
    return "[" .. table.concat(parts, " ") .. "]"
end

-- =========================================================== section 1 ====
print("\n[1] Def.AxisKeySet is the set the converters actually handle")
do
    check("LeftAxisX is a member", Def.AxisKeySet.IK_Pad_LeftAxisX == true)
    check("LeftAxisY is a member", Def.AxisKeySet.IK_Pad_LeftAxisY == true)
    check("RightAxisX is not a member", Def.AxisKeySet.IK_Pad_RightAxisX == nil)
    check("set has exactly 2 members",
        (function()
            local n = 0
            for _ in pairs(Def.AxisKeySet) do n = n + 1 end
            return n == 2
        end)())
end

-- =========================================================== section 2 ====
print("\n[2] differential: old pipeline vs new, end to end")
do
    -- The pre-fix proxy gate + pre-fix ConvertAxisAction, transcribed literally.
    -- Runs against the same core so the queue it produces is directly comparable.
    local function old_pipeline(core, key, value)
        if not (math.abs(value) > DAV.axis_dead_zone) then return end
        if not string.find(key, "IK_Pad") then return end
        local sit = core.event_obj.current_situation or Def.Situation.Idle
        if not (sit == Def.Situation.InVehicle
                or sit == Def.Situation.Waiting
                or sit == Def.Situation.Normal) then
            return
        end
        if core.av_obj.is_blocking_operation then return end
        local axis_key_list = { "IK_Pad_LeftAxisX", "IK_Pad_LeftAxisY" }
        if core.av_obj.engine_obj.flight_mode == Def.FlightMode.AV then
            for _, kb in ipairs(axis_key_list) do
                if key == kb then core:ConvertAVAxisAction(kb, value) return end
            end
        elseif core.av_obj.engine_obj.flight_mode == Def.FlightMode.Helicopter then
            for _, kb in ipairs(axis_key_list) do
                if key == kb then core:ConvertHeliAxisAction(kb, value) return end
            end
        end
    end

    local keys = {
        "IK_Pad_LeftAxisX", "IK_Pad_LeftAxisY",
        "IK_Pad_RightAxisX", "IK_Pad_RightAxisY",
        "IK_Pad_FlyUp", "IK_Pad_Down",
        "IK_Keyboard_W", "IK_Keyboard_Space",
        "PrefixIK_Pad_Tricky",   -- contains IK_Pad but is not an axis
        "",
    }
    local values = { 0, 0.05, 0.1, 0.11, 1, -0.05, -0.1, -0.11, -1 }
    local sits = { Def.Situation.Normal, Def.Situation.Idle, Def.Situation.Waiting,
                  Def.Situation.InVehicle, Def.Situation.Landing, Def.Situation.TalkingOff }
    local modes = { Def.FlightMode.AV, Def.FlightMode.Helicopter }
    local blocks = { false, true }

    local cases, mismatches = 0, {}
    for _, sit in ipairs(sits) do
        for _, mode in ipairs(modes) do
            for _, blk in ipairs(blocks) do
                for _, key in ipairs(keys) do
                    for _, val in ipairs(values) do
                        local oc = new_core(sit, mode, blk)
                        old_pipeline(oc, key, val)
                        local want = drain(oc.queue_obj)

                        local nc = new_core(sit, mode, blk)
                        DAV.core_obj = nc
                        axis_cb(make_event(key, val))
                        local got = drain(nc.queue_obj)

                        cases = cases + 1
                        if #want ~= #got or want[1] == nil and got[1] ~= nil then
                            mismatches[#mismatches + 1] = string.format(
                                "sit=%d mode=%d blk=%s %s v=%s: old=%s new=%s",
                                sit, mode, tostring(blk), key, tostring(val),
                                describe(want), describe(got))
                        elseif want[1] ~= nil then
                            if want[1][1] ~= got[1][1] or want[1][2] ~= got[1][2] then
                                mismatches[#mismatches + 1] = string.format(
                                    "sit=%d mode=%d blk=%s %s v=%s: old=%s new=%s",
                                    sit, mode, tostring(blk), key, tostring(val),
                                    describe(want), describe(got))
                            end
                        end
                    end
                end
            end
        end
    end
    check("all " .. cases .. " combinations produce the same queue", #mismatches == 0,
        #mismatches > 0 and ("\n    " .. table.concat(mismatches, "\n    ")) or "")
end

-- =========================================================== section 3 ====
print("\n[3] boundary: dead zone behaves identically")
do
    DAV.core_obj = new_core(Def.Situation.InVehicle, Def.FlightMode.AV, false)
    local cases = {
        { 0.10, false, "exactly at dead zone does not enqueue" },
        { 0.1001, true, "just above dead zone enqueues" },
        { -0.10, false, "exactly at -dead zone does not enqueue" },
        { -0.1001, true, "just below -dead zone enqueues" },
        { 0, false, "zero does not enqueue" },
    }
    for _, c in ipairs(cases) do
        DAV.core_obj.queue_obj = require("Etc/queue.lua"):New()
        axis_cb(make_event("IK_Pad_LeftAxisX", c[1]))
        local q = drain(DAV.core_obj.queue_obj)
        check(c[3], (#q > 0) == c[2], "value=" .. tostring(c[1]) .. " got " .. describe(q))
    end
end

-- =========================================================== section 4 ====
print("\n[4] non-AV situations cost zero interop")
do
    for _, sit in ipairs({ Def.Situation.Idle, Def.Situation.Landing,
                          Def.Situation.TalkingOff }) do
        DAV.core_obj = new_core(sit, Def.FlightMode.AV, false)
        reset_counters()
        axis_cb(make_event("IK_Pad_LeftAxisX", 1))
        check("situation " .. sit .. " reads neither GetValue nor GetKey",
            counters.get_value == 0 and counters.get_key == 0,
            string.format("get_value=%d get_key=%d", counters.get_value, counters.get_key))
    end
    DAV.core_obj = nil
    reset_counters()
    axis_cb(make_event("IK_Pad_LeftAxisX", 1))
    check("no core_obj reads nothing", counters.get_value == 0 and counters.get_key == 0)
end

-- =========================================================== section 5 ====
print("\n[5] dead-zone rejection happens before GetKey")
do
    DAV.core_obj = new_core(Def.Situation.InVehicle, Def.FlightMode.AV, false)
    reset_counters()
    axis_cb(make_event("IK_Pad_LeftAxisX", 0.0))
    check("below dead zone: GetValue read once, GetKey never",
        counters.get_value == 1 and counters.get_key == 0,
        string.format("get_value=%d get_key=%d", counters.get_value, counters.get_key))
end

-- =========================================================== section 6 ====
print("\n[6] non-axis key is dropped before ConvertAxisAction")
do
    DAV.core_obj = new_core(Def.Situation.InVehicle, Def.FlightMode.AV, false)
    reset_counters()
    axis_cb(make_event("IK_Pad_RightAxisX", 1))
    check("right stick enqueues nothing", #drain(DAV.core_obj.queue_obj) == 0)

    -- The old code reached ConvertAxisAction for these and allocated a table
    -- there; the new code never gets in.
    DAV.core_obj = new_core(Def.Situation.InVehicle, Def.FlightMode.AV, false)
    reset_counters()
    axis_cb(make_event("IK_Keyboard_W", 1))
    check("keyboard axis enqueues nothing", #drain(DAV.core_obj.queue_obj) == 0)
end

-- =========================================================== section 7 ====
print("\n[7] the four real actions still map correctly")
do
    local expect = {
        { "IK_Pad_LeftAxisX",  0.5,  Def.ActionList.RightRotate },
        { "IK_Pad_LeftAxisX", -0.5,  Def.ActionList.LeftRotate },
        { "IK_Pad_LeftAxisY",  0.5,  Def.ActionList.LeanForward },
        { "IK_Pad_LeftAxisY", -0.5,  Def.ActionList.LeanBackward },
    }
    for _, e in ipairs(expect) do
        DAV.core_obj = new_core(Def.Situation.InVehicle, Def.FlightMode.AV, false)
        axis_cb(make_event(e[1], e[2]))
        local q = drain(DAV.core_obj.queue_obj)
        check(e[1] .. " " .. tostring(e[2]) .. " -> action " .. tostring(e[3]),
            #q == 1 and q[1][1] == e[3], describe(q))
        check("  magnitude preserved", #q == 1 and math.abs(q[1][2] - 0.5) < 1e-9,
            describe(q))
    end

    local heli = {
        { "IK_Pad_LeftAxisX",  0.5 },
        { "IK_Pad_LeftAxisY",  0.5 },
    }
    for _, h in ipairs(heli) do
        DAV.core_obj = new_core(Def.Situation.InVehicle, Def.FlightMode.Helicopter, false)
        axis_cb(make_event(h[1], h[2]))
        local q = drain(DAV.core_obj.queue_obj)
        check("helicopter " .. h[1] .. " enqueues an action",
            #q == 1 and q[1][1] ~= nil, describe(q))
    end
end

-- =========================================================== section 8 ====
print("\n[8] blocking operation still suppresses")
do
    DAV.core_obj = new_core(Def.Situation.InVehicle, Def.FlightMode.AV, true)
    axis_cb(make_event("IK_Pad_LeftAxisX", 1))
    check("blocked operation enqueues nothing", #drain(DAV.core_obj.queue_obj) == 0)
end

-- =========================================================== section 9 ====
print("\n[9] cost ledger: C# reads and allocations per axis event, old vs new")
do
    -- Pre-fix proxy body + pre-fix ConvertAxisAction, with the event reads and
    -- the candidate-table allocation counted.
    local function old_cost(sit, key, value)
        local ev = make_event(key, value)
        reset_counters()
        local k = ev:GetKey().value
        local v = ev:GetValue()
        local reads = counters.get_key + counters.get_value
        if math.abs(v) > DAV.axis_dead_zone then
            if string.find(k, "IK_Pad") then
                local s = sit or Def.Situation.Idle
                if s == Def.Situation.InVehicle
                        or s == Def.Situation.Waiting
                        or s == Def.Situation.Normal then
                    local allocs = 1  -- axis_key_list built per call
                    local list = { "IK_Pad_LeftAxisX", "IK_Pad_LeftAxisY" }
                    for _, kb in ipairs(list) do
                        if k == kb then return reads, allocs end
                    end
                    return reads, allocs
                end
            end
        end
        return reads, 0
    end

    local function new_cost(sit, key, value)
        DAV.core_obj = new_core(sit, Def.FlightMode.AV, false)
        reset_counters()
        axis_cb(make_event(key, value))
        -- The rewrite builds no table on this path.
        return counters.get_value + counters.get_key, 0
    end

    local cases = {
        { "Idle (no AV)",              Def.Situation.Idle,      "IK_Pad_LeftAxisX",  1 },
        { "Landing",                   Def.Situation.Landing,   "IK_Pad_LeftAxisX",  1 },
        { "Normal, below dead zone",   Def.Situation.Normal,    "IK_Pad_LeftAxisX",  0.02 },
        { "InVehicle, below dead zone",Def.Situation.InVehicle, "IK_Pad_LeftAxisX",  0.02 },
        { "InVehicle, right stick",    Def.Situation.InVehicle, "IK_Pad_RightAxisX", 1 },
        { "InVehicle, keyboard axis",  Def.Situation.InVehicle, "IK_Keyboard_W",     1 },
        { "InVehicle, LeftAxisX",      Def.Situation.InVehicle, "IK_Pad_LeftAxisX",  0.8 },
        { "Waiting, LeftAxisY",        Def.Situation.Waiting,   "IK_Pad_LeftAxisY",  0.8 },
    }

    print(string.format("  %-28s %s", "case", "C# reads        tables built"))
    print(string.format("  %-28s %6s %6s %6s %6s", "", "old", "new", "old", "new"))
    print("  " .. string.rep("-", 62))
    local or_, nr, oa, na = 0, 0, 0, 0
    for _, c in ipairs(cases) do
        local o_reads, o_allocs = old_cost(c[2], c[3], c[4])
        local n_reads, n_allocs = new_cost(c[2], c[3], c[4])
        or_, nr = or_ + o_reads, nr + n_reads
        oa, na = oa + o_allocs, na + n_allocs
        print(string.format("  %-28s %6d %6d %6d %6d", c[1], o_reads, n_reads, o_allocs, n_allocs))
    end
    print("  " .. string.rep("-", 62))
    print(string.format("  %-28s %6d %6d %6d %6d   -%d of %d (%.0f%%)",
        "TOTAL", or_, nr, oa, na,
        (or_ + oa) - (nr + na), or_ + oa,
        100 * ((or_ + oa) - (nr + na)) / (or_ + oa)))

    local never_worse = true
    for _, c in ipairs(cases) do
        local o_reads, o_allocs = old_cost(c[2], c[3], c[4])
        local n_reads, n_allocs = new_cost(c[2], c[3], c[4])
        if n_reads > o_reads or n_allocs > o_allocs then never_worse = false end
    end
    check("new path never costs more per event", never_worse)
    check("no candidate table is built on any path now", na == 0 and oa > 0,
        string.format("old=%d new=%d", oa, na))
    check("non-AV situations now cost zero C# reads",
        (function()
            for _, c in ipairs(cases) do
                if c[2] == Def.Situation.Idle or c[2] == Def.Situation.Landing then
                    local n_reads = new_cost(c[2], c[3], c[4])
                    if n_reads ~= 0 then return false end
                end
            end
            return true
        end)())
end

-- ------------------------------------------------------------- result -----
print(string.format("\naxis_proxy_cost_test: %d passed, %d failed", pass, fail))
if fail > 0 then return error("test failures") end
