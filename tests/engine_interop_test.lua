-- =============================================================================
-- Engine interop regression test
--
-- The control loop used to cross into the red4ext plugin eight times per tick:
-- Engine:Run read velocity and angular velocity, Engine:Update read physics
-- state, velocity and angular velocity again, and two of those four reads
-- threw half of what they paid for away. The fix is two natives --
-- GetFlightState (one read for everything Lua needs) and AddForceTracked
-- (one write that also does the read it needs) -- plus a per-frame snapshot
-- in front of every getter.
--
-- Two things have to be true and both are asserted here:
--
--   1. Cost. Two plugin transitions per tick, no matter how many places ask
--      for the physics state in between.
--   2. Equivalence. The torque the plugin now computes is bit-for-bit the
--      torque Lua used to compute. Moving arithmetic across a language
--      boundary is not permission to change the arithmetic.
--
-- Run:  python tests/run_engine_interop_test.py
-- =============================================================================

local MODDIR = ...

-- ------------------------------------------------------------- counters -----
local CALLS = {}
local function count(key) CALLS[key] = (CALLS[key] or 0) + 1 end
local function reset_calls() CALLS = {} end
local function n(key) return CALLS[key] or 0 end
local function flyav_total()
    local t = 0
    for k, v in pairs(CALLS) do
        if k:sub(1, 6) == "flyav." then t = t + v end
    end
    return t
end

local CLOCK = { t = 500.0 }
os.clock = function() return CLOCK.t end
local function advance(dt) CLOCK.t = CLOCK.t + dt end

-- ----------------------------------------------------------- stub types -----
Vector4 = {}
Vector4.__index = Vector4
function Vector4.new(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w or 1 }, Vector4)
end
function Vector4.Zero() return Vector4.new(0, 0, 0, 1) end
function Vector4.Vector3To4(v) return Vector4.new(v.x, v.y, v.z, 0) end
function Vector4.Length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function Vector4.__index.Length2D(v) return math.sqrt(v.x * v.x + v.y * v.y) end
Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
EulerAngles = { new = function(p, y, r) return { pitch = p, yaw = y, roll = r } end }
Quaternion = { new = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end }
CName = { new = function(s) return { value = s } end }
json = { decode = function() return {} end, encode = function() return "{}" end }
spdlog = { info = function() end }
inkTextRef = { SetText = function() end }

-- ------------------------------------------------------- stub game API ------
-- Deferred through package.preload so a module's top-level code runs only when
-- its dependencies are already globals, matching how the other cost tests load
-- the real modules. LuaJIT's `goto` is rewritten out because the harness runs
-- on Lua 5.1 semantics.
local LUAJIT_EXT = "%f[%w]goto%s+[A-Za-z_][A-Za-z0-9_]*%f[^%w]"
local LUAJIT_LBL = "::%s*[A-Za-z_][A-Za-z0-9_]*%s*::"

local function preload(name)
    local f = assert(io.open(MODDIR .. "/" .. name, "r"), "cannot open " .. name)
    local b = f:read("*a"); f:close()
    b = b:gsub(LUAJIT_EXT, "do end")
    b = b:gsub(LUAJIT_LBL, "do end")
    local chunk, err = (loadstring or load)(b, name)
    if not chunk then error("cannot compile " .. name .. ": " .. tostring(err)) end
    package.preload[name] = chunk
end

preload("Etc/log.lua")
preload("Etc/utils.lua")
preload("Etc/timescale.lua")
TimeScale = require("Etc/timescale.lua")
preload("Etc/def.lua")
preload("Modules/engine.lua")

Log = require("Etc/log.lua")
Def = require("Etc/def.lua")

DAV = {
    frame_seq = 0,
    time_resolution = 0.01,
    model_index = 1,
    is_ready = true,
    user_setting_table = {
        acceleration = 1,
        vertical_acceleration = 1,
        left_right_acceleration = 1,
        roll_change_amount = 1,
        pitch_change_amount = 1,
        pitch_restore_amount = 1,
        roll_restore_amount = 1,
        yaw_change_amount = 1,
        rotate_roll_change_amount = 1,
        max_speed = 100,
        horizontal_air_resistance_const = 0.01,
        vertical_air_resistance_const = 0.01,
        h_lift_idle_acceleration = 0,
        h_acceleration = 1,
        h_ascend_acceleration = 1,
        h_descend_acceleration = 1,
        h_roll_change_amount = 1,
        h_pitch_change_amount = 1,
        h_yaw_change_amount = 1,
        h_roll_restore_amount = 1,
        h_pitch_restore_amount = 1,
        is_enable_idle_gravity = false,
    },
}

-- ------------------------------------------------- the plugin-side stub -----
-- Mirrors the real GetFlightState / AddForceTracked packing and arithmetic so
-- a drift between the two sides shows up here rather than in the game.
--
-- `body` is the simulated physics body. Tests move it directly; the mod can
-- only observe it through the stubs.
local body = {
    velocity = { x = 0, y = 0, z = 0 },
    angular_velocity = { x = 0, y = 0, z = 0 },
    force = { x = 0, y = 0, z = 0 },
    torque = { x = 0, y = 0, z = 0 },
    on_ground = false,
    gravity = false,
    physics_off = false,
    valid = true,
}

local FLAG_ON_GROUND, FLAG_GRAVITY, FLAG_PHYSICS_OFF, FLAG_VALID = 1, 2, 4, 8

local fly_av = {}
function fly_av.SetVehicle(self, h) count("flyav.SetVehicle") end
function fly_av.GetMass(self) count("flyav.GetMass"); return 5000 end
function fly_av.GetPhysicsState(self) count("flyav.GetPhysicsState"); return body.physics_off and 1 or 0 end
function fly_av.UnsetPhysicsState(self) count("flyav.UnsetPhysicsState"); body.physics_off = false end
function fly_av.EnableOriginalPhysics(self, on) count("flyav.EnableOriginalPhysics") end
function fly_av.EnableGravity(self, on) count("flyav.EnableGravity"); body.gravity = on end
function fly_av.HasGravity(self) count("flyav.HasGravity"); return body.gravity end
function fly_av.IsOnGround(self) count("flyav.IsOnGround"); return body.on_ground end
function fly_av.GetVelocity(self)
    count("flyav.GetVelocity")
    return Vector3.new(body.velocity.x, body.velocity.y, body.velocity.z)
end
function fly_av.GetAngularVelocity(self)
    count("flyav.GetAngularVelocity")
    return Vector3.new(body.angular_velocity.x, body.angular_velocity.y, body.angular_velocity.z)
end
function fly_av.AddForce(self, f, t)
    count("flyav.AddForce")
    body.force.x = body.force.x + f.x
    body.force.y = body.force.y + f.y
    body.force.z = body.force.z + f.z
    body.torque.x = body.torque.x + t.x
    body.torque.y = body.torque.y + t.y
    body.torque.z = body.torque.z + t.z
end
function fly_av.ChangeVelocity(self, v, a, k) count("flyav.ChangeVelocity") end

function fly_av.GetFlightState(self)
    count("flyav.GetFlightState")
    local flags = 0
    if body.on_ground then flags = flags + FLAG_ON_GROUND end
    if body.gravity then flags = flags + FLAG_GRAVITY end
    if body.physics_off then flags = flags + FLAG_PHYSICS_OFF end
    if body.valid then flags = flags + FLAG_VALID end
    return Vector4.new(body.velocity.x, body.velocity.y, body.velocity.z, flags)
end

function fly_av.AddForceTracked(self, force, target_angular, gain)
    count("flyav.AddForceTracked")
    if body.physics_off then
        body.physics_off = false
        count("flyav.ForceEnablePhysics")
    end
    body.force.x = body.force.x + force.x
    body.force.y = body.force.y + force.y
    body.force.z = body.force.z + force.z
    local applied = Vector3.new(
        (target_angular.x - body.angular_velocity.x) * gain,
        (target_angular.y - body.angular_velocity.y) * gain,
        (target_angular.z - body.angular_velocity.z) * gain)
    body.torque.x = body.torque.x + applied.x
    body.torque.y = body.torque.y + applied.y
    body.torque.z = body.torque.z + applied.z
    return applied
end

FlyAVSystem = { new = function() return setmetatable({}, { __index = fly_av }) end }

local Engine = require("Modules/engine.lua")
-- ------------------------------------------------------------- asserts ------
local pass, fail = 0, 0
local function ok(cond, label, detail)
    if cond then
        pass = pass + 1
        print("  PASS  " .. label)
    else
        fail = fail + 1
        print("  FAIL  " .. label .. (detail and ("   [" .. tostring(detail) .. "]") or ""))
    end
end
local function eq_int(got, want, label)
    ok(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function near(got, want, label)
    ok(math.abs(got - want) < 1e-4, label,
        string.format("got %.6f, want %.6f", got, want))
end

-- ------------------------------------------------------------- fixture ------
-- A minimal AV-shaped object. Engine only reaches through these fields.
local function make_engine()
    local event_obj = { IsInMenuOrPopupOrPhoto = function(self) return false end,
                       IsInVehicle = function(self) return false end }
    local av_obj = {
        -- Backdated past Engine.ground_check_delay so IsOnGround actually
        -- reports the body's flag instead of the spawn-protection default.
        spawn_time = CLOCK.t - 10,
        is_auto_pilot = false,
        all_models = { { flight_mode = Def.FlightMode.AV } },
        minimum_distance_to_ground = 1.2,
        IsDespawned = function(self) return false end,
        GetEulerAngles = function(self) return EulerAngles.new(0, 0, 0) end,
        GetForward = function(self) return Vector4.new(1, 0, 0, 0) end,
        GetRight = function(self) return Vector4.new(0, 1, 0, 0) end,
        GetUp = function(self) return Vector4.new(0, 0, 1, 0) end,
        navigation_obj = { IsCollision = function(self) return false end,
                          GetHeight = function(self) return 20 end },
        core_obj = { event_obj = event_obj },
    }
    local eng = Engine:New(av_obj)
    eng:Init({ hash = 1234 })
    av_obj.engine_obj = eng
    return eng
end

local function new_frame() DAV.frame_seq = DAV.frame_seq + 1 end

-- =============================================================================
print("== 1. the snapshot is one read per frame, however many ask ==")
-- =============================================================================
local eng = make_engine()
body.velocity = { x = 3, y = -2, z = 1.5 }
body.on_ground = true
body.gravity = true
reset_calls()
new_frame()

local v1 = eng:GetVelocity()
local v2 = eng:GetVelocity()
local ground = eng:IsOnGround()
local grav = eng:HasGravity()
local v3 = eng:GetVelocity()

eq_int(n("flyav.GetFlightState"), 1, "five asks, one GetFlightState")
eq_int(flyav_total(), 1, "and nothing else crossed")
ok(v1 == v2 and v2 == v3, "the same table is served inside a frame")
near(v1.x, 3, "velocity x unpacked")
near(v1.z, 1.5, "velocity z unpacked")
ok(ground == true, "on_ground unpacked")
ok(grav == true, "has_gravity unpacked")

new_frame()
eng:GetVelocity()
eq_int(n("flyav.GetFlightState"), 2, "a new frame reads again")

-- =============================================================================
print("== 2. every flag decodes, and a dead handle reads as parked ==")
-- =============================================================================
new_frame()
body.on_ground = false
body.gravity = false
body.physics_off = false
local s = eng:RefreshSnapshot()
eq_int(s.valid and 1 or 0, 1, "valid flag")
ok(not s.on_ground and not s.has_gravity and not s.physics_off, "clear flags decode as clear")

new_frame()
body.valid = false
body.velocity = { x = 99, y = 99, z = 99 }
local dead = eng:RefreshSnapshot()
ok(dead.valid == false, "invalid handle reported")
near(dead.velocity.x, 0, "invalid handle zeroes the velocity")
ok(dead.on_ground == false and dead.has_gravity == false, "invalid handle clears the flags")
body.valid = true

-- =============================================================================
print("== 3. no frame counter means no caching ==")
-- =============================================================================
DAV.frame_seq = nil
reset_calls()
eng:GetVelocity(); eng:GetVelocity(); eng:GetVelocity()
eq_int(n("flyav.GetFlightState"), 3, "three asks, three reads (never serves stale)")
DAV.frame_seq = 100

-- =============================================================================
print("== 4. AddForce: two transitions a tick, and the old torque exactly ==")
-- =============================================================================
-- The pre-change branch, transcribed. This is the reference the plugin has to
-- match: force = target_linear * mass, torque = (target_angular - actual) * gain.
local function old_add_force(e)
    local direction_velocity = e:GetDirectionVelocity()
    local angular_velocity = e:GetAngularVelocity()
    local actual = fly_av.GetAngularVelocity(nil)   -- the read this all removes
    local diff = Vector3.new(angular_velocity.x - actual.x,
                            angular_velocity.y - actual.y,
                            angular_velocity.z - actual.z)
    local mass = e.mass
    return Vector3.new(direction_velocity.x * mass,
                       direction_velocity.y * mass,
                       direction_velocity.z * mass),
           Vector3.new(diff.x * e.torque_gain, diff.y * e.torque_gain, diff.z * e.torque_gain)
end

local eng2 = make_engine()
eng2:SetControlType(Def.EngineControlType.AddForce)
eng2:SetDirectionVelocity(Vector3.new(2.5, -1.25, 0.75))
eng2:SetAngularVelocity(Vector3.new(4, -3, 6))
body.angular_velocity = { x = 1, y = 1, z = -2 }

local want_force, want_torque = old_add_force(eng2)

reset_calls()
new_frame()
eng2:Update(1 / 60)

eq_int(n("flyav.AddForceTracked"), 1, "one write")
eq_int(n("flyav.GetFlightState"), 1, "one read")
eq_int(flyav_total(), 2, "two transitions for the whole tick")
near(eng2.force.x, want_force.x, "force x matches the old computation")
near(eng2.force.z, want_force.z, "force z matches the old computation")
near(eng2.torque.x, want_torque.x, "torque x matches the old computation")
near(eng2.torque.y, want_torque.y, "torque y matches the old computation")
near(eng2.torque.z, want_torque.z, "torque z matches the old computation")
near(body.torque.x, want_torque.x, "and the body got the same torque")

-- The old path cost 4 here (GetPhysicsState + GetVelocity + GetAngularVelocity
-- + AddForce) before Run added three more.
eq_int(n("flyav.GetVelocity"), 0, "no separate velocity read")
eq_int(n("flyav.GetAngularVelocity"), 0, "no separate angular read")
eq_int(n("flyav.GetPhysicsState"), 0, "no physics-state poll")

-- =============================================================================
print("== 5. a disabled body is re-enabled, and only when it is disabled ==")
-- =============================================================================
new_frame()
body.physics_off = false
eng2:Update(1 / 60)
eq_int(n("flyav.UnsetPhysicsState"), 0, "healthy body: no UnsetPhysicsState")

new_frame()
body.physics_off = true
eng2:Update(1 / 60)
eq_int(n("flyav.UnsetPhysicsState"), 1, "disabled body: Lua re-enables it once")
ok(not body.physics_off, "and it stays enabled")

-- The write self-heals too, so a snapshot that went stale mid-frame cannot
-- leave force going into a body that is not simulating.
body.physics_off = true
DAV.frame_seq = DAV.frame_seq - 1        -- pretend the snapshot is still fresh
reset_calls()
fly_av.AddForceTracked(nil, Vector3.new(1, 1, 1), Vector3.new(0, 0, 0), 100)
eq_int(n("flyav.ForceEnablePhysics"), 1, "the write re-enables even on a stale snapshot")

-- =============================================================================
print("== 6. ChangeVelocity mode: read + write, nothing else ==")
-- =============================================================================
local eng3 = make_engine()
eng3:SetControlType(Def.EngineControlType.ChangeVelocity)
reset_calls()
new_frame()
eng3:Update(1 / 60)
eq_int(n("flyav.ChangeVelocity"), 1, "one ChangeVelocity")
eq_int(n("flyav.GetFlightState"), 1, "one read")
eq_int(flyav_total(), 2, "two transitions")

-- =============================================================================
print("== 7. Blocking does not write ==")
-- =============================================================================
local eng4 = make_engine()
eng4:SetControlType(Def.EngineControlType.Blocking)
reset_calls()
new_frame()
eng4:Update(1 / 60)
eq_int(flyav_total(), 1, "only the snapshot read, no write")

-- =============================================================================
print("== 8. Run/IsOnGround/HasGravity add nothing to the tick ==")
-- =============================================================================
local eng5 = make_engine()
eng5:SetControlType(Def.EngineControlType.AddForce)
reset_calls()
new_frame()
-- The whole control chain for one tick, in the order init.lua drives it.
eng5:Run(1, 2, 3, 0.1, 0.2, 0.3)
eng5:OnlyAngularRun(0.1, 0.2, 0.3)
eng5:GetVelocity()
eng5:IsOnGround()
eng5:HasGravity()
eng5:Update(1 / 60)
eq_int(flyav_total(), 2, "six consumers + the write = two transitions")

-- =============================================================================
print("== 9. Init drops the previous body's snapshot ==")
-- =============================================================================
body.velocity = { x = 7, y = 7, z = 7 }
reset_calls()
new_frame()
eng5:GetVelocity()
eq_int(n("flyav.GetFlightState"), 1, "read in this frame")
eng5:Init({ hash = 9999 })
eq_int(eng5.snap_seq, -1, "Init invalidated the snapshot")
eng5:GetVelocity()
eq_int(n("flyav.GetFlightState"), 2, "the next read goes back to the plugin")

print("")
print(string.format("engine_interop_test: %d passed, %d failed", pass, fail))
if fail > 0 then error("engine_interop_test failed") end
