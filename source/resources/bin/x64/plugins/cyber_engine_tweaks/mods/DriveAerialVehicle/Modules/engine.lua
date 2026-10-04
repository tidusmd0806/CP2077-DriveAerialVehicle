local Utils = require("Etc/utils.lua")
Engine = {}
Engine.__index = Engine

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
    obj.direction_velocity = Vector3.new(0, 0, 0)
    obj.angular_velocity = Vector3.new(0, 0, 0)
    obj.acceleration = Vector3.new(0, 0, 0)
    obj.prev_velocity = Vector3.new(0, 0, 0)
    obj.engine_control_type = Def.EngineControlType.None
    obj.is_finished_init = false
    obj.is_idle = false

    return setmetatable(obj, self)
end

--- Initialize
---@param entity_id EntityID
function Engine:Init(entity_id)
    self.entity_id = entity_id
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
    self.native_tick_probe_interval = 0.5
    self.native_tick_stall_limit = 3
    self.native_tick_probe = 0
    self.native_tick_stall = 0
    self.native_tick_last = nil
    self.log_obj:Record(LogLevel.Info, string.format("native_control=%s native_flight_model=%s mass=%.1f physics_state=%s",
        tostring(self.native_control), tostring(self.native_flight_model), self.mass, tostring(self.fly_av_system:GetPhysicsState())))
    if self.native_flight_model then
        self:PushNativeParams()
    end
    self.is_finished_init = true
end

--- Give up on the native path and hand control back to the Lua flight model.
---@param reason string
function Engine:DisableNative(reason)
    if not self.native_control and not self.native_flight_model then
        return
    end
    self.log_obj:Record(LogLevel.Error, "native flight disabled, falling back to Lua path: " .. reason)
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
    self.native_off_pushed = true
end

--- Fall back to the Lua path when the DLL physics-tick counter stops advancing.
---@param delta number
function Engine:WatchNativeTick(delta)
    if not self.native_tick_readable then
        return
    end
    local control_type = self.engine_control_type
    if control_type ~= Def.EngineControlType.AddForce then
        -- Only manual flight uses the hook; an unboarded vehicle is not simulated.
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

--- Attitude source for the native restore math: true = CET's ToEulerAngles (what the Lua path uses).
local NATIVE_ATTITUDE_FROM_CET = true

--- B-3: push the manual-flight command list; the DLL physics hook runs the flight model per tick.
---@param action_command_lists table list of {action, value}
function Engine:PushNativeCommands(action_command_lists)
    local n = #action_command_lists
    if n > 6 then n = 6 end
    local a = {0, 0, 0, 0, 0, 0}
    local v = {1, 1, 1, 1, 1, 1}
    for i = 1, n do
        local c = action_command_lists[i]
        a[i] = c[1]
        v[i] = c[2] or 1
    end
    local reset = self.native_reset_pending and 1 or 0
    self.native_reset_pending = false
    -- Attitude for the DLL's restore math; W = 0 means "use the DLL's own extraction".
    local att = Vector4.new(0, 0, 0, 0)
    if NATIVE_ATTITUDE_FROM_CET then
        local ang = self.av_obj:GetEulerAngles()
        if ang ~= nil then
            att = Vector4.new(ang.roll, ang.pitch, ang.yaw, 1)
        end
    end
    -- Entity world quaternion (real w in W); the DLL validates it by norm.
    local q = self.av_obj:GetQuaternion()
    local cq = Vector4.new(0, 0, 0, 0)
    if q ~= nil then
        cq = Vector4.new(q.i, q.j, q.k, q.r)
    end
    -- Entity axes: the DLL must use the same vectors the Lua thrust math uses.
    local fwd = self.av_obj:GetForward()
    local right = self.av_obj:GetRight()
    local up = self.av_obj:GetUp()
    local ax_ok = (fwd ~= nil and right ~= nil and up ~= nil) and 1 or 0
    if ax_ok == 0 then
        fwd, right, up = Vector4.new(0, 0, 0, 0), Vector4.new(0, 0, 0, 0), Vector4.new(0, 0, 0, 0)
    end
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
    -- Shadow A/B: run the Lua flight model on the same commands and log its target, to diff against
    -- the DLL's `hook ang target` for the same attitude. Read-only apart from rpm (restored below).
    if DAV.native_shadow then
        local rpm_saved = self.rpm_count
        local xt, yt, zt, rt, pt, yt2 = 0, 0, 0, 0, 0, 0
        for _, c in ipairs(action_command_lists) do
            local x, y, z, r, p, yw = self:CalculateAddVelocity(c)
            local cv = c[2] or 1
            xt = xt + x * cv; yt = yt + y * cv; zt = zt + z * cv
            rt = rt + r * cv; pt = pt + p * cv; yt2 = yt2 + yw * cv
        end
        self.rpm_count = rpm_saved
        if self:Run(xt, yt, zt, rt, pt, yt2) then
            local ang = self.av_obj:GetEulerAngles()
            local av = self.angular_velocity
            self.shadow_probe = (self.shadow_probe or 0) + 1
            if ang ~= nil and self.shadow_probe >= 60 then
                self.shadow_probe = 0
                self.log_obj:Record(LogLevel.Info, string.format(
                    "shadow att=(%.1f,%.1f,%.1f) target=(%.2f,%.2f,%.2f)",
                    ang.roll, ang.pitch, ang.yaw, av.x, av.y, av.z))
            end
        end
    end
end

--- Get Control Type
---@return Def.EngineControlType
function Engine:GetControlType()
    return self.engine_control_type
end

--- Set control type
---@param engine_control_type Def.EngineControlType
function Engine:SetControlType(engine_control_type)
    self.engine_control_type = engine_control_type
end

--- Set Idle
---@param is_idle boolean
function Engine:SetIdle(is_idle)
    self.is_idle = is_idle
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
    self.fly_av_system:SetFlightControl(mode, v, a, gain)
end

--- Update
---@param delta number
function Engine:Update(delta)
    if not self.is_finished_init then
        return
    end
    -- The Engine outlives its entity: gate physics calls so they never hit a despawned entity.
    if self.av_obj == nil or self.av_obj.entity_id == nil then
        return
    end
    if self.av_obj.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
        -- Native keeps applying the last pushed target; force it off once until the menu closes.
        if self.native_control and not self.native_off_pushed then
            self:PushNativeControl(0, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), 0)
            self.native_off_pushed = true
            self.native_mode3_pushed = false
        end
        return
    end
    self.native_off_pushed = false
    -- While unresolved GetMass() is 0 and every physics call is a silent no-op.
    if self.native_control and self.mass <= 0 then
        local mass = self.fly_av_system:GetMass()
        if mass > 0 then
            self.mass = mass
            self.log_obj:Record(LogLevel.Info, string.format("native mass resolved: %.1f", mass))
        end
    end
    -- -1 means "vehicle not resolved yet"; ForceEnablePhysics is what gets a fresh AV simulated.
    if self:GetPhysicsState() ~= 0 then
        self:UnsetPhysicsState()
        self.log_obj:Record(LogLevel.Trace, "Unset DAV physics")
    end
    if self.native_control then
        self:WatchNativeTick(delta)
    end
    -- Re-assert the boarding toggles: a toggle dropped while unresolved leaves game physics fighting.
    if self.native_control and self.engine_control_type == Def.EngineControlType.AddForce then
        self.physics_assert_probe = (self.physics_assert_probe or 0) + delta
        if self.physics_assert_probe >= 1.0 then
            self.physics_assert_probe = 0
            self.physics_assert_warn = (self.physics_assert_warn or 0)
            if self.fly_av_system:EnableOriginalPhysics(false) ~= 1 then
                self.physics_assert_warn = self.physics_assert_warn + 1
                if self.physics_assert_warn <= 3 then
                    self.log_obj:Record(LogLevel.Warning, "EnableOriginalPhysics(false) rejected (vehicle unresolved?)")
                end
            end
            if self.fly_av_system:EnableGravity(false) ~= 1 then
                if self.physics_assert_warn <= 3 then
                    self.log_obj:Record(LogLevel.Warning, "EnableGravity(false) rejected (vehicle unresolved?)")
                end
            end
        end
    end
    if self.native_flight_model and self.engine_control_type == Def.EngineControlType.AddForce
            and not self.av_obj.is_auto_pilot then
        -- B-3: the DLL physics hook runs the whole flight model; nothing to compute here.
        if not self.native_mode3_pushed then
            self.log_obj:Record(LogLevel.Info, "mode3 push (native flight model active)")
            self:PushNativeControl(3, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), self.torque_gain)
            self.native_mode3_pushed = true
        end
        -- Cross-check against the DLL's `att=`/`ext=`/`fwd=` log lines.
        self.native_att_log_probe = (self.native_att_log_probe or 0) + delta
        if self.native_att_log_probe >= 1.0 then
            self.native_att_log_probe = 0
            local ang = self.av_obj:GetEulerAngles()
            local fwd = self.av_obj:GetForward()
            local up = self.av_obj:GetUp()
            if ang ~= nil then
                self.log_obj:Record(LogLevel.Info, string.format(
                    "cet euler roll=%.1f pitch=%.1f yaw=%.1f fwd=(%.2f,%.2f,%.2f) up=(%.2f,%.2f,%.2f)",
                    ang.roll, ang.pitch, ang.yaw, fwd.x, fwd.y, fwd.z, up.x, up.y, up.z))
            end
        end
        self.force = Vector3.new(0, 0, 0)
        self.torque = Vector3.new(0, 0, 0)
        return
    end
    if self.native_mode3_pushed then
        -- Otherwise the hook keeps flying the AV after the player leaves it.
        self:PushNativeControl(0, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), 0)
        self.native_mode3_pushed = false
    end
    if self.engine_control_type == Def.EngineControlType.ChangeVelocity then
        self.force = Vector3.new(0, 0, 0)
        self.torque = Vector3.new(0, 0, 0)
        -- The hook does not run for an unboarded vehicle, so keep the direct write here.
        self:ChangeVelocity(Def.ChangeVelocityType.Both ,self.direction_velocity, self.angular_velocity)
    elseif self.engine_control_type == Def.EngineControlType.AddForce then
        local direction_velocity = self:GetDirectionVelocity()
        local angular_velocity = self:GetAngularVelocity()
        self.force = Vector3.new(direction_velocity.x * self.mass, direction_velocity.y * self.mass, direction_velocity.z * self.mass)
        if self.native_control then
            -- Native computes torque from the live angular velocity error each physics tick.
            self.torque = Vector3.new(0, 0, 0)
            self:PushNativeControl(1, direction_velocity, angular_velocity, self.torque_gain)
        else
            local _, actual_angular_velocity = self:GetDirectionAndAngularVelocity()
            local angular_velocity_diff = Vector3.new(angular_velocity.x - actual_angular_velocity.x, angular_velocity.y - actual_angular_velocity.y, angular_velocity.z - actual_angular_velocity.z)
            local mass = self.mass
            self.force = Vector3.new(direction_velocity.x * mass, direction_velocity.y * mass, direction_velocity.z * mass)
            self.torque = Vector3.new(angular_velocity_diff.x * self.torque_gain, angular_velocity_diff.y * self.torque_gain, angular_velocity_diff.z * self.torque_gain)
            self:AddForce(self.force, self.torque)
        end
    elseif self.engine_control_type == Def.EngineControlType.FluctuationVelocity then
        self.force = Vector3.new(0, 0, 0)
        self.torque = Vector3.new(0, 0, 0)
        self:FluctuationVelocity(delta)
    elseif self.engine_control_type == Def.EngineControlType.Blocking then
        -- Do nothing, just block the physics
        if self.native_control then
            self:PushNativeControl(0, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), 0)
        end
        self.log_obj:Record(LogLevel.Trace, "Blocking DAV physics")
    else
        self.log_obj:Record(LogLevel.Error, "Unknown control type", "Engine:Update - control_type: " .. tostring(self.engine_control_type))
    end
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
    self.direction_velocity = direction_velocity
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

    self.direction_velocity = Vector3.new(x, y, z)
    self.angular_velocity = Vector3.new(roll, pitch, yaw)
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
    self.engine_control_type = Def.EngineControlType.FluctuationVelocity
end

--- Fluctuation velocity
---@param delta number
function Engine:FluctuationVelocity(delta)
    -- Check if player is in vehicle - if so, switch to AddForce mode
    if self.av_obj.core_obj.event_obj:IsInVehicle() and not self.av_obj.is_auto_pilot then
        self.log_obj:Record(LogLevel.Info, "Player in vehicle detected - switching from FluctuationVelocity to AddForce")
        self.engine_control_type = Def.EngineControlType.AddForce
        return
    end

    local velocity = Vector4.Vector3To4(self.direction_velocity):Length()
    if velocity == 0 then
        self.log_obj:Record(LogLevel.Trace, "Current velocity is 0 - cannot apply fluctuation")
        return
    end
    if self.step_width_per_second == 0 then
        self.log_obj:Record(LogLevel.Trace, "step_width_per_second is 0")
        self.engine_control_type = Def.EngineControlType.ChangeVelocity
        return
    elseif self.step_width_per_second > 0 and velocity > self.target_velocity then
        self.log_obj:Record(LogLevel.Trace, "velocity > target_velocity")
        self.direction_velocity.x = self.direction_velocity.x / velocity * self.target_velocity
        self.direction_velocity.y = self.direction_velocity.y / velocity * self.target_velocity
        self.direction_velocity.z = self.direction_velocity.z / velocity * self.target_velocity
        self.engine_control_type = Def.EngineControlType.ChangeVelocity
        return
    elseif self.step_width_per_second < 0 and velocity < self.target_velocity then
        self.log_obj:Record(LogLevel.Trace, "velocity < target_velocity")
        self.direction_velocity.x = self.direction_velocity.x / velocity * self.target_velocity
        self.direction_velocity.y = self.direction_velocity.y / velocity * self.target_velocity
        self.direction_velocity.z = self.direction_velocity.z / velocity * self.target_velocity
        self.engine_control_type = Def.EngineControlType.ChangeVelocity
        return
    end
    self.direction_velocity.x = self.direction_velocity.x / velocity * (velocity + self.step_width_per_second * delta)
    self.direction_velocity.y = self.direction_velocity.y / velocity * (velocity + self.step_width_per_second * delta)
    self.direction_velocity.z = self.direction_velocity.z / velocity * (velocity + self.step_width_per_second * delta)
    -- Direct write: this runs while the AV is unboarded (spawn descent), where the physics hook
    -- does not fire.
    self:ChangeVelocity(Def.ChangeVelocityType.Both ,self.direction_velocity, self.angular_velocity)
end

return Engine