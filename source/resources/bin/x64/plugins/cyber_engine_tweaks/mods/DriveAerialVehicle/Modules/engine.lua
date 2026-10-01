local Utils = require("Etc/utils.lua")
Engine = {}
Engine.__index = Engine

--- Flag bits packed into the W component of FlyAVSystem:GetFlightState().
--- W is an integer bitfield, not a float in any meaningful sense. Keep in
--- sync with DAVStateFlags in the DAV red4ext plugin (src/Main.cpp).
local STATE_ON_GROUND = 1
local STATE_GRAVITY = 2
local STATE_PHYSICS_OFF = 4
local STATE_VALID = 8

--- Test one bit of the snapshot's flag field.
--- Written with division instead of `&`/`>>` so the file keeps running under
--- a plain-Lua harness that may not be 5.4.
local function state_has(bits, flag)
    return math.floor(bits / flag) % 2 == 1
end

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
    -- RPM ramp. These are increments per *base tick* (0.01 s); the effective
    -- ramp rate is step / resolution, so every use is multiplied by DAV.dt_scale
    -- to keep the per-second ramp constant. See Etc/timescale.lua.
    obj.rpm_count_step = 4
    obj.rpm_restore_step = 2
    obj.rpm_count_scale = 80
    obj.rpm_max_count = 10 * obj.rpm_count_scale
    obj.torque_gain = 1000
    -- Width of the restore boundary layer, in degrees, at the base control
    -- period. The restore was a bare relay: full rate target the instant the
    -- angle left the deadband, zero the instant it came back. A relay commits to
    -- the full rate for a whole control tick no matter how close it already is,
    -- so the overshoot it produces grows in proportion to the tick -- at 20 Hz
    -- the body is 5x further along before the correction lands, and it rocks
    -- around the deadband edge instead of settling onto it.
    --
    -- Inside the boundary layer the commanded rate now falls off linearly to
    -- zero at the deadband edge, so the body decelerates onto the target. The
    -- width is multiplied by dt_scale so the taper covers exactly the extra
    -- per-tick travel: at the 0.01 tuning reference this is the number below,
    -- and it widens from there as the loop gets coarser.
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
    --- Frame-cached physics snapshot. See Engine:RefreshSnapshot.
    obj.snap = {
        velocity = Vector3.new(0, 0, 0),
        on_ground = false,
        has_gravity = false,
        physics_off = false,
        valid = false,
    }
    obj.snap_seq = -1

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
    -- A different body. Whatever the previous one reported is not this one's
    -- velocity, gravity or ground contact.
    self:InvalidateSnapshot()
    self.is_finished_init = true
end

--- Drop the cached physics snapshot so the next read goes back to the plugin.
--- Needed whenever the underlying body changes; a stale snapshot would
--- otherwise be served for the rest of the frame.
function Engine:InvalidateSnapshot()
    self.snap_seq = -1
end

--- Return this rendered frame's physics snapshot, reading it once if this is
--- the first thing to ask since the frame started.
---
--- One `GetFlightState` transition per frame serves every consumer in the
--- mod. Before, Engine:Run, Engine:Update, IsOnGround and HasGravity each
--- resolved their own -- and two of them threw half of what they paid to
--- read away. None of it can change inside a frame: the body is stepped once
--- per frame, so the second read of a value returns the first read's answer.
---
--- Same frame-counter contract as AV:GetEulerAngles. The snapshot and the
--- vector inside it are shared; callers must treat them as read-only.
---@return table|nil nil when the engine has not finished initializing
function Engine:RefreshSnapshot()
    if not self.is_finished_init then
        return nil
    end
    local frame = DAV.frame_seq
    if frame == nil then
        -- No frame counter means we cannot reason about freshness. Read
        -- every time rather than cache forever against a counter that never
        -- moves.
        return self:ReadSnapshot()
    end
    if self.snap_seq ~= frame then
        self:ReadSnapshot()
        self.snap_seq = frame
    end
    return self.snap
end

--- Perform the actual read into self.snap. Prefer RefreshSnapshot.
---@return table
function Engine:ReadSnapshot()
    local snap = self.snap
    local state = self.fly_av_system:GetFlightState()
    local vel = snap.velocity
    if state == nil then
        vel.x, vel.y, vel.z = 0, 0, 0
        snap.on_ground = false
        snap.has_gravity = false
        snap.physics_off = false
        snap.valid = false
        return snap
    end
    local bits = math.floor(state.w or 0)
    snap.valid = state_has(bits, STATE_VALID)
    if snap.valid then
        vel.x, vel.y, vel.z = state.x, state.y, state.z
        snap.on_ground = state_has(bits, STATE_ON_GROUND)
        snap.has_gravity = state_has(bits, STATE_GRAVITY)
        snap.physics_off = state_has(bits, STATE_PHYSICS_OFF)
    else
        -- No locked handle. Report a parked craft rather than whatever the
        -- last body was doing.
        vel.x, vel.y, vel.z = 0, 0, 0
        snap.on_ground = false
        snap.has_gravity = false
        snap.physics_off = false
    end
    return snap
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

--- Update
---@param delta number
function Engine:Update(delta)
    if not self.is_finished_init then
        return
    end
    if self.av_obj.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
        return
    end
    -- The physics state rides along in the frame snapshot, so the per-tick
    -- GetPhysicsState poll is gone. The re-enable only costs a transition in
    -- the rare tick that actually finds the body disabled -- and AddForceTracked
    -- re-checks at the moment of writing, so a snapshot that went stale
    -- mid-frame cannot let a disabled body slip through.
    local snap = self:RefreshSnapshot()
    if snap ~= nil and snap.physics_off then
        self:UnsetPhysicsState()
        self.log_obj:Record(LogLevel.Trace, "Unset DAV physics")
    end
    if self.engine_control_type == Def.EngineControlType.ChangeVelocity then
        self.force = Vector3.new(0, 0, 0)
        self.torque = Vector3.new(0, 0, 0)
        self:ChangeVelocity(Def.ChangeVelocityType.Both ,self.direction_velocity, self.angular_velocity)
    elseif self.engine_control_type == Def.EngineControlType.AddForce then
        local mass = self.mass
        local direction_velocity = self.direction_velocity
        self.force = Vector3.new(direction_velocity.x * mass, direction_velocity.y * mass, direction_velocity.z * mass)
        -- The tracking torque is closed inside the plugin. Computing it here
        -- meant pulling the body's angular velocity back across the boundary
        -- for nothing but a subtraction; the plugin subtracts it where the
        -- data already lives and hands the applied torque back, so
        -- `self.torque` still records what this tick commanded.
        self.torque = self.fly_av_system:AddForceTracked(self.force, self.angular_velocity, self.torque_gain)
    elseif self.engine_control_type == Def.EngineControlType.FluctuationVelocity then
        self.force = Vector3.new(0, 0, 0)
        self.torque = Vector3.new(0, 0, 0)
        self:FluctuationVelocity(delta)
    elseif self.engine_control_type == Def.EngineControlType.Blocking then
        -- Do nothing, just block the physics
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
--- Served from the frame snapshot; see Engine:RefreshSnapshot.
---@return boolean
function Engine:HasGravity()
    local snap = self:RefreshSnapshot()
    return snap ~= nil and snap.has_gravity
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
--- Served from the frame snapshot; see Engine:RefreshSnapshot.
---@return boolean
function Engine:IsOnGround()
    if not self.is_finished_init then
        return false
    end
    -- Ignore ground checks for a short time after initialization (prevent false detections from physics engine initialization)
    local elapsed_time = os.clock() - self.av_obj.spawn_time
    if elapsed_time < self.ground_check_delay then
        return false
    end
    local snap = self:RefreshSnapshot()
    return snap ~= nil and snap.on_ground
end

--- Get Direction and Angular Velocity
---
--- Uncached: this is two transitions back out of the plugin. Nothing on the
--- control path needs the angular half any more -- the tracking torque that
--- used to require it is closed inside AddForceTracked -- so prefer
--- GetVelocity(), which is one transition per frame shared by every caller.
---@return Vector3
---@return Vector3
function Engine:GetDirectionAndAngularVelocity()
    if not self.is_finished_init then
        return Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)
    end
    return self.fly_av_system:GetVelocity(), self.fly_av_system:GetAngularVelocity()
end

--- Get the linear velocity only.
--- Served from the frame snapshot, so N callers in one frame cost one
--- transition between them. See Engine:RefreshSnapshot for the read-only
--- contract on the returned vector.
---@return Vector3|nil nil when the physics handle is not up yet
function Engine:GetVelocity()
    local snap = self:RefreshSnapshot()
    if snap == nil then
        return nil
    end
    return snap.velocity
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
---@param skip_linear boolean|nil Idle only: skip the hover/height term. Callers
---        that discard x/y/z (DespawnFromGround feeds only the angular half to
---        OnlyAngularRun) use this to avoid an IsOnGround probe, a velocity
---        read and a ground raycast whose result is thrown away.
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateAddVelocity(action_command_list, skip_linear)
    -- `or 1` keeps the base (pre-timescale) behaviour if DAV.dt_scale was never
    -- published, e.g. under a test harness that stubs DAV by hand.
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

    -- GetVelocity is nil before the physics handle is up, where the old
    -- GetDirectionAndAngularVelocity handed back a zero vector and the run
    -- carried on. Keep carrying on: bailing here would also skip the thruster
    -- and sound passes that AV:Operate does after Run.
    local vel_vec = self:GetVelocity() or Vector3.new(0, 0, 0)

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
        -- Accumulator: builds lift over time, so the increment is per-tick and
        -- must scale. The `z` term above is a rate target and must not.
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
        -- GetVelocity is nil before the physics handle is up, where the old
        -- GetDirectionAndAngularVelocity handed back a zero vector.
        local vel_vec = self:GetVelocity() or Vector3.new(0, 0, 0)
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
    self:ChangeVelocity(Def.ChangeVelocityType.Both ,self.direction_velocity, self.angular_velocity)
end

return Engine