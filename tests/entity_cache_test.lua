-- Entity handle cache test (docs/PERF_ANALYSIS_init441.md fix (1)).
--
-- Verifies that AV:GetEntity() resolves Game.FindEntityByID at most once per
-- rendered frame, that nil is never cached, and that Spawn/Despawn invalidate.
-- Loads the real Modules/av.lua with the CET API stubbed and a call counter on
-- the one function we want to stop calling so much.

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
QueryFilter = {
    new = function() return { mask2 = 0 } end,
    AddGroup = function() return { mask2 = 1 } end,
}
DynamicEntitySpec = { new = function() return {} end }
SaveLocksManager = { RequestSaveLockAdd = function() end, RequestSaveLockRemove = function() end }
GameObjectEffectHelper = { StartEffectEvent = function() end, StopEffectEvent = function() end }
json = { decode = function() return {} end, encode = function() return "{}" end }
spdlog = { info = function() end }
Cron = { Every = function() return 1 end, Halt = function() end, After = function() end }

DAV = {
    frame_seq = 0,
    model_index = 1,
    model_type_index = 1,
    is_debug_mode = false,
    is_debug_enable_obstacle_scan = false,
    is_debug_profile_autopilot = false,
    user_setting_table = {
        is_enable_landing_vfx = false,
        is_enable_obstacle_recording = false,
        garage_info_list = {},
        astar_calculation_precision = 100,
    },
}

-- The counter under test.
local find_calls = 0
local live_entity = nil
local deleted = {}

local function make_entity()
    return {
        IsPlayerMounted = function() return true end,
        IsDestroyed = function() return false end,
        IsEngineTurnedOn = function() return true end,
        GetWorldPosition = function() return Vector4.new(10, 20, 30, 1) end,
        GetWorldForward = function() return Vector4.new(1, 0, 0, 0) end,
        GetWorldRight = function() return Vector4.new(0, 1, 0, 0) end,
        GetWorldUp = function() return Vector4.new(0, 0, 1, 0) end,
        GetWorldOrientation = function()
            return { ToEulerAngles = function() return EulerAngles.new(0, 0, 0) end }
        end,
    }
end

Game = {
    FindEntityByID = function(id)
        find_calls = find_calls + 1
        return live_entity
    end,
    GetPlayer = function()
        return { GetWorldPosition = function() return Vector4.new(0, 0, 0, 1) end,
                 PSIsInDriverCombat = function() return false end }
    end,
    GetTimeSystem = function() return { GetGameTimeStamp = function() return 0 end } end,
    GetDynamicEntitySystem = function()
        return {
            CreateEntity = function(_, spec) return { hash = 1234 } end,
            DeleteEntity = function(_, id) deleted[#deleted + 1] = id end,
        }
    end,
    GetSpatialQueriesSystem = function()
        return { SyncRaycastByQueryFilter = function() return false, nil end }
    end,
    GetVehicleSystem = function()
        return { GetPlayerUnlockedVehicles = function() return {} end }
    end,
    IsSavingLocked = function() return false, nil end,
}

local function preload(name)
    local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
    local b = f:read("*a"); f:close()
    package.preload[name] = (loadstring or load)(b, name)
end

preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Etc/timescale.lua")
TimeScale = require("Etc/timescale.lua")
preload("Etc/def.lua")
preload("Modules/profprobe.lua")
preload("Modules/obstacle_grid.lua")
preload("Modules/camera.lua")
preload("Modules/engine.lua")
preload("Modules/navigation.lua")
preload("Modules/av.lua")

Log = require("Etc/log.lua")
local AV = require("Modules/av.lua")
local Navigation = require("Modules/navigation.lua")

-- ------------------------------------------------------------- harness -----
local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1; print("  [PASS] " .. name)
    else fail = fail + 1; print("  [FAIL] " .. name .. (detail and ("  " .. detail) or "")) end
end

local function new_av()
    -- Bare instance: we only exercise the handle cache, not AV:New's model wiring.
    local obj = setmetatable({
        log_obj = Log:New(),
        -- Navigation:New reads session fields off core_obj (all `or`-defaulted),
        -- so an empty stand-in is enough for these cache tests.
        core_obj = {},
        entity_id = nil,
        _entity = nil,
        _entity_frame = -1,
        is_enable_landing_vfx = false,
        landing_vfx_component = nil,
        is_landing_projection = false,
    }, AV)
    -- AV:New always wires a navigation object, and Spawn/Despawn invalidate its
    -- height cache alongside the entity handle, so the instance needs one.
    obj.navigation_obj = Navigation:New(obj)
    return obj
end

local function reset(frame)
    find_calls = 0
    DAV.frame_seq = frame or 0
end

print("== 1. no entity_id: zero resolution ==")
local av = new_av()
reset(10)
check("GetEntity returns nil", av:GetEntity() == nil)
check("no FindEntityByID when entity_id is nil", find_calls == 0, "got " .. find_calls)
av:GetEntity(); av:GetEntity()
check("still zero after repeats", find_calls == 0, "got " .. find_calls)

print("== 2. one resolution per frame ==")
live_entity = make_entity()
av.entity_id = { hash = 1 }
reset(20)
local e1 = av:GetEntity()
check("resolves the entity", e1 ~= nil)
check("exactly one FindEntityByID", find_calls == 1, "got " .. find_calls)
for _ = 1, 20 do av:GetEntity() end
check("20 more calls, still one resolution", find_calls == 1, "got " .. find_calls)
check("cached handle is the same object", av:GetEntity() == e1)

print("== 3. new frame forces a fresh resolution ==")
DAV.frame_seq = 21
av:GetEntity()
check("second frame re-resolves", find_calls == 2, "got " .. find_calls)
DAV.frame_seq = 22
av:GetEntity(); av:GetEntity()
check("third frame re-resolves once", find_calls == 3, "got " .. find_calls)

print("== 4. nil is never cached ==")
live_entity = nil
reset(30)
check("GetEntity returns nil once entity is gone", av:GetEntity() == nil)
check("first lookup counted", find_calls == 1, "got " .. find_calls)
av:GetEntity(); av:GetEntity()
check("nil not cached - every call re-resolves", find_calls == 3, "got " .. find_calls)
live_entity = make_entity()

print("== 5. accessors share one resolution per frame ==")
av.entity_id = { hash = 2 }
av:InvalidateEntityCache()
reset(40)
av:IsPlayerIn()
av:IsDestroyed()
av:IsDespawned()
av:IsEngineOn()
av:GetPosition()
av:GetForward()
av:GetRight()
av:GetUp()
av:GetQuaternion()
av:GetEulerAngles()
check("10 accessors in one frame = 1 FindEntityByID", find_calls == 1, "got " .. find_calls)
av:IsPlayerIn(); av:GetPosition(); av:GetEulerAngles()
check("repeats add nothing", find_calls == 1, "got " .. find_calls)

print("== 5b. basis vectors are cached per frame, not forever ==")
do
    -- GetForward/GetRight/GetUp went through the frame cache too. Two things
    -- have to hold: they must not re-cross into the game inside one frame, and
    -- they must actually refresh when the frame moves -- a basis vector stuck
    -- on the spawn heading would steer the autopilot into a wall.
    av:InvalidateEntityCache()
    reset(60)
    local f1 = av:GetForward()
    local r1 = av:GetRight()
    local u1 = av:GetUp()
    check("forward resolved once", find_calls == 1, "got " .. find_calls)
    for _ = 1, 10 do av:GetForward(); av:GetRight(); av:GetUp() end
    check("30 repeats add no resolution", find_calls == 1, "got " .. find_calls)
    check("same table handed back inside the frame", av:GetForward() == f1)
    check("right is the cached one", av:GetRight() == r1)
    check("up is the cached one", av:GetUp() == u1)

    DAV.frame_seq = 61
    local f2 = av:GetForward()
    check("new frame re-resolves", find_calls == 2, "got " .. find_calls)
    check("value still correct after refresh", f2.x == 1 and f2.y == 0 and f2.z == 0,
        string.format("%s,%s,%s", tostring(f2.x), tostring(f2.y), tostring(f2.z)))

    -- A different entity must not be able to inherit the old basis vectors.
    av:InvalidateEntityCache()
    check("invalidate drops all three", av._forward == nil and av._right == nil and av._up == nil)
    av:GetRight()
    check("and the next read goes back to the game", find_calls == 3, "got " .. find_calls)
end

print("== 5c. no frame counter means no caching ==")
do
    -- Same defensive contract as GetEntity: with nothing to compare against,
    -- every call resolves rather than serving a value of unknown age.
    av:InvalidateEntityCache()
    DAV.frame_seq = nil
    find_calls = 0
    av:GetForward(); av:GetForward(); av:GetForward()
    check("three calls, three resolutions", find_calls == 3, "got " .. find_calls)
    DAV.frame_seq = 70
end

print("== 6. InvalidateEntityCache forces re-resolution ==")
do
    -- Self-contained: the sections above leave the counter wherever they ended,
    -- so pin it here rather than making this depend on their bookkeeping.
    reset(71)
    av:InvalidateEntityCache()
    av:GetEntity()
    check("invalidate forces a lookup", find_calls == 1, "got " .. find_calls)
    av:GetEntity()
    check("then caches again", find_calls == 1, "got " .. find_calls)
end

print("== 7. Despawn drops the handle ==")
av:Despawn()
check("DeleteEntity called", #deleted == 1)
check("entity_id cleared", av.entity_id == nil)
check("cache cleared by Despawn", av._entity == nil and av._entity_frame == -1)
reset(41)
check("GetEntity returns nil after Despawn", av:GetEntity() == nil)
check("no lookup after Despawn (entity_id is nil)", find_calls == 0, "got " .. find_calls)

print("== 8. Spawn invalidates the previous handle ==")
local av3 = new_av()
av3.entity_id = { hash = 3 }
reset(50)
av3:GetEntity()
check("pre-spawn resolution", find_calls == 1, "got " .. find_calls)
check("handle cached", av3._entity ~= nil)
-- A spawn requires no live entity_id (AV:Spawn refuses otherwise), which is
-- exactly the state after Despawn. Start from there.
av3.entity_id = nil
reset(51)
local spawned = av3:Spawn(Vector4.new(0, 0, 50, 1), EulerAngles.new(0, 0, 0))
check("Spawn succeeded", spawned == true)
check("Spawn assigned a new entity_id", av3.entity_id ~= nil)
check("cache dropped by Spawn", av3._entity == nil and av3._entity_frame == -1)
check("Spawn itself did not read the handle", find_calls == 0, "got " .. find_calls)
av3:GetEntity()
check("post-spawn GetEntity re-resolves", find_calls == 1, "got " .. find_calls)

print("== 9. frame_seq absent (defensive) ==")
DAV.frame_seq = nil
av3:InvalidateEntityCache()
reset(0)
find_calls = 0
local okcall = pcall(function() return av3:GetEntity() end)
check("missing DAV.frame_seq does not error", okcall)
check("still resolves", find_calls == 1, "got " .. find_calls)

print("")
print(string.format("entity_cache_test: %d passed, %d failed", pass, fail))
if fail > 0 then error("entity_cache_test failed") end
