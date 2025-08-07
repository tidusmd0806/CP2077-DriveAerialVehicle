local Utils = require("Etc/utils.lua")
Engine = {}
Engine.__index = Engine

--- Constractor
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
    obj.rpm_count_step = 4
    obj.rpm_restore_step = 2
    obj.rpm_count_scale = 80
    obj.rpm_max_count = 10 * obj.rpm_count_scale
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
    self.is_finished_init = true
    self.mass = self.fly_av_system:GetMass()
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
    self:UnsetPhysicsState()
    if self.av_obj.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
        return
    end
    if self.engine_control_type == Def.EngineControlType.ChangeVelocity then
        self.force = Vector3.new(0, 0, 0)
        self.torque = Vector3.new(0, 0, 0)
        self:ChangeVelocity(Def.ChangeVelocityType.Both ,self.direction_velocity, self.angular_velocity)
    elseif self.engine_control_type == Def.EngineControlType.AddForce then
        local direction_velocity = self:GetDirectionVelocity()
        local angular_velocity = self:GetAngularVelocity()
        local mass = self.mass
        self.force = Vector3.new(direction_velocity.x / delta * mass, direction_velocity.y / delta * mass, direction_velocity.z / delta * mass)
        self.torque = Vector3.new(angular_velocity.x / delta * mass, angular_velocity.y / delta * mass, angular_velocity.z / delta * mass)
        self:AddForce(delta, self.force, self.torque)
    elseif self.engine_control_type == Def.EngineControlType.FluctuationVelocity then
        self.force = Vector3.new(0, 0, 0)
        self.torque = Vector3.new(0, 0, 0)
        self:FluctuationVelocity(delta)
    else
        self.log_obj:Record(LogLevel.Error, "Unknown control type")
    end
end

--- Unset physics state
function Engine:UnsetPhysicsState()
    self.fly_av_system:UnsetPhysicsState()
end

--- Enable original physics
---@param on boolean
function Engine:EnableOriginalPhysics(on)
    self.fly_av_system:EnableOriginalPhysics(on)
end

--- Check if has gravity
---@return boolean
function Engine:HasGravity()
    return self.fly_av_system:HasGravity()
end

--- Set gravity
---@param on boolean
function Engine:EnableGravity(on)
    self.fly_av_system:EnableGravity(on)
end

--- Get Vehicle Mass
---@return number
function Engine:GetMass()
    return self.fly_av_system:GetMass()
end

--- If Collision Detected
---@return boolean
function Engine:IsOnGround()
    if not self.is_finished_init then
        return false
    end
    return self.fly_av_system:IsOnGround()
end

--- Get Direction and Angular Velocity
---@return Vector3
---@return Vector3
function Engine:GetDirectionAndAngularVelocity()
    return self.fly_av_system:GetVelocity(), self.fly_av_system:GetAngularVelocity()
end

--- Add force
---@param delta number
---@param force Vector3
---@param torque Vector3
function Engine:AddForce(delta, force, torque)
    local delta_force = Vector3.new(force.x * delta, force.y * delta, force.z * delta)
    local delta_torque = Vector3.new(torque.x * delta, torque.y * delta, torque.z * delta)
    self.fly_av_system:AddForce(delta_force, delta_torque)
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
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateAddVelocity(action_command_list)
    if action_command_list[1] == Def.ActionList.Idle then
        self.rpm_count = 0
        return self:CalculateIdleMode()
    end

    if (action_command_list[1] == Def.ActionList.Forward or action_command_list[1] == Def.ActionList.Up or action_command_list[1] == Def.ActionList.HAccelerate or action_command_list[1] == Def.ActionList.HUp) and self.rpm_count <= self.rpm_max_count then
        self.rpm_count = self.rpm_count + self.rpm_count_step
    elseif (action_command_list[1] == Def.ActionList.Backward or action_command_list[1] == Def.ActionList.Down or action_command_list[1] == Def.ActionList.HDown) and self.rpm_count >= -self.rpm_max_count then
        self.rpm_count = self.rpm_count - self.rpm_count_step
    end
    if self.rpm_count > 0 then
        self.rpm_count = self.rpm_count - self.rpm_restore_step
    elseif self.rpm_count < 0 then
        self.rpm_count = self.rpm_count + self.rpm_restore_step
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

--- Run the engine with specified parameters.
---@param x number
---@param y number
---@param z number
---@param roll number
---@param pitch number
---@param yaw number
function Engine:Run(x, y, z, roll, pitch, yaw)
    local vel_vec, ang_vec = self:GetDirectionAndAngularVelocity()
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

    if self.flight_mode == Def.FlightMode.Helicopter or self.fly_av_system:HasGravity() then
        if current_angle.pitch > pitch_restore_amount then
            local_pitch = local_pitch - pitch_restore_amount
        elseif current_angle.pitch < -pitch_restore_amount then
            local_pitch = local_pitch + pitch_restore_amount
        end
    end

    if current_angle.roll > roll_restore_amount then
        local_roll = local_roll - roll_restore_amount
    elseif current_angle.roll < -roll_restore_amount then
        local_roll = local_roll + roll_restore_amount
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
    local max_speed = (DAV.user_setting_table.max_speed * 1000 + 34867) / 4968 -- Approximate formula
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
    -- holding angle
    if not self.av_obj.is_auto_pilot and not self.is_idle then
        roll = roll - ang_vec.x
        pitch = pitch - ang_vec.y
        yaw = yaw - ang_vec.z
    end

    self.direction_velocity = Vector3.new(x, y, z)
    self.angular_velocity = Vector3.new(roll, pitch, yaw)
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
    elseif action_command_list[1] == Def.ActionList.Backward then
        x = x - acceleration * forward_vec.x
        y = y - acceleration * forward_vec.y
        z = z - acceleration * forward_vec.z
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
    local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0
    local current_angle = self.av_obj:GetEulerAngles()

    local roll_change_amount = DAV.user_setting_table.h_roll_change_amount
    local pitch_change_amount = DAV.user_setting_table.h_pitch_change_amount
    local yaw_change_amount = DAV.user_setting_table.h_yaw_change_amount
    local acceaeration = DAV.user_setting_table.h_acceleration
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
        x = x + acceaeration * forward_vec.x
        y = y + acceaeration * forward_vec.y
        z = z + acceaeration * forward_vec.z
    elseif action_command_list[1] == Def.ActionList.HUp then
        z = z + ascend_acceleration * up_vec.z
        self.heli_lift_acceleration = self.heli_lift_acceleration + ascend_acceleration
    elseif action_command_list[1] == Def.ActionList.HDown then
        z = z - descend_acceleration * up_vec.z
        self.heli_lift_acceleration = self.heli_lift_acceleration - descend_acceleration
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll+ d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    return x, y, z, roll, pitch, yaw
end

--- Calculate velocity for idle mode
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateIdleMode()
    local x,y,z,roll,pitch = 0,0,0,0,0

    if DAV.user_setting_table.is_enable_idle_gravity and self.av_obj:IsCollision() then
        local vel_vec, _ = self:GetDirectionAndAngularVelocity()
        local height = self.av_obj:GetHeight()
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
        pitch = pitch - pitch_restore_amount
    elseif current_angle.pitch < -pitch_restore_amount then
        pitch = pitch + pitch_restore_amount
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
    local velocity = Vector4.Vector3To4(self.direction_velocity):Length()
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