local Utils = require("Etc/utils.lua")
Engine = {}
Engine.__index = Engine

--- Component-wise equality within a tolerance; used to skip redundant native pushes.
---@param a Vector3
---@param b Vector3
---@param eps number
---@return boolean
local function vec3_equal(a, b, eps)
    return math.abs(a.x - b.x) <= eps and math.abs(a.y - b.y) <= eps and math.abs(a.z - b.z) <= eps
end

-- A held velocity target only needs re-pushing when it actually moved (m/s and rad/s).
local VELOCITY_EPS = 0.01
local ANGULAR_EPS = 0.01

--- Debug-only display values. The native paths apply nothing in Lua, so every "nothing applied"
--- branch points at one shared zero instead of allocating two vectors per frame. Nobody writes
--- components of force/torque (SetForce/SetTorque replace the reference), so sharing is safe.
--- Built in New rather than at module scope: Vector3 is a runtime global of the CET sandbox.

--- Constructor
--- @param av_obj any AV instance
--- @return table
function Engine:New(av_obj)
    ---instance---
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Engine")
    obj.av_obj = av_obj
    obj.all_models = av_obj.all_models
    ---static---
    obj.max_roll = 30
    obj.max_pitch = 30
    obj.force_restore_angle = 70
    -- RPM ramp increments per base tick (0.01 s); multiply by DAV.dt_scale to keep the rate constant.
    obj.rpm_count_step = 4
    obj.rpm_restore_step = 2
    obj.rpm_count_scale = 80
    obj.rpm_max_count = 10 * obj.rpm_count_scale
    obj.torque_gain = 1000
    -- Restore boundary layer (deg, base period): rate tapers to zero at the deadband edge, scaled by dt_scale.
    obj.restore_boundary_deg = 1.0
    obj.ground_check_delay = 3.0
    ---dynamic---
    obj.entity_id = nil
    obj.flight_mode = Def.FlightMode.AV
    obj.fly_av_system = nil
    obj.mass = 5000
    obj.current_speed = 0
    obj.heli_lift_acceleration = DAV.user_setting_table.h_lift_idle_acceleration
    obj.rpm_count = 0
    obj.force = Vector3.new(0, 0, 0)
    obj.torque = Vector3.new(0, 0, 0)
    obj.zero3 = Vector3.new(0, 0, 0)
    obj.direction_velocity = Vector3.new(0, 0, 0)
    obj.angular_velocity = Vector3.new(0, 0, 0)
    obj.acceleration = Vector3.new(0, 0, 0)
    obj.engine_control_type = Def.EngineControlType.None
    obj.is_menu_blocked = false
    obj.loop_timer = nil
    obj.loop_interval = 0.01
    obj.is_finished_init = false

    return setmetatable(obj, self)
end

--- Initialize
---@param entity_id EntityID
function Engine:Init(entity_id)
    self.entity_id = entity_id
    -- The menu gate is edge-driven now (B-6); adopt the state that was already in effect.
    local event_obj = self.av_obj.core_obj and self.av_obj.core_obj.event_obj
    self.is_menu_blocked = (event_obj ~= nil and event_obj:IsInMenuOrPopupOrPhoto()) and true or false
    self.flight_mode = self.all_models[DAV.model_index].flight_mode
    self.fly_av_system = FlyAVSystem.new()
    self.fly_av_system:SetVehicle(entity_id.hash)
    self.mass = self.fly_av_system:GetMass()
    -- Gated on DAV.is_enable_native_flight; pcall because a missing method on an old DLL may throw.
    local ok, fn = pcall(function() return self.fly_av_system.SetFlightControl end)
    self.native_control = DAV.is_enable_native_flight and ok and fn ~= nil
    -- B-3: full native flight model (DLL computes Engine:Run math per physics tick).
    local ok2, fn2 = pcall(function() return self.fly_av_system.SetFlightModel end)
    self.native_flight_model = DAV.is_enable_native_flight and self.native_control and ok2 and fn2 ~= nil
    -- Watchdog source: the DLL counts physics ticks it applies for this vehicle.
    local ok3, fn3 = pcall(function() return self.fly_av_system.GetNativeTickCount end)
    self.native_tick_readable = ok3 and fn3 ~= nil
    -- B-5: native idle hover (mode 4). The DLL runs the unboarded hover regulator on the physics
    -- tick, so Lua stops paying a ground raycast plus six game API calls every Cron tick to hold a
    -- vehicle that is not going anywhere. A DLL without the native keeps the Lua loop.
    local ok4, fn4 = pcall(function() return self.fly_av_system.SetIdleHoverParams end)
    self.native_idle_ok = (DAV.is_enable_native_flight and self.native_control and ok4 and fn4 ~= nil)
        and true or false
    self.native_idle_active = false
    -- Phase C: the DLL keeps the ground reference on its own game-thread update (contact teaches it),
    -- so the hover no longer costs Lua a raycast twice a second.
    local ok5, fn5 = pcall(function() return self.fly_av_system.GetGroundInfo end)
    self.native_ground_ok = (DAV.is_enable_native_flight and self.native_control and ok5 and fn5 ~= nil)
        and true or false
    -- The DLL can run the ground query itself, but the search box and the collision groups are user
    -- settings, so they have to be handed over. Absent native = Lua keeps raycasting as before.
    local ok6, fn6 = pcall(function() return self.fly_av_system.SetGroundQuery end)
    self.native_ground_query_ok = (self.native_ground_ok and ok6 and fn6 ~= nil) and true or false
    self.native_tick_probe_interval = 0.5
    self.native_tick_stall_limit = 3
    self.native_tick_probe = 0
    self.native_tick_stall = 0
    self.native_tick_last = nil
    -- B-4: velocity hold (mode 2) bookkeeping — what the DLL is currently holding for us.
    self.native_hold_pushed = false
    self.native_hold_push_count = 0
    self.native_last_mode = 0
    self.native_hold = { v = Vector3.new(0, 0, 0), a = Vector3.new(0, 0, 0) }
    self.hook_probe_enabled = DAV.is_debug_probe_hook_tick == true
    self.hook_probe_interval = 1.0
    self.hook_probe_budget = 6.0
    self.hook_probe_boarded_budget = 1.0
    self.hook_probe_episode_cap = 40
    self.hook_probe_episodes = 0
    self.hook_probe_type = nil
    self.hook_probe_pending = nil
    self.hook_probe_settle = 0
    self.hook_probe_settle_delay = 0.5
    self.hook_probe_active = false
    self.hook_probe_budget_now = 0
    self.hook_probe_elapsed = 0
    self.hook_probe_next = 0
    self.hook_probe_last = nil
    self.hook_probe_max_hz = 0
    self.log_obj:Record(LogLevel.Info, string.format("native_control=%s native_flight_model=%s mass=%.1f physics_state=%s",
        tostring(self.native_control), tostring(self.native_flight_model), self.mass, tostring(self.fly_av_system:GetPhysicsState())))
    if self.native_flight_model then
        self:PushNativeParams()
    end
    if self.native_control then
        -- The shared native buffer outlives a vehicle: a stale mode 1/2/3 would grab the new body with
        -- the old target, so every fresh engine starts from "native applies nothing".
        self:PushNativeControl(0, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), 0)
        self.native_hold_pushed = false
        self.native_mode3_pushed = false
    end
    self.is_finished_init = true
    -- Re-apply on every spawn: the Engine object outlives the vehicle, so across a respawn the control
    -- type often does not change and SetControlType would not fire.
    self:ApplyControlMode()
end

--- Give up on the native path and hand control back to the Lua flight model.
---@param reason string
function Engine:DisableNative(reason)
    if not self.native_control and not self.native_flight_model then
        return
    end
    self.log_obj:Record(LogLevel.Error, "native flight disabled, falling back to Lua path: " .. reason)
    -- Log:Record only reaches the CET log with PrintDebugMode on; this has to be visible always, because
    -- silently losing the native path is the single most confusing failure mode the mod can have.
    self:ProbeLog("NATIVE FLIGHT DISABLED -> Lua fallback: " .. reason)
    if self.native_control then
        local ok = pcall(function()
            self.fly_av_system:SetFlightControl(0, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), 0)
        end)
        if not ok then
            self.log_obj:Record(LogLevel.Error, "failed to push native stop before fallback")
        end
    end
    self.native_control = false
    self.native_flight_model = false
    self.native_mode3_pushed = false
    self.native_hold_pushed = false
    self.native_last_mode = 0
    -- The Lua flight model needs live feedback again, so put the control mode back on the Lua side.
    self:ApplyControlMode()
end

--- Fall back to the Lua path when the DLL physics-tick counter stops advancing.
---@param delta number
function Engine:WatchNativeTick(delta)
    if not self.native_tick_readable then
        return
    end
    local control_type = self.engine_control_type
    local holds_velocity = control_type == Def.EngineControlType.ChangeVelocity
            or control_type == Def.EngineControlType.FluctuationVelocity
    if control_type ~= Def.EngineControlType.AddForce
            and not (holds_velocity and self.native_hold_pushed) then
        -- Nothing is being driven through the hook; the watchdog has nothing to watch.
        self.native_tick_probe = 0
        self.native_tick_stall = 0
        self.native_tick_last = nil
        return
    end
    if self.mass <= 0 then
        -- Entity not resolved yet: wait for the lazy retry instead of tearing the native path down.
        self.native_tick_probe = 0
        self.native_tick_stall = 0
        self.native_tick_last = nil
        return
    end

    self.native_tick_probe = self.native_tick_probe + delta
    if self.native_tick_probe < self.native_tick_probe_interval then
        return
    end
    self.native_tick_probe = 0

    local ok, ticks = pcall(function() return self.fly_av_system:GetNativeTickCount() end)
    if not ok then
        self.native_tick_readable = false
        return
    end
    if self.native_tick_last == nil or ticks > self.native_tick_last then
        self.native_tick_stall = 0
    else
        self.native_tick_stall = self.native_tick_stall + 1
        if self.native_tick_stall == 1 then
            self.log_obj:Record(LogLevel.Warning, string.format(
                "native physics tick stalled at %.0f (control_type=%s); fallback in %.1fs",
                ticks, tostring(control_type), self.native_tick_probe_interval * self.native_tick_stall_limit))
        end
    end
    self.native_tick_last = ticks

    if self.native_tick_stall >= self.native_tick_stall_limit then
        self:DisableNative(string.format("no physics tick for %.1fs (tick=%.0f)",
            self.native_tick_probe_interval * self.native_tick_stall_limit, ticks))
    end
end

--- Read one native diagnostic counter; nil when the DLL does not expose it.
---@param name string
---@return number|nil
function Engine:ReadNativeCounter(name)
    local ok, value = pcall(function()
        local fn = self.fly_av_system[name]
        if fn == nil then
            return nil
        end
        return fn(self.fly_av_system)
    end)
    if not ok or value == nil then
        return nil
    end
    return tonumber(value)
end

--- Probe output: Log:Record only reaches the log when the ImGui "Print Debug Mode" box is ticked,
--- so the diagnostic also prints unconditionally (scripting.log + CET console).
---@param message string
function Engine:ProbeLog(message)
    self.log_obj:Record(LogLevel.Info, message)
    print("[DAV][probe] " .. message)
end

--- Diagnostic: does the DLL physics hook fire while nobody is aboard the AV?
--- The hook is a per-vehicle member function (this = one WheeledPhysics), so "the game's physics runs"
--- and "the hook fires for our body" are different claims. The DLL counts every hit for our vehicle
--- regardless of who owns the physics, so a counter that stands still outside AddForce proves the game
--- never steps an unmanned vehicle through ApplyAllResistances — which is what keeps that path in Lua.
--- One episode per control-type change: 6s unboarded, 1s boarded (A/B reference in the same log),
--- capped per session so the log stays small.
---@param delta number
function Engine:ProbeHookTickRate(delta)
    if not self.hook_probe_enabled or not self.native_tick_readable then
        return
    end
    local control_type = self.engine_control_type
    local boarded = control_type == Def.EngineControlType.AddForce
    if self.hook_probe_type ~= control_type then
        -- The spawn descent flips ChangeVelocity/FluctuationVelocity several times a second, which
        -- used to re-arm (and log) an episode per flip. Require the value to hold steady first.
        if self.hook_probe_pending ~= control_type then
            self.hook_probe_pending = control_type
            self.hook_probe_settle = 0
        end
        self.hook_probe_settle = self.hook_probe_settle + delta
        if self.hook_probe_settle < self.hook_probe_settle_delay then
            self.hook_probe_active = false
            return
        end
        self.hook_probe_type = control_type
        self.hook_probe_active = (self.hook_probe_episodes < self.hook_probe_episode_cap)
        if not self.hook_probe_active then
            return
        end
        self.hook_probe_episodes = self.hook_probe_episodes + 1
        self.hook_probe_budget_now = (boarded and self.hook_probe_boarded_budget or self.hook_probe_budget)
        self.hook_probe_elapsed = 0
        self.hook_probe_next = self.hook_probe_interval
        self.hook_probe_max_hz = 0
        self.hook_probe_last = self:ReadNativeCounter("GetNativeTickCount")
        self.hook_probe_push_last = self.native_hold_push_count or 0
        self.hook_probe_target_pushes_last = self.target_push_count or 0
        self:ProbeLog(string.format(
            "hook probe armed (%s control_type=%s tick=%.0f mass=%.1f physics_state=%s)",
            boarded and "boarded" or "unboarded", tostring(control_type), self.hook_probe_last or -1,
            self:ReadNativeCounter("GetMass") or -1, tostring(self:GetPhysicsState())))
    else
        self.hook_probe_pending = control_type
        self.hook_probe_settle = 0
    end
    if not self.hook_probe_active or self.hook_probe_last == nil then
        return
    end
    self.hook_probe_elapsed = self.hook_probe_elapsed + delta
    if self.hook_probe_elapsed < self.hook_probe_next then
        return
    end
    self.hook_probe_next = self.hook_probe_next + self.hook_probe_interval
    local ticks = self:ReadNativeCounter("GetNativeTickCount")
    if ticks == nil then
        self.hook_probe_enabled = false
        return
    end
    local hz = (ticks - self.hook_probe_last) / self.hook_probe_interval
    self.hook_probe_last = ticks
    if hz > self.hook_probe_max_hz then
        self.hook_probe_max_hz = hz
    end
    -- mass is a second proof of a live hook: GetMass falls back to the value the hook body publishes.
    -- hold_pushes is the B-4 saving; target_pushes is the B-7 one (pushes driven by state changes,
    -- not by frames) and loop says whether the ramp timer is running.
    local pushes = self.native_hold_push_count or 0
    local dpush = pushes - (self.hook_probe_push_last or 0)
    self.hook_probe_push_last = pushes
    local tp = (self.target_push_count or 0) - (self.hook_probe_target_pushes_last or 0)
    self.hook_probe_target_pushes_last = self.target_push_count or 0
    local gz, az, og, gvalid = self:ReadGroundInfo()
    self:ProbeLog(string.format(
        "hook tick (%s control_type=%s): total=%.0f effective=%.1fHz hold_pushes=%d/s target_pushes=%d/s loop=%s native=%s fm=%s mode=%s auto=%s mass=%.1f physics_state=%s ground_z=%.1f av_z=%.1f h=%.1f on_ground=%s valid=%s",
        boarded and "boarded" or "unboarded", tostring(control_type), ticks, hz, dpush, tp,
        tostring(self.loop_timer ~= nil), tostring(self.native_control), tostring(self.native_flight_model),
        tostring(self.native_last_mode), tostring(self.av_obj.is_auto_pilot),
        self:ReadNativeCounter("GetMass") or -1, tostring(self:GetPhysicsState()),
        gz, az, az - gz, tostring(og), tostring(gvalid)))
    if self.hook_probe_elapsed < self.hook_probe_budget_now then
        return
    end
    self.hook_probe_active = false
    if boarded then
        return
    end
    if self.hook_probe_max_hz <= 0.5 then
        self:ProbeLog("unboarded hook verdict: hook does NOT fire unboarded -> the Lua path must keep writing physics")
    else
        self:ProbeLog(string.format(
            "unboarded hook verdict: hook DOES fire unboarded (%.1fHz) -> mode 2 can move into the DLL",
            self.hook_probe_max_hz))
    end
end

--- Push every flight model tunable to the DLL (packed into Vector4s; order must match Main.cpp).
function Engine:PushNativeParams()
    local s = DAV.user_setting_table
    self.fly_av_system:SetFlightParams(
        Vector4.new(s.max_speed, s.horizontal_air_resistance_const, s.vertical_air_resistance_const, s.acceleration),
        Vector4.new(s.vertical_acceleration, s.left_right_acceleration, s.roll_change_amount, s.roll_restore_amount),
        Vector4.new(s.pitch_change_amount, s.pitch_restore_amount, s.yaw_change_amount, s.rotate_roll_change_amount))
    self.fly_av_system:SetFlightParams2(
        Vector4.new(s.h_roll_change_amount, s.h_roll_restore_amount, s.h_pitch_change_amount, s.h_pitch_restore_amount),
        Vector4.new(s.h_yaw_change_amount, s.h_acceleration, s.h_lift_idle_acceleration, s.h_ascend_acceleration),
        Vector4.new(s.h_descend_acceleration, self.rpm_count_step, self.rpm_restore_step, self.rpm_count_scale))
    self.fly_av_system:SetFlightParams3(
        Vector4.new(self.max_roll, self.max_pitch, self.force_restore_angle, self.restore_boundary_deg))
end

--- B-5: push the idle hover reference and gains (order must match Main.cpp IdleParams).
--- ground_z is the one input the DLL cannot see from inside the physics hook, and it is the only
--- thing Lua still has to raycast for; everything else is a constant or a user setting.
function Engine:PushIdleHoverParams()
    local s = DAV.user_setting_table
    local pos = self.av_obj:GetPosition()
    local height = self.av_obj.navigation_obj:GetHeight()
    local ground_z = (pos ~= nil and pos.z or 0) - height
    -- CalculateIdleMode skips its altitude term while the vehicle is touching something, and that is
    -- what lets a landed AV rest on the ground instead of being pushed up to hover height.
    local idle_gravity = (s.is_enable_idle_gravity and not self.av_obj.navigation_obj:IsCollision()) and 1 or 0
    local heli = self.flight_mode == Def.FlightMode.Helicopter
    local pitch_band = heli and s.h_pitch_restore_amount or s.pitch_restore_amount
    local roll_band = heli and s.h_roll_restore_amount or s.roll_restore_amount
    self.fly_av_system:SetIdleHoverParams(
        -- damping / height_gain are hardcoded in Engine:CalculateIdleMode; mirrored, not retuned.
        Vector4.new(ground_z, self.av_obj.minimum_distance_to_ground, 0.2, 0.5),
        Vector4.new(pitch_band, roll_band, self.restore_boundary_deg, DAV.dt_scale or 1),
        Vector4.new(self.max_roll, self.max_pitch, self.force_restore_angle, s.horizontal_air_resistance_const),
        Vector4.new(s.vertical_air_resistance_const, idle_gravity, 12, 1))
end

--- B-5: hand the unboarded hover to the DLL (mode 4). Returns whether the DLL really holds it, so
--- the caller knows whether it still has to push a mode 2 target of its own.
function Engine:SetNativeIdle(on)
    local effective = (on == true and self.native_idle_ok and DAV.is_enable_native_idle
        and self.is_finished_init and not self.is_menu_blocked
        and self.av_obj ~= nil and self.av_obj.entity_id ~= nil)
        and true or false
    if effective == self.native_idle_active then
        return effective
    end
    self.native_idle_active = effective
    if effective then
        self:PushIdleHoverParams()
        -- Seed once; after that the DLL learns the ground from contact on its own.
        self:SeedGroundReference()
        self.native_hold_pushed = false
        self:PushNativeControl(4, self.zero3, self.zero3, self.torque_gain)
        self.log_obj:Record(LogLevel.Info, "mode4 push (native idle hover active)")
    end
    return effective
end

--- Phase C: read the ground reference the DLL publishes from its game-thread update.
---@return number ground_z, number av_z, boolean on_ground, boolean valid
function Engine:ReadGroundInfo()
    if not self.native_ground_ok then
        return 0, 0, false, false
    end
    local ok, info = pcall(function() return self.fly_av_system:GetGroundInfo() end)
    if not ok or info == nil then
        self.native_ground_ok = false
        return 0, 0, false, false
    end
    return info.x, info.y, (info.z > 0.5), (info.w > 0.5)
end

--- Phase C: height above the DLL's ground reference, or nil when it has nothing to offer yet.
--- Only safe where the vehicle is on or near the surface it last touched: the reference is learned
--- from contact, so a descent onto fresh terrain would be judged against the old ground.
---@return number|nil
function Engine:GetNativeHeight()
    if not self.native_ground_ok then
        return nil
    end
    local ground_z, av_z, _, valid = self:ReadGroundInfo()
    if not valid then
        return nil
    end
    return av_z - ground_z
end

--- Phase C: hand the DLL what its own ground query needs - the search box and the collision groups.
function Engine:PushGroundQuery(offset, distance, mask1, mask2)
    if not self.native_ground_query_ok then
        return false
    end
    local ok = pcall(function()
        self.fly_av_system:SetGroundQuery(offset, distance, mask1 or 0, mask2 or 0)
    end)
    if not ok then
        self.native_ground_query_ok = false
    end
    return ok and true or false
end

--- Phase C: hand the DLL a ground reference once, before the first contact teaches it itself.
function Engine:SeedGroundReference()
    if not self.native_ground_ok or self.av_obj == nil or self.av_obj.entity_id == nil then
        return false
    end
    local pos = self.av_obj:GetPosition()
    if pos == nil then
        return false
    end
    self.fly_av_system:SetGroundReference(pos.z - self.av_obj.navigation_obj:GetHeight())
    return true
end

--- B-3: push the manual-flight command list; the DLL physics hook runs the flight model per tick.
---@param action_command_lists table list of {action, value}
function Engine:PushNativeCommands(action_command_lists)
    -- Commands now arrive as event edges through Core:PushNative, so the per-tick list is no longer
    -- sent. A DLL without that native keeps the legacy path, otherwise flight would silently die.
    if self.native_cmd_ok == nil then
        local ok, fn = pcall(function()
            return self.fly_av_system ~= nil and self.fly_av_system.SetNativeCommand ~= nil
        end)
        self.native_cmd_ok = (ok and fn == true) and true or false
    end
    local n = 0
    local a = {0, 0, 0, 0, 0, 0}
    local v = {1, 1, 1, 1, 1, 1}
    if self.native_cmd_ok ~= true then
        n = #action_command_lists
        if n > 6 then n = 6 end
        for i = 1, n do
            local c = action_command_lists[i]
            a[i] = c[1]
            v[i] = c[2] or 1
        end
    end
    local reset = self.native_reset_pending and 1 or 0
    self.native_reset_pending = false
    -- The DLL derives attitude and axes from the entity quaternion itself (see the axis assignment in
    -- FmStep), so neither is pushed any more. W = 0 means "use your own extraction".
    local att = Vector4.new(0, 0, 0, 0)
    -- Entity world quaternion (real w in W); the DLL validates it by norm.
    local q = self.av_obj:GetQuaternion()
    local cq = Vector4.new(0, 0, 0, 0)
    if q ~= nil then
        cq = Vector4.new(q.i, q.j, q.k, q.r)
    end
    local fwd, right, up = Vector4.new(0, 0, 0, 0), Vector4.new(0, 0, 0, 0), Vector4.new(0, 0, 0, 0)
    local ax_ok = 0
    self.fly_av_system:SetFlightModel(
        Vector4.new(self.flight_mode, self:HasGravity() and 1 or 0, DAV.dt_scale or 1, n),
        Vector4.new(reset, a[1], a[2], a[3]),
        Vector4.new(a[4], a[5], a[6], v[1]),
        Vector4.new(v[2], v[3], v[4], v[5]),
        Vector4.new(v[6], 0, 0, 0),
        att,
        cq,
        Vector4.new(fwd.x, fwd.y, fwd.z, ax_ok),
        Vector4.new(right.x, right.y, right.z, 0),
        Vector4.new(up.x, up.y, up.z, 0))
end

--- Get Control Type
---@return Def.EngineControlType
function Engine:GetControlType()
    return self.engine_control_type
end

--- Set control type
---@param engine_control_type Def.EngineControlType
function Engine:SetControlType(engine_control_type)
    if self.engine_control_type == engine_control_type then
        return
    end
    self.engine_control_type = engine_control_type
    self:ApplyControlMode()
end

--- Push flight control to the DLL reusing scratch Vector3 tables (no per-push allocation).
---@param mode integer 0=off, 1=add force/torque, 2=write velocity
---@param vel Vector3
---@param angvel Vector3
---@param gain number
function Engine:PushNativeControl(mode, vel, angvel, gain)
    self.native_scratch = self.native_scratch or { Vector3.new(0, 0, 0), Vector3.new(0, 0, 0) }
    local v, a = self.native_scratch[1], self.native_scratch[2]
    v.x, v.y, v.z = vel.x, vel.y, vel.z
    a.x, a.y, a.z = angvel.x, angvel.y, angvel.z
    self.native_last_mode = mode
    self.fly_av_system:SetFlightControl(mode, v, a, gain)
end

--- Apply the native mode implied by the current state.
--- B-7: this replaces the per-frame `Engine:Update`. Every mode decision happens when the state
--- changes (control type, menu, spawn/despawn), never from a frame loop.
function Engine:ApplyControlMode()
    if not self.is_finished_init then
        return
    end
    if self.av_obj == nil or self.av_obj.entity_id == nil or self.is_menu_blocked then
        -- No body to drive, or the menu owns the screen: never leave a held target in the buffer.
        self:StopLoop()
        self:PushNativeOff()
        return
    end
    local control_type = self.engine_control_type
    -- Every mode decision below re-derives who owns the hover. The flag must not survive into a
    -- control type that does not run it (AddForce after boarding, FluctuationVelocity ramps), or
    -- AV:Operate would keep skipping the Lua math and the player's input would go nowhere.
    self.native_idle_active = false
    if control_type == Def.EngineControlType.AddForce and self.native_flight_model
            and not self.av_obj.is_auto_pilot then
        -- B-3: the DLL physics hook runs the whole flight model from the pushed commands.
        self:StopLoop()
        self.force = self.zero3
        self.torque = self.zero3
        if not self.native_mode3_pushed then
            self.log_obj:Record(LogLevel.Info, "mode3 push (native flight model active)")
            self:PushNativeControl(3, self.zero3, self.zero3, self.torque_gain)
            self.native_mode3_pushed = true
        end
        return
    end
    if self.native_mode3_pushed then
        -- Otherwise the hook keeps flying the AV after the player leaves it.
        self:PushNativeOff()
    end
    if control_type == Def.EngineControlType.ChangeVelocity then
        self.native_hold_pushed = false
        -- With the hook installed it re-applies the target every physics tick; without it the Lua
        -- side is the only thing that can keep the vehicle there.
        if self.native_control then
            self:StopLoop()
        else
            self:StartLoop()
        end
        -- ChangeVelocity with no autopilot means the unboarded hover: give it to the DLL. The
        -- autopilot also drives mode 2 and must keep its own targets, so it is excluded here.
        if self:SetNativeIdle(not self.av_obj.is_auto_pilot) then
            return
        end
        self:PushFlightTarget()
    elseif control_type == Def.EngineControlType.FluctuationVelocity then
        -- The ramp integrates over time, so it is the one thing that always needs a clock.
        self:StartLoop()
    elseif control_type == Def.EngineControlType.AddForce then
        self.native_hold_pushed = false
        if self.native_control then
            self:StopLoop()
        else
            -- The Lua flight model is a closed loop: it needs live feedback every tick, not just on
            -- a target change.
            self:StartLoop()
        end
        self:PushFlightTarget()
    else
        -- None (nothing has asked for control yet) and Blocking both mean "the DLL applies nothing".
        self:StopLoop()
        self:PushNativeOff()
        if control_type ~= Def.EngineControlType.None and control_type ~= Def.EngineControlType.Blocking then
            self.log_obj:Record(LogLevel.Error, "Unknown control type",
                "Engine:ApplyControlMode - control_type: " .. tostring(control_type))
        end
    end
end

--- Push the current flight target for the current control type. This is the only place a flight
--- target reaches the DLL, and it runs from the setters — never from a frame loop.
function Engine:PushFlightTarget()
    if not self.is_finished_init or self.is_menu_blocked then
        return
    end
    if self.av_obj == nil or self.av_obj.entity_id == nil then
        return
    end
    local control_type = self.engine_control_type
    if control_type == Def.EngineControlType.ChangeVelocity
            or control_type == Def.EngineControlType.FluctuationVelocity then
        self.target_push_count = (self.target_push_count or 0) + 1
        self:PushVelocityHold()
    elseif control_type == Def.EngineControlType.AddForce then
        if self.native_flight_model and not self.av_obj.is_auto_pilot then
            -- The DLL derives force and torque from the pushed commands and the live body.
            return
        end
        if self.native_control then
            self:PushForceTarget()
        else
            self:ApplyLuaFlightModel()
        end
    end
end

--- Hold the vehicle at the current velocity target (ChangeVelocity semantics).
--- The physics hook re-applies mode 2 every physics tick, so a target that has not moved needs no
--- push at all. Falls back to the direct write on a DLL without SetFlightControl.
---@return boolean pushed
function Engine:PushVelocityHold()
    if not self.native_control then
        self:ChangeVelocity(Def.ChangeVelocityType.Both, self.direction_velocity, self.angular_velocity)
        return true
    end
    local vel = self.direction_velocity
    local ang = self.angular_velocity
    local held = self.native_hold
    -- native_last_mode matters: another mode (1/3) may have been pushed since, and the DLL holds
    -- whatever mode it was last told, so "target unchanged" alone is not enough to skip the push.
    if self.native_hold_pushed and self.native_last_mode == 2
            and vec3_equal(held.v, vel, VELOCITY_EPS)
            and vec3_equal(held.a, ang, ANGULAR_EPS) then
        return false
    end
    self:PushNativeControl(2, vel, ang, 0)
    self.native_hold_push_count = (self.native_hold_push_count or 0) + 1
    held.v.x, held.v.y, held.v.z = vel.x, vel.y, vel.z
    held.a.x, held.a.y, held.a.z = ang.x, ang.y, ang.z
    self.native_hold_pushed = true
    return true
end

--- AddForce semantics without the native flight model: hand the DLL the velocity target and let it
--- compute the torque error from the live angular velocity every physics tick.
function Engine:PushForceTarget()
    local vel = self.direction_velocity
    local ang = self.angular_velocity
    local held = self.native_hold
    if self.native_last_mode == 1 and vec3_equal(held.v, vel, VELOCITY_EPS)
            and vec3_equal(held.a, ang, ANGULAR_EPS) then
        return
    end
    self:PushNativeControl(1, vel, ang, self.torque_gain)
    held.v.x, held.v.y, held.v.z = vel.x, vel.y, vel.z
    held.a.x, held.a.y, held.a.z = ang.x, ang.y, ang.z
    self.native_hold_pushed = true
end

--- The pre-native flight model, kept for a DLL without SetFlightControl and for the watchdog
--- fallback. It needs live feedback, so the control loop drives it through Engine:Run.
function Engine:ApplyLuaFlightModel()
    local target = self.direction_velocity
    local ang = self.angular_velocity
    local mass = self.mass
    local _, actual = self:GetDirectionAndAngularVelocity()
    self.force = Vector3.new(target.x * mass, target.y * mass, target.z * mass)
    self.torque = Vector3.new(
        (ang.x - actual.x) * self.torque_gain,
        (ang.y - actual.y) * self.torque_gain,
        (ang.z - actual.z) * self.torque_gain)
    self:AddForce(self.force, self.torque)
end

--- The one clock the Engine still owns: the descent/ascent ramp integrates over time.
function Engine:StartLoop()
    if self.loop_timer ~= nil then
        return
    end
    local engine = self
    self.loop_timer = Cron.Every(self.loop_interval, function(args)
        -- Cron only ever fires a timer once per frame, so the nominal interval would under-count the
        -- ramp whenever the frame rate is below 1/interval. Use the real frame delta instead.
        engine:LoopTick(DAV.last_frame_delta or args.interval)
    end)
end

function Engine:StopLoop()
    if self.loop_timer ~= nil then
        Cron.Halt(self.loop_timer)
        self.loop_timer = nil
    end
end

---@param delta number the timer interval, so the ramp rate is per second whatever the frame rate is
function Engine:LoopTick(delta)
    if self.av_obj == nil or self.av_obj.entity_id == nil or self.is_menu_blocked then
        self:StopLoop()
        return
    end
    local control_type = self.engine_control_type
    if control_type == Def.EngineControlType.FluctuationVelocity then
        self:FluctuationVelocity(delta)
        return
    end
    if not self.native_control then
        -- No DLL hook to re-apply anything, so the Lua path has to keep writing the target.
        self:PushFlightTarget()
        return
    end
    self:StopLoop()
end

--- Autopilot is a mode condition, not just a flag: mode 3 is manual-only, so the DLL mode has to be
--- re-evaluated the moment it flips. Navigation used to set av_obj.is_auto_pilot directly and rely on
--- the per-frame Update to notice.
---@param on boolean
function Engine:SetAutoPilot(on)
    if self.av_obj == nil or self.av_obj.is_auto_pilot == on then
        return
    end
    self.av_obj.is_auto_pilot = on
    self:ApplyControlMode()
end

--- Slow safety net, driven by Core: the physics body can resolve late and the hook can stop.
---@param delta number
function Engine:Heartbeat(delta)
    if not self.is_finished_init or self.av_obj == nil or self.av_obj.entity_id == nil then
        return
    end
    if self.is_menu_blocked then
        -- Physics is frozen while the menu owns the screen, so the hook legitimately stops ticking.
        -- The old per-frame Update returned here too; without this the watchdog tears the native path
        -- down 1.5s after any menu, popup, or photo mode opens.
        self.native_tick_probe = 0
        self.native_tick_stall = 0
        self.native_tick_last = nil
        return
    end
    -- While unresolved GetMass() is 0 and every physics call is a silent no-op.
    if self.native_control and self.mass <= 0 then
        local mass = self.fly_av_system:GetMass()
        if mass > 0 then
            self.mass = mass
            self.log_obj:Record(LogLevel.Info, string.format("native mass resolved: %.1f", mass))
        end
    end
    -- -1 means "vehicle not resolved yet"; ForceEnablePhysics is what gets a fresh AV simulated.
    -- This has to stay on the game thread: the physics hook only fires while the body is simulated,
    -- and calling ForceEnablePhysics from inside that body's own update reenters the physics engine.
    if (not self.native_control or self.native_tick_last == nil) and self:GetPhysicsState() ~= 0 then
        self:UnsetPhysicsState()
        self.log_obj:Record(LogLevel.Trace, "Unset DAV physics")
    end
    if self.native_idle_active and not self.native_ground_ok then
        -- The ground under the AV is the one thing the DLL could not see. With Phase C it can: contact
        -- teaches it on the game thread, so this fallback only runs on a DLL without GetGroundInfo.
        self:PushIdleHoverParams()
    end
    if self.native_control then
        self:WatchNativeTick(delta)
    end
    self:ProbeHookTickRate(delta)
end

--- Unset physics state
function Engine:UnsetPhysicsState()
    if not self.is_finished_init then
        return
    end
    self.fly_av_system:UnsetPhysicsState()
end

--- Get Physics state
---@return number
function Engine:GetPhysicsState()
    if not self.is_finished_init then
        return 0
    end
    return self.fly_av_system:GetPhysicsState()
end

--- Enable original physics
---@param on boolean
function Engine:EnableOriginalPhysics(on)
    if not self.is_finished_init then
        return
    end
    self.fly_av_system:EnableOriginalPhysics(on)
end

--- Check if has gravity
---@return boolean
function Engine:HasGravity()
    if not self.is_finished_init then
        return false
    end
    return self.fly_av_system:HasGravity()
end

--- Set gravity
---@param on boolean
function Engine:EnableGravity(on)
    if not self.is_finished_init then
        return
    end
    self.fly_av_system:EnableGravity(on)
end

--- If Collision Detected
---@return boolean
function Engine:IsOnGround()
    if not self.is_finished_init then
        return false
    end
    -- Ignore ground checks briefly after spawn: physics init causes false detections
    local elapsed_time = os.clock() - self.av_obj.spawn_time
    if elapsed_time < self.ground_check_delay then
        return false
    end
    return self.fly_av_system:IsOnGround()
end

--- Get Direction and Angular Velocity
---@return Vector3
---@return Vector3
function Engine:GetDirectionAndAngularVelocity()
    if not self.is_finished_init then
        return Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)
    end
    return self.fly_av_system:GetVelocity(), self.fly_av_system:GetAngularVelocity()
end

--- Get the linear velocity only (skips the angular C# transition of GetDirectionAndAngularVelocity).
---@return Vector3|nil nil when the physics handle is not up yet
function Engine:GetVelocity()
    if not self.is_finished_init then
        return nil
    end
    return self.fly_av_system:GetVelocity()
end

--- Add force
---@param force Vector3
---@param torque Vector3
function Engine:AddForce(force, torque)
    self.fly_av_system:AddForce(force, torque)
end

--- Add velocity
---@param delta number
---@param direction_velocity Vector3
---@param angular_velocity Vector3
function Engine:AddVelocity(delta, direction_velocity, angular_velocity)
    local delta_direction_velocity = Vector3.new(direction_velocity.x * delta, direction_velocity.y * delta, direction_velocity.z * delta)
    local delta_angular_velocity = Vector3.new(angular_velocity.x * delta, angular_velocity.y * delta, angular_velocity.z * delta)
    self.fly_av_system:AddVelocity(delta_direction_velocity, delta_angular_velocity)
end

--- Stop whatever the hook was applying, once. Shared by every path that leaves a native mode.
function Engine:PushNativeOff()
    if not self.native_control then
        return
    end
    if not (self.native_mode3_pushed or self.native_hold_pushed) then
        return
    end
    self:PushNativeControl(0, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), 0)
    self.native_mode3_pushed = false
    self.native_hold_pushed = false
end

--- B-6: the menu/popup/photo gate used to be polled every frame. The UI observers now report the
--- edge, so the Engine only keeps a flag and stops/resumes native application when it flips.
---@param blocked boolean
function Engine:SetMenuBlocked(blocked)
    blocked = blocked and true or false
    if self.is_menu_blocked == blocked then
        return
    end
    self.is_menu_blocked = blocked
    -- ApplyControlMode pushes mode 0 while blocked and re-asserts the target when the menu clears.
    self:ApplyControlMode()
end

--- Change velocity
---@param type integer
---@param direction_velocity Vector3
---@param angular_velocity Vector3
function Engine:ChangeVelocity(type, direction_velocity, angular_velocity)
    self.fly_av_system:ChangeVelocity(direction_velocity, angular_velocity, type)
end

--- Set force
---@param force Vector3
function Engine:SetForce(force)
    self.force = force
end

--- Set torque
---@param torque Vector3
function Engine:SetTorque(torque)
    self.torque = torque
end

--- Get direction velocity
---@return Vector3
function Engine:GetDirectionVelocity()
    return self.direction_velocity
end

--- Set direction velocity
---@param direction_velocity Vector3
function Engine:SetDirectionVelocity(direction_velocity)
    -- No change gate here on purpose: the deadband belongs in PushVelocityHold, which compares against
    -- what the DLL actually holds. Comparing against the previous Lua target instead would silently
    -- discard slow drift (each step under eps, the sum over eps) and the vehicle would never see it.
    self.direction_velocity = direction_velocity
    self:PushFlightTarget()
end

--- Get angular velocity
---@return Vector3
function Engine:GetAngularVelocity()
    return self.angular_velocity
end

--- Set angular velocity
---@param angular_velocity Vector3
function Engine:SetAngularVelocity(angular_velocity)
    self.angular_velocity = angular_velocity
    self:PushFlightTarget()
end

--- Calculate linearly velocity.
---@param action_command_list table
---@param skip_linear boolean|nil Idle only: skip the hover/height term for callers that discard x/y/z.
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateAddVelocity(action_command_list, skip_linear)
    -- `or 1` keeps pre-timescale behaviour if DAV.dt_scale was never published.
    local dt_scale = DAV.dt_scale or 1
    if action_command_list[1] == Def.ActionList.Idle then
        self.rpm_count = 0
        return self:CalculateIdleMode(skip_linear)
    end

    if (action_command_list[1] == Def.ActionList.Forward or action_command_list[1] == Def.ActionList.Up or action_command_list[1] == Def.ActionList.HAccelerate or action_command_list[1] == Def.ActionList.HUp) and self.rpm_count <= self.rpm_max_count then
        self.rpm_count = self.rpm_count + self.rpm_count_step * dt_scale
    elseif (action_command_list[1] == Def.ActionList.Backward or action_command_list[1] == Def.ActionList.Down or action_command_list[1] == Def.ActionList.HDown) and self.rpm_count >= -self.rpm_max_count then
        self.rpm_count = self.rpm_count - self.rpm_count_step * dt_scale
    end
    if self.rpm_count > 0 then
        self.rpm_count = self.rpm_count - self.rpm_restore_step * dt_scale
    elseif self.rpm_count < 0 then
        self.rpm_count = self.rpm_count + self.rpm_restore_step * dt_scale
    end

    if self.flight_mode == Def.FlightMode.AV then
        return self:CalculateAVMode(action_command_list)
    elseif self.flight_mode == Def.FlightMode.Helicopter then
        return self:CalculateHelicopterMode(action_command_list)
    else
        self.log_obj:Record(LogLevel.Critical, "Unknown flight mode: " .. self.flight_mode)
        return 0,0,0,0,0,0
    end
end

--- Restore rate with a boundary layer, replacing a bare relay.
--- See `restore_boundary_deg` in the constructor for why.
---@param excess number how far past the deadband edge the angle is, in degrees (>= 0)
---@param full_rate number the untapered restore rate for this axis
---@return number the rate to command, tapered to zero as excess -> 0
function Engine:RestoreRate(excess, full_rate)
    local boundary = self.restore_boundary_deg * (DAV.dt_scale or 1)
    if boundary <= 0 or excess >= boundary then
        return full_rate
    end
    if excess <= 0 then
        return 0
    end
    return full_rate * (excess / boundary)
end

--- Run the engine with specified parameters.
---@param x number
---@param y number
---@param z number
---@param roll number
---@param pitch number
---@param yaw number
---@return boolean success True if engine ran successfully, false otherwise
function Engine:Run(x, y, z, roll, pitch, yaw)
    -- Validation checks
    if not self.is_finished_init then
        self.log_obj:Record(LogLevel.Warning, "Engine not initialized", "Engine:Run")
        return false
    end

    if not self.entity_id then
        self.log_obj:Record(LogLevel.Error, "Entity ID is nil", "Engine:Run")
        return false
    end

    if self.av_obj:IsDespawned() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle not spawned", "Engine:Run")
        return false
    end

    local vel_vec, _ = self:GetDirectionAndAngularVelocity()
    if not vel_vec then
        self.log_obj:Record(LogLevel.Error, "Failed to get velocity", "Engine:Run")
        return false
    end

    local current_angle = self.av_obj:GetEulerAngles()
    if not current_angle then
        self.log_obj:Record(LogLevel.Error, "Failed to get angles", "Engine:Run")
        return false
    end
    local roll_restore_amount
    local pitch_restore_amount

    if self.flight_mode == Def.FlightMode.AV then
        roll_restore_amount = DAV.user_setting_table.roll_restore_amount
        pitch_restore_amount = DAV.user_setting_table.pitch_restore_amount
    elseif self.flight_mode == Def.FlightMode.Helicopter then
        roll_restore_amount = DAV.user_setting_table.h_roll_restore_amount
        pitch_restore_amount = DAV.user_setting_table.h_pitch_restore_amount
    end
    local local_roll = 0
    local local_pitch = 0

    if self.flight_mode == Def.FlightMode.Helicopter or self:HasGravity() then
        if current_angle.pitch > pitch_restore_amount then
            local_pitch = local_pitch - self:RestoreRate(
                current_angle.pitch - pitch_restore_amount, pitch_restore_amount)
        elseif current_angle.pitch < -pitch_restore_amount then
            local_pitch = local_pitch + self:RestoreRate(
                -current_angle.pitch - pitch_restore_amount, pitch_restore_amount)
        end
    end

    if current_angle.roll > roll_restore_amount then
        local_roll = local_roll - self:RestoreRate(
            current_angle.roll - roll_restore_amount, roll_restore_amount)
    elseif current_angle.roll < -roll_restore_amount then
        local_roll = local_roll + self:RestoreRate(
            -current_angle.roll - roll_restore_amount, roll_restore_amount)
    end

    -- Smooth roll correction when exceeding max_roll
    if current_angle.roll > self.max_roll then
        local excess_roll = current_angle.roll - self.max_roll
        local_roll = local_roll - excess_roll * 0.5 -- Apply gradual correction
    elseif current_angle.roll < -self.max_roll then
        local excess_roll = -self.max_roll - current_angle.roll
        local_roll = local_roll + excess_roll * 0.5 -- Apply gradual correction
    end

    if current_angle.roll > self.force_restore_angle or current_angle.roll < -self.force_restore_angle then
        local_roll = - current_angle.roll
    elseif current_angle.pitch > self.force_restore_angle or current_angle.pitch < -self.force_restore_angle then
        local_pitch = - current_angle.pitch
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll + d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    if self.flight_mode == Def.FlightMode.Helicopter then
        local up_vec = self.av_obj:GetUp()
        if self.heli_lift_acceleration < 0 then
            self.heli_lift_acceleration = 0
        end
        x = x + self.heli_lift_acceleration * up_vec.x
        y = y + self.heli_lift_acceleration * up_vec.y

        self.heli_lift_acceleration = DAV.user_setting_table.h_lift_idle_acceleration
    end

    local current_x = x + vel_vec.x
    local current_y = y + vel_vec.y
    local current_z = z + vel_vec.z
    self.current_speed = math.sqrt(current_x * current_x + current_y * current_y + current_z * current_z)
    local max_speed = DAV.user_setting_table.max_speed * 0.44704 -- Convert MPH to m/s
    if self.current_speed > max_speed then
        x = 0
        y = 0
        z = 0
    end

    local horizontal_air_resistance_const = DAV.user_setting_table.horizontal_air_resistance_const
    local vertical_air_resistance_const = DAV.user_setting_table.vertical_air_resistance_const

    -- air resistance
    x = x - horizontal_air_resistance_const * vel_vec.x
    y = y - horizontal_air_resistance_const * vel_vec.y
    z = z - vertical_air_resistance_const * vel_vec.z

    -- Always push: PushVelocityHold compares against the value the DLL holds, so a target that has not
    -- moved is free and a slow drift still accumulates until it crosses the deadband. Gating here on
    -- the delta from the previous target would drop sub-eps corrections for good -- that is what made
    -- the autopilot oscillate onto a heading and steer too softly around obstacles.
    self.direction_velocity = Vector3.new(x, y, z)
    self.angular_velocity = Vector3.new(roll, pitch, yaw)
    self:PushFlightTarget()
    return true
end

---@param roll number
---@param pitch number
---@param yaw number
---@return boolean success True if engine ran successfully, false otherwise
function Engine:OnlyAngularRun(roll, pitch, yaw)
    -- Skip execution if vehicle entity is not properly initialized
    if self.av_obj:IsDespawned() then
        self.log_obj:Record(LogLevel.Trace, "Engine:OnlyAngularRun skipped - vehicle not spawned")
        return false
    end
    local current_angle = self.av_obj:GetEulerAngles()
    local roll_restore_amount
    local pitch_restore_amount

    if self.flight_mode == Def.FlightMode.AV then
        roll_restore_amount = DAV.user_setting_table.roll_restore_amount
        pitch_restore_amount = DAV.user_setting_table.pitch_restore_amount
    elseif self.flight_mode == Def.FlightMode.Helicopter then
        roll_restore_amount = DAV.user_setting_table.h_roll_restore_amount
        pitch_restore_amount = DAV.user_setting_table.h_pitch_restore_amount
    end
    local local_roll = 0
    local local_pitch = 0

    if self.flight_mode == Def.FlightMode.Helicopter or self:HasGravity() then
        if current_angle.pitch > pitch_restore_amount then
            local_pitch = local_pitch - self:RestoreRate(
                current_angle.pitch - pitch_restore_amount, pitch_restore_amount)
        elseif current_angle.pitch < -pitch_restore_amount then
            local_pitch = local_pitch + self:RestoreRate(
                -current_angle.pitch - pitch_restore_amount, pitch_restore_amount)
        end
    end

    if current_angle.roll > roll_restore_amount then
        local_roll = local_roll - self:RestoreRate(
            current_angle.roll - roll_restore_amount, roll_restore_amount)
    elseif current_angle.roll < -roll_restore_amount then
        local_roll = local_roll + self:RestoreRate(
            -current_angle.roll - roll_restore_amount, roll_restore_amount)
    end

    -- Smooth roll correction when exceeding max_roll
    if current_angle.roll > self.max_roll then
        local excess_roll = current_angle.roll - self.max_roll
        local_roll = local_roll - excess_roll * 0.5 -- Apply gradual correction
    elseif current_angle.roll < -self.max_roll then
        local excess_roll = -self.max_roll - current_angle.roll
        local_roll = local_roll + excess_roll * 0.5 -- Apply gradual correction
    end

    if current_angle.roll > self.force_restore_angle or current_angle.roll < -self.force_restore_angle then
        local_roll = - current_angle.roll
    elseif current_angle.pitch > self.force_restore_angle or current_angle.pitch < -self.force_restore_angle then
        local_pitch = - current_angle.pitch
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll + d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    self.angular_velocity = Vector3.new(roll, pitch, yaw)
    self:PushFlightTarget()
    return true
end

--- Calculate velocity for AV mode.
---@param action_command_list table
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateAVMode(action_command_list)
    local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0
    local current_angle = self.av_obj:GetEulerAngles()

    local acceleration = DAV.user_setting_table.acceleration
    local vertical_acceleration = DAV.user_setting_table.vertical_acceleration
    local left_right_acceleration = DAV.user_setting_table.left_right_acceleration
    local roll_change_amount = DAV.user_setting_table.roll_change_amount
    local pitch_change_amount = DAV.user_setting_table.pitch_change_amount
    local pitch_restore_amount = DAV.user_setting_table.pitch_restore_amount
    local yaw_change_amount = DAV.user_setting_table.yaw_change_amount
    local rotate_roll_change_amount = DAV.user_setting_table.rotate_roll_change_amount

    local forward_vec = self.av_obj:GetForward()
    local right_vec = self.av_obj:GetRight()

    local local_roll = 0
    local local_pitch = 0

    if action_command_list[1] == Def.ActionList.Up then
        z = z + vertical_acceleration
    elseif action_command_list[1] == Def.ActionList.Down then
        z = z - vertical_acceleration
    elseif action_command_list[1] == Def.ActionList.Forward then
        x = x + acceleration * forward_vec.x
        y = y + acceleration * forward_vec.y
        z = z + acceleration * forward_vec.z
        -- Add pitch stabilization during forward movement
        if current_angle.pitch > pitch_restore_amount then
            local_pitch = local_pitch - pitch_restore_amount
        elseif current_angle.pitch < -pitch_restore_amount then
            local_pitch = local_pitch + pitch_restore_amount
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch - current_angle.pitch
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - current_angle.pitch
        end
    elseif action_command_list[1] == Def.ActionList.Backward then
        x = x - acceleration * forward_vec.x
        y = y - acceleration * forward_vec.y
        z = z - acceleration * forward_vec.z
        -- Add pitch stabilization during backward movement
        if current_angle.pitch > pitch_restore_amount then
            local_pitch = local_pitch - pitch_restore_amount
        elseif current_angle.pitch < -pitch_restore_amount then
            local_pitch = local_pitch + pitch_restore_amount
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch - current_angle.pitch
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - current_angle.pitch
        end
    elseif action_command_list[1] == Def.ActionList.LeftRotate then
        yaw = yaw + yaw_change_amount
        if current_angle.roll > self.max_roll then
            local_roll = 0
        elseif current_angle.roll > 0 then
            local_roll = local_roll - rotate_roll_change_amount * ((self.max_roll - current_angle.roll) / self.max_roll)
        else
            local_roll = local_roll - rotate_roll_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.RightRotate then
        yaw = yaw - yaw_change_amount
        if current_angle.roll < -self.max_roll then
            local_roll = 0
        elseif current_angle.roll < 0 then
            local_roll = local_roll + rotate_roll_change_amount * ((self.max_roll + current_angle.roll) / self.max_roll)
        else
            local_roll = local_roll + rotate_roll_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.Right then
        x = x + left_right_acceleration * right_vec.x
        y = y + left_right_acceleration * right_vec.y
        if current_angle.roll > self.max_roll then
            local_roll = 0
        elseif current_angle.roll > 0 then
            local_roll = local_roll + roll_change_amount * ((self.max_roll - current_angle.roll) / self.max_roll)
        else
            local_roll = local_roll + roll_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.Left then
        x = x - left_right_acceleration * right_vec.x
        y = y - left_right_acceleration * right_vec.y
        if current_angle.roll < -self.max_roll then
            local_roll = 0
        elseif current_angle.roll < 0 then
            local_roll = local_roll - roll_change_amount * ((self.max_roll + current_angle.roll) / self.max_roll)
        else
            local_roll = local_roll - roll_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.LeanForward then
        if current_angle.pitch < -self.max_pitch then
            local_pitch = 0
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - pitch_change_amount * ((self.max_pitch + current_angle.pitch) / self.max_pitch)
        else
            local_pitch = local_pitch - pitch_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.LeanBackward then
        if current_angle.pitch > self.max_pitch then
            local_pitch = 0
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch + pitch_change_amount * ((self.max_pitch - current_angle.pitch) / self.max_pitch)
        else
            local_pitch = local_pitch + pitch_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.LeanReset then
        if current_angle.pitch > pitch_restore_amount then
            local_pitch = local_pitch - pitch_restore_amount
        elseif current_angle.pitch < -pitch_restore_amount then
            local_pitch = local_pitch + pitch_restore_amount
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch - current_angle.pitch
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - current_angle.pitch
        end
    elseif action_command_list[1] == Def.ActionList.Nothing then
        if current_angle.pitch > pitch_restore_amount then
            local_pitch = local_pitch - pitch_restore_amount
        elseif current_angle.pitch < -pitch_restore_amount then
            local_pitch = local_pitch + pitch_restore_amount
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch - current_angle.pitch
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - current_angle.pitch
        end
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll+ d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    return x, y, z, roll, pitch, yaw
end

--- Calculates the velocity of the helicopter
---@param action_command_list table
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateHelicopterMode(action_command_list)
    local dt_scale = DAV.dt_scale or 1
    local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0
    local current_angle = self.av_obj:GetEulerAngles()

    local roll_change_amount = DAV.user_setting_table.h_roll_change_amount
    local pitch_change_amount = DAV.user_setting_table.h_pitch_change_amount
    local yaw_change_amount = DAV.user_setting_table.h_yaw_change_amount
    local acceleration = DAV.user_setting_table.h_acceleration
    local ascend_acceleration = DAV.user_setting_table.h_ascend_acceleration
    local descend_acceleration = DAV.user_setting_table.h_descend_acceleration

    local forward_vec = self.av_obj:GetForward()
    local up_vec = self.av_obj:GetUp()

    local local_roll = 0
    local local_pitch = 0

    if action_command_list[1] == Def.ActionList.HLeanForward then
        if current_angle.pitch < -self.max_pitch then
            local_pitch = 0
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - pitch_change_amount * ((self.max_pitch + current_angle.pitch) / self.max_pitch)
        else
            local_pitch = local_pitch - pitch_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.HLeanBackward then
        if current_angle.pitch > self.max_pitch then
            local_pitch = 0
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch + pitch_change_amount * ((self.max_pitch - current_angle.pitch) / self.max_pitch)
        else
            local_pitch = local_pitch + pitch_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.HLeanLeft then
        if current_angle.roll < -self.max_roll then
            local_roll = 0
        elseif current_angle.roll < 0 then
            local_roll = local_roll - roll_change_amount * ((self.max_roll + current_angle.roll) / self.max_roll)
        else
            local_roll = local_roll - roll_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.HLeanRight then
        if current_angle.roll > self.max_roll then
            local_roll = 0
        elseif current_angle.roll > 0 then
            local_roll = local_roll + roll_change_amount * ((self.max_roll - current_angle.roll) / self.max_roll)
        else
            local_roll = local_roll + roll_change_amount
        end
    elseif action_command_list[1] == Def.ActionList.HRightRotate then
        yaw = yaw - yaw_change_amount
    elseif action_command_list[1] == Def.ActionList.HLeftRotate then
        yaw = yaw + yaw_change_amount
    elseif action_command_list[1] == Def.ActionList.HAccelerate then
        x = x + acceleration * forward_vec.x
        y = y + acceleration * forward_vec.y
        z = z + acceleration * forward_vec.z
    elseif action_command_list[1] == Def.ActionList.HUp then
        z = z + ascend_acceleration * up_vec.z
        -- Accumulator: the lift increment is per-tick and must scale; the rate target above must not.
        self.heli_lift_acceleration = self.heli_lift_acceleration + ascend_acceleration * dt_scale
    elseif action_command_list[1] == Def.ActionList.HDown then
        z = z - descend_acceleration * up_vec.z
        self.heli_lift_acceleration = self.heli_lift_acceleration - descend_acceleration * dt_scale
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll+ d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    return x, y, z, roll, pitch, yaw
end

--- Calculate velocity for idle mode
---@param skip_linear boolean|nil see Engine:CalculateAddVelocity
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateIdleMode(skip_linear)
    local x,y,z,roll,pitch = 0,0,0,0,0

    if not skip_linear and DAV.user_setting_table.is_enable_idle_gravity and not self.av_obj.navigation_obj:IsCollision() then
        local vel_vec, _ = self:GetDirectionAndAngularVelocity()
        local height = self.av_obj.navigation_obj:GetHeight()
        local dest_height = self.av_obj.minimum_distance_to_ground

        local damping = 0.2
        local height_gain = 0.5

        z = z - vel_vec.z * damping
        if math.abs(height - dest_height) > 0.01 then
            z = z + (dest_height - height) * height_gain
        end
    end

    local current_angle = self.av_obj:GetEulerAngles()
    local pitch_restore_amount = DAV.user_setting_table.pitch_restore_amount
    if current_angle.pitch > pitch_restore_amount then
        pitch = pitch - self:RestoreRate(
            current_angle.pitch - pitch_restore_amount, pitch_restore_amount)
    elseif current_angle.pitch < -pitch_restore_amount then
        pitch = pitch + self:RestoreRate(
            -current_angle.pitch - pitch_restore_amount, pitch_restore_amount)
    elseif current_angle.pitch > 0 then
        pitch = pitch - current_angle.pitch
    elseif current_angle.pitch < 0 then
        pitch = pitch - current_angle.pitch
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(roll, pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    return x, y, z, d_roll, d_pitch, d_yaw
end

--- Get RPM count
---@return integer
function Engine:GetRPMCount()
    if self.native_flight_model and self.native_mode3_pushed then
        return math.floor(self.fly_av_system:GetNativeRPM() / self.rpm_count_scale)
    end
    return math.floor(self.rpm_count / self.rpm_count_scale)
end

--- Set fluctuation velocity params
---@param step_width_per_second number
---@param target_velocity number
function Engine:SetFluctuationVelocityParams(step_width_per_second, target_velocity)
    self.step_width_per_second = step_width_per_second
    self.target_velocity = target_velocity
    self:SetControlType(Def.EngineControlType.FluctuationVelocity)
end

--- Fluctuation velocity
---@param delta number
function Engine:FluctuationVelocity(delta)
    -- Check if player is in vehicle - if so, switch to AddForce mode
    if self.av_obj.core_obj.event_obj:IsInVehicle() and not self.av_obj.is_auto_pilot then
        self.log_obj:Record(LogLevel.Info, "Player in vehicle detected - switching from FluctuationVelocity to AddForce")
        self:SetControlType(Def.EngineControlType.AddForce)
        return
    end

    local velocity = Vector4.Vector3To4(self.direction_velocity):Length()
    if velocity == 0 then
        self.log_obj:Record(LogLevel.Trace, "Current velocity is 0 - cannot apply fluctuation")
        return
    end
    if self.step_width_per_second == 0 then
        self.log_obj:Record(LogLevel.Trace, "step_width_per_second is 0")
        self:SetControlType(Def.EngineControlType.ChangeVelocity)
        return
    elseif self.step_width_per_second > 0 and velocity > self.target_velocity then
        self.log_obj:Record(LogLevel.Trace, "velocity > target_velocity")
        self.direction_velocity.x = self.direction_velocity.x / velocity * self.target_velocity
        self.direction_velocity.y = self.direction_velocity.y / velocity * self.target_velocity
        self.direction_velocity.z = self.direction_velocity.z / velocity * self.target_velocity
        self:SetControlType(Def.EngineControlType.ChangeVelocity)
        return
    elseif self.step_width_per_second < 0 and velocity < self.target_velocity then
        self.log_obj:Record(LogLevel.Trace, "velocity < target_velocity")
        self.direction_velocity.x = self.direction_velocity.x / velocity * self.target_velocity
        self.direction_velocity.y = self.direction_velocity.y / velocity * self.target_velocity
        self.direction_velocity.z = self.direction_velocity.z / velocity * self.target_velocity
        self:SetControlType(Def.EngineControlType.ChangeVelocity)
        return
    end
    self.direction_velocity.x = self.direction_velocity.x / velocity * (velocity + self.step_width_per_second * delta)
    self.direction_velocity.y = self.direction_velocity.y / velocity * (velocity + self.step_width_per_second * delta)
    self.direction_velocity.z = self.direction_velocity.z / velocity * (velocity + self.step_width_per_second * delta)
    -- B-4: same hold as ChangeVelocity — the hook re-applies it every physics tick (measured live for
    -- an unboarded vehicle), so the descent only pushes while the ramped target actually moves.
    self:PushFlightTarget()
end

return Engine