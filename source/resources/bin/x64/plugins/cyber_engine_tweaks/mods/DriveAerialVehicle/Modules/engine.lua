local Utils = require("Etc/utils.lua")
Engine = {}
Engine.__index = Engine

--- Constractor
--- @param position_obj any Position instance
--- @param all_models table all models data
--- @return table
function Engine:New(position_obj, all_models)
    ---instance---
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Engine")
    obj.position_obj = position_obj
    obj.all_models = all_models

    ---static---
    obj.max_roll = 30
    obj.max_pitch = 30
    obj.force_restore_angle = 70
    obj.rpm_count_step = 4
    obj.rpm_restore_step = 2
    obj.rpm_count_scale = 80
    obj.rpm_max_count = 10 * obj.rpm_count_scale
    obj.gravitational_acceleration = 9.8
    ---dynamic---
    obj.entity_id = nil
    obj.flight_mode = Def.FlightMode.AV
    obj.fly_av_system = nil
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
    -- obj.hover_height = 0
    obj.end_point_for_linearly_autopilot = Vector4.new(0, 0, 0, 1)
    obj.end_decreased_distance_for_linearly_autopilot = 0
    obj.start_increased_time_for_linearly_autopilot = 0
    obj.end_decreased_time_for_linearly_autopilot = 0
    obj.min_speed_for_linearly_autopilot = 0
    obj.max_speed_for_linearly_autopilot = 0
    obj.is_rocked_angle_for_linearly_autopilot = false
    obj.is_enable_limearly_autopilot = false
    obj.autopilot_time = 0

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
end

--- Set control type
---@param engine_control_type integer
function Engine:SetControlType(engine_control_type)
    self.engine_control_type = engine_control_type
end

--- Update
---@param delta number
function Engine:Update(delta)
    if not self.is_finished_init then
        return
    end
    self:UnsetPhysicsState()
    self:SetAcceleration(delta)
    if self.engine_control_type == Def.EngineControlType.ChangeVelocity then
        self:ChangeVelocity(Def.ChangeVelocityType.Both ,self.direction_velocity, self.angular_velocity)
    elseif self.engine_control_type == Def.EngineControlType.AddForce then
        self:AddForce(delta, self.force, self.torque)
    elseif self.engine_control_type == Def.EngineControlType.LinearlyAutopilot then
        self:OperateLinelyAutopilot(delta)
    else
        self.log_obj:Record(LogLevel.Error, "Unknown control type")
    end
end

--- Unset physics state
function Engine:UnsetPhysicsState()
    self.fly_av_system:UnsetPhysicsState()
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

--- Get gravitational force
---@return number
function Engine:GetGravitationalForce()
    local mass = self.fly_av_system:GetMass()
    return -self.gravitational_acceleration * mass
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


--- Get acceleration
---@return Vector3
function Engine:GetAcceleration()
    return self.acceleration
end

--- Set acceleration
---@param delta number
function Engine:SetAcceleration(delta)
    local current_velocity = self.fly_av_system:GetVelocity()
    self.acceleration.x = (current_velocity.x - self.prev_velocity.x) / delta
    self.acceleration.y = (current_velocity.y - self.prev_velocity.y) / delta
    self.acceleration.z = (current_velocity.z - self.prev_velocity.z) / delta
    self.prev_velocity = current_velocity
end

--- Calculate linearly velocity.
---@param action_command_list table
function Engine:CalculateForceAndTorque(action_command_list)
    if self.flight_mode == Def.FlightMode.AV then
        self:CalculateAVForceAndTorque(action_command_list)
    elseif self.flight_mode == Def.FlightMode.Helicopter then
        -- self:CalculateHelicopterMode(action_command)
    else
        self.log_obj:Record(LogLevel.Critical, "Unknown flight mode: " .. self.flight_mode)
    end
end

--- Calculate velocity for AV mode.
---@param action_command_list table
function Engine:CalculateAVForceAndTorque(action_command_list)
    -- local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0
    local entity = Game.FindEntityByID(self.entity_id)
    local current_angle = entity:GetWorldOrientation():ToEulerAngles()

    -- local acceleration = DAV.user_setting_table.acceleration
    local vertical_acceleration = DAV.user_setting_table.vertical_acceleration
    local left_right_acceleration = DAV.user_setting_table.left_right_acceleration
    local roll_change_amount = DAV.user_setting_table.roll_change_amount
    local pitch_change_amount = DAV.user_setting_table.pitch_change_amount
    local pitch_restore_amount = DAV.user_setting_table.pitch_restore_amount
    local yaw_change_amount = DAV.user_setting_table.yaw_change_amount
    local rotate_roll_change_amount = DAV.user_setting_table.rotate_roll_change_amount

    local forward_vec = entity:GetWorldForward()
    local right_vec = entity:GetWorldRight()

    local force_vec4 = Vector4.new(0, 0, 0, 1)
    local acceleration = 10000
    if action_command_list[1] == Def.ActionList.Forward then
        force_vec4.x = acceleration * forward_vec.x
        force_vec4.y = acceleration * forward_vec.y
        force_vec4.z = acceleration * forward_vec.z
    elseif action_command_list[1] == Def.ActionList.Idle then
        force_vec4.x = 0
        force_vec4.y = 0
        force_vec4.z = 0
    end
    self:SetForce(Vector4.Vector4To3(force_vec4))

    -- local local_roll = 0
    -- local local_pitch = 0

    -- if action_commands == Def.ActionList.Up then
    --     z = z + vertical_acceleration
    -- elseif action_commands == Def.ActionList.Down then
    --     z = z - vertical_acceleration
    -- elseif action_commands == Def.ActionList.Forward then
    --     x = x + acceleration * forward_vec.x
    --     y = y + acceleration * forward_vec.y
    --     z = z + acceleration * forward_vec.z
    -- elseif action_commands == Def.ActionList.Backward then
    --     x = x - acceleration * forward_vec.x
    --     y = y - acceleration * forward_vec.y
    --     z = z - acceleration * forward_vec.z
    -- elseif action_commands == Def.ActionList.RightRotate then
    --     yaw = yaw + yaw_change_amount
    --     if current_angle.roll > -self.max_roll then
    --         local_roll = local_roll - rotate_roll_change_amount
    --     end
    -- elseif action_commands == Def.ActionList.LeftRotate then
    --     yaw = yaw - yaw_change_amount
    --     if current_angle.roll < self.max_roll then
    --         local_roll = local_roll + rotate_roll_change_amount
    --     end
    -- elseif action_commands == Def.ActionList.Right then
    --     x = x + left_right_acceleration * right_vec.x
    --     y = y + left_right_acceleration * right_vec.y
    --     if current_angle.roll < self.max_roll then
    --         local_roll = local_roll + roll_change_amount
    --     end
    -- elseif action_commands == Def.ActionList.Left then
    --     x = x - left_right_acceleration * right_vec.x
    --     y = y - left_right_acceleration * right_vec.y
    --     if current_angle.roll > -self.max_roll then
    --         local_roll = local_roll - roll_change_amount
    --     end
    -- elseif action_commands == Def.ActionList.LeanForward then
    --     if current_angle.pitch < -self.max_pitch then
    --         local_pitch = 0
    --     elseif current_angle.pitch < 0 then
    --         local_pitch = local_pitch - pitch_change_amount * ((self.max_pitch + current_angle.pitch) / self.max_pitch)
    --     else
    --         local_pitch = local_pitch - pitch_change_amount
    --     end
    -- elseif action_commands == Def.ActionList.LeanBackward then
    --     if current_angle.pitch > self.max_pitch then
    --         local_pitch = 0
    --     elseif current_angle.pitch > 0 then
    --         local_pitch = local_pitch + pitch_change_amount * ((self.max_pitch - current_angle.pitch) / self.max_pitch)
    --     else
    --         local_pitch = local_pitch + pitch_change_amount
    --     end
    -- elseif action_commands == Def.ActionList.LeanReset then
    --     if current_angle.pitch > pitch_restore_amount then
    --         local_pitch = local_pitch - pitch_restore_amount
    --     elseif current_angle.pitch < -pitch_restore_amount then
    --         local_pitch = local_pitch + pitch_restore_amount
    --     elseif current_angle.pitch > 0 then
    --         local_pitch = local_pitch - current_angle.pitch
    --     elseif current_angle.pitch < 0 then
    --         local_pitch = local_pitch - current_angle.pitch
    --     end
    -- elseif action_commands == Def.ActionList.Nothing then
    --     if current_angle.pitch > pitch_restore_amount then
    --         local_pitch = local_pitch - pitch_restore_amount
    --     elseif current_angle.pitch < -pitch_restore_amount then
    --         local_pitch = local_pitch + pitch_restore_amount
    --     elseif current_angle.pitch > 0 then
    --         local_pitch = local_pitch - current_angle.pitch
    --     elseif current_angle.pitch < 0 then
    --         local_pitch = local_pitch - current_angle.pitch
    --     end
    -- end

    -- local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    -- roll = roll+ d_roll
    -- pitch = pitch + d_pitch
    -- yaw = yaw + d_yaw

    -- return x, y, z, roll, pitch, yaw
end

--- Calculate linearly velocity.
---@param action_command number
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateLinelyVelocity(action_command)
    if action_command == Def.ActionList.Idle then
        if self.fly_av_system:GetPhysicsState() ~= 0 or not DAV.user_setting_table.is_enable_idle_gravity then
            self.fly_av_system:EnableGravity(false)
        elseif not self.fly_av_system:HasGravity() then
            self.fly_av_system:EnableGravity(true)
        end
        self.rpm_count = 0
        return self:CalculateIdleMode()
    else
        if self.fly_av_system:HasGravity() then
            self.fly_av_system:EnableGravity(false)
        end
    end

    if (action_command == Def.ActionList.Forward or action_command == Def.ActionList.Up or action_command == Def.ActionList.HAccelerate or action_command == Def.ActionList.HUp) and self.rpm_count <= self.rpm_max_count then
        self.rpm_count = self.rpm_count + self.rpm_count_step
    elseif (action_command == Def.ActionList.Backward or action_command == Def.ActionList.Down or action_command == Def.ActionList.HDown) and self.rpm_count >= -self.rpm_max_count then
        self.rpm_count = self.rpm_count - self.rpm_count_step
    end
    if self.rpm_count > 0 then
        self.rpm_count = self.rpm_count - self.rpm_restore_step
    elseif self.rpm_count < 0 then
        self.rpm_count = self.rpm_count + self.rpm_restore_step
    end

    if self.flight_mode == Def.FlightMode.AV then
        return self:CalculateAVMode(action_command)
    elseif self.flight_mode == Def.FlightMode.Helicopter then
        return self:CalculateHelicopterMode(action_command)
    else
        self.log_obj:Record(LogLevel.Critical, "Unknown flight mode: " .. self.flight_mode)
        return 0, 0, 0, 0, 0, 0
    end
end

--- Interface for RED4Ext Plugin. Add linearly velocity.
---@param x number
---@param y number
---@param z number
---@param roll number
---@param pitch number
---@param yaw number
function Engine:AddLinelyVelocity(x, y, z, roll, pitch, yaw)
    local vel_vec = self.fly_av_system:GetVelocity()
    local ang_vec = self.fly_av_system:GetAngularVelocity()
    local current_angle = self.position_obj:GetEulerAngles()
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

    if current_angle.roll > self.force_restore_angle or current_angle.roll < -self.force_restore_angle then
        local_roll = - current_angle.roll
    elseif current_angle.pitch > self.force_restore_angle or current_angle.pitch < -self.force_restore_angle then
        local_pitch = - current_angle.pitch
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll+ d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    if self.flight_mode == Def.FlightMode.Helicopter then
        local up_vec = self.position_obj:GetUp()
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
    roll = roll - ang_vec.x
    pitch = pitch - ang_vec.y
    yaw = yaw - ang_vec.z

    self.fly_av_system:AddVelocity(Vector3.new(x, y, z), Vector3.new(roll, pitch, yaw))
end

--- Change linearly velocity of AV.
-- ---@param x number
-- ---@param y number
-- ---@param z number
-- ---@param roll number
-- ---@param pitch number
-- ---@param yaw number
-- ---@param type number 0: velocity, 1: angle, 2: both
-- function Engine:ChangeVelocity(x, y, z, roll, pitch, yaw, type)
--     self.fly_av_system:ChangeVelocity(Vector3.new(x, y, z), Vector3.new(roll, pitch, yaw), type)
-- end

--- Calculate velocity for AV mode.
---@param action_commands Def.ActionList
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateAVMode(action_commands)
    local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0
    local current_angle = self.position_obj:GetEulerAngles()

    local acceleration = DAV.user_setting_table.acceleration
    local vertical_acceleration = DAV.user_setting_table.vertical_acceleration
    local left_right_acceleration = DAV.user_setting_table.left_right_acceleration
    local roll_change_amount = DAV.user_setting_table.roll_change_amount
    local pitch_change_amount = DAV.user_setting_table.pitch_change_amount
    local pitch_restore_amount = DAV.user_setting_table.pitch_restore_amount
    local yaw_change_amount = DAV.user_setting_table.yaw_change_amount
    local rotate_roll_change_amount = DAV.user_setting_table.rotate_roll_change_amount

    local forward_vec = self.position_obj:GetForward()
    local right_vec = self.position_obj:GetRight()

    local local_roll = 0
    local local_pitch = 0

    if action_commands == Def.ActionList.Up then
        z = z + vertical_acceleration
    elseif action_commands == Def.ActionList.Down then
        z = z - vertical_acceleration
    elseif action_commands == Def.ActionList.Forward then
        x = x + acceleration * forward_vec.x
        y = y + acceleration * forward_vec.y
        z = z + acceleration * forward_vec.z
    elseif action_commands == Def.ActionList.Backward then
        x = x - acceleration * forward_vec.x
        y = y - acceleration * forward_vec.y
        z = z - acceleration * forward_vec.z
    elseif action_commands == Def.ActionList.RightRotate then
        yaw = yaw + yaw_change_amount
        if current_angle.roll > -self.max_roll then
            local_roll = local_roll - rotate_roll_change_amount
        end
    elseif action_commands == Def.ActionList.LeftRotate then
        yaw = yaw - yaw_change_amount
        if current_angle.roll < self.max_roll then
            local_roll = local_roll + rotate_roll_change_amount
        end
    elseif action_commands == Def.ActionList.Right then
        x = x + left_right_acceleration * right_vec.x
        y = y + left_right_acceleration * right_vec.y
        if current_angle.roll < self.max_roll then
            local_roll = local_roll + roll_change_amount
        end
    elseif action_commands == Def.ActionList.Left then
        x = x - left_right_acceleration * right_vec.x
        y = y - left_right_acceleration * right_vec.y
        if current_angle.roll > -self.max_roll then
            local_roll = local_roll - roll_change_amount
        end
    elseif action_commands == Def.ActionList.LeanForward then
        if current_angle.pitch < -self.max_pitch then
            local_pitch = 0
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - pitch_change_amount * ((self.max_pitch + current_angle.pitch) / self.max_pitch)
        else
            local_pitch = local_pitch - pitch_change_amount
        end
    elseif action_commands == Def.ActionList.LeanBackward then
        if current_angle.pitch > self.max_pitch then
            local_pitch = 0
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch + pitch_change_amount * ((self.max_pitch - current_angle.pitch) / self.max_pitch)
        else
            local_pitch = local_pitch + pitch_change_amount
        end
    elseif action_commands == Def.ActionList.LeanReset then
        if current_angle.pitch > pitch_restore_amount then
            local_pitch = local_pitch - pitch_restore_amount
        elseif current_angle.pitch < -pitch_restore_amount then
            local_pitch = local_pitch + pitch_restore_amount
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch - current_angle.pitch
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - current_angle.pitch
        end
    elseif action_commands == Def.ActionList.Nothing then
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
---@param action_commands Def.ActionList
---@return number x
---@return number y
---@return number z
---@return number roll
---@return number pitch
---@return number yaw
function Engine:CalculateHelicopterMode(action_commands)
    local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0
    local current_angle = self.position_obj:GetEulerAngles()

    local roll_change_amount = DAV.user_setting_table.h_roll_change_amount
    local pitch_change_amount = DAV.user_setting_table.h_pitch_change_amount
    local yaw_change_amount = DAV.user_setting_table.h_yaw_change_amount
    local acceaeration = DAV.user_setting_table.h_acceleration
    local ascend_acceleration = DAV.user_setting_table.h_ascend_acceleration
    local descend_acceleration = DAV.user_setting_table.h_descend_acceleration

    local forward_vec = self.position_obj:GetForward()
    local up_vec = self.position_obj:GetUp()

    local local_roll = 0
    local local_pitch = 0

    if action_commands == Def.ActionList.HLeanForward then
        if current_angle.pitch < -self.max_pitch then
            local_pitch = 0
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch - pitch_change_amount * ((self.max_pitch + current_angle.pitch) / self.max_pitch)
        else
            local_pitch = local_pitch - pitch_change_amount
        end
    elseif action_commands == Def.ActionList.HLeanBackward then
        if current_angle.pitch > self.max_pitch then
            local_pitch = 0
        elseif current_angle.pitch > 0 then
            local_pitch = local_pitch + pitch_change_amount * ((self.max_pitch - current_angle.pitch) / self.max_pitch)
        else
            local_pitch = local_pitch + pitch_change_amount
        end
    elseif action_commands == Def.ActionList.HLeanRight then
        if current_angle.roll < -self.max_roll then
            local_roll = 0
        else
            local_roll = local_roll - roll_change_amount
        end
    elseif action_commands == Def.ActionList.HLeanLeft then
        if current_angle.roll > self.max_roll then
            local_roll = 0
        else
            local_roll = local_roll + roll_change_amount
        end
    elseif action_commands == Def.ActionList.HRightRotate then
        yaw = yaw - yaw_change_amount
    elseif action_commands == Def.ActionList.HLeftRotate then
        yaw = yaw + yaw_change_amount
    elseif action_commands == Def.ActionList.HAccelerate then
        x = x + acceaeration * forward_vec.x
        y = y + acceaeration * forward_vec.y
        z = z + acceaeration * forward_vec.z
    elseif action_commands == Def.ActionList.HUp then
        z = z + ascend_acceleration * up_vec.z
        self.heli_lift_acceleration = self.heli_lift_acceleration + ascend_acceleration
    elseif action_commands == Def.ActionList.HDown then
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
    local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0

    if self.fly_av_system:GetPhysicsState() == 0 and DAV.user_setting_table.is_enable_idle_gravity then
        local vel_vec = self.fly_av_system:GetVelocity()
        local height = self.position_obj:GetHeight()
        local dest_height = self.position_obj.minimum_distance_to_ground
        z = z - vel_vec.z
        if height < dest_height then
            local diff = dest_height - height
            z = z + diff * diff
        end
    end

    return x, y, z, roll, pitch, yaw
end

--- Get RPM count
---@return integer
function Engine:GetRPMCount()
    return math.floor(self.rpm_count / self.rpm_count_scale)
end

--- Set linearly autopilot mode
---@param enable boolean
---@param end_point Vector4
---@param end_decreased_distance number
---@param first_increased_time number
---@param end_decreased_time number
---@param min_speed number
---@param max_speed number
---@param is_rocked_angle boolean
function Engine:SetlinearlyAutopilotMode(enable, end_point, end_decreased_distance, first_increased_time, end_decreased_time, min_speed, max_speed, is_rocked_angle)
    if enable then
        self:SetControlType(Def.EngineControlType.LinearlyAutopilot)
        self.end_point_for_linearly_autopilot = end_point
        self.end_decreased_distance_for_linearly_autopilot = end_decreased_distance
        self.first_increased_time_for_linearly_autopilot = first_increased_time
        self.end_decreased_time_for_linearly_autopilot = end_decreased_time
        self.min_speed_for_linearly_autopilot = min_speed
        self.max_speed_for_linearly_autopilot = max_speed
        self.is_rocked_angle_for_linearly_autopilot = is_rocked_angle
        self.is_enable_limearly_autopilot = true
        self.autopilot_time = 0
    else
        self:SetControlType(Def.EngineControlType.ChangeVelocity)
        self:SetDirectionVelocity(Vector3.new(0, 0, 0))
        self:SetAngularVelocity(Vector3.new(0, 0, 0))
        self.autopilot_time = 0
        self.is_enable_limearly_autopilot = false
    end
end

--- Operate linely autopilot
---@param delta number
function Engine:OperateLinelyAutopilot(delta)
    if not self.is_enable_limearly_autopilot then
        self.log_obj:Record(LogLevel.Critical, "Don't operate because linely autopilot is not enabled")
        return
    end
    local av_position = Game.FindEntityByID(self.entity_id):GetWorldPosition()
    local direction_vector = Vector4.new(self.end_point_for_linearly_autopilot.x - av_position.x,
                                            self.end_point_for_linearly_autopilot.y - av_position.y,
                                            self.end_point_for_linearly_autopilot.z - av_position.z, 1)
    local direcrtion_vector_normalized = Vector4.Normalize(direction_vector)
    local gradient_start
    if self.first_increased_time_for_linearly_autopilot == 0 then
         gradient_start = 0
    else
        gradient_start = (self.max_speed_for_linearly_autopilot - self.min_speed_for_linearly_autopilot) / self.first_increased_time_for_linearly_autopilot
    end
    local gradient_end
    if self.end_decreased_time_for_linearly_autopilot == 0 then
        gradient_end = 0
    else
        gradient_end = (self.min_speed_for_linearly_autopilot - self.max_speed_for_linearly_autopilot) / self.end_decreased_time_for_linearly_autopilot
    end
    local remaining_distance = Vector4.Distance(av_position, self.end_point_for_linearly_autopilot)
    local current_velocity = self:GetDirectionVelocity()
    local current_velocity_norm = math.sqrt(current_velocity.x * current_velocity.x + current_velocity.y * current_velocity.y + current_velocity.z * current_velocity.z)
    if self.autopilot_time < self.first_increased_time_for_linearly_autopilot then
        local direction_velocity = Vector3.new(current_velocity.x + direcrtion_vector_normalized.x * gradient_start * delta, current_velocity.y + direcrtion_vector_normalized.y * gradient_start * delta, current_velocity.z + direcrtion_vector_normalized.z * gradient_start * delta)
        local direction_velocity_norm = math.sqrt(direction_velocity.x * direction_velocity.x + direction_velocity.y * direction_velocity.y + direction_velocity.z * direction_velocity.z)
        if direction_velocity_norm > self.max_speed_for_linearly_autopilot then
            direction_velocity.x = direction_velocity.x / direction_velocity_norm * self.max_speed_for_linearly_autopilot
            direction_velocity.y = direction_velocity.y / direction_velocity_norm * self.max_speed_for_linearly_autopilot
            direction_velocity.z = direction_velocity.z / direction_velocity_norm * self.max_speed_for_linearly_autopilot
        end
        self:SetDirectionVelocity(direction_velocity)
    elseif remaining_distance < 1 or current_velocity_norm == 0 then
        self:SetlinearlyAutopilotMode(false, Vector4.new(0, 0, 0, 1), 0, 0, 0, 0, 0, false)
        return
    elseif remaining_distance < self.end_decreased_distance_for_linearly_autopilot then
        local direction_velocity = Vector3.new(current_velocity.x + direcrtion_vector_normalized.x * gradient_end * delta, current_velocity.y + direcrtion_vector_normalized.y * gradient_end * delta, current_velocity.z + direcrtion_vector_normalized.z * gradient_end * delta)
        local direction_velocity_norm = math.sqrt(direction_velocity.x * direction_velocity.x + direction_velocity.y * direction_velocity.y + direction_velocity.z * direction_velocity.z)
        if direction_velocity_norm < self.min_speed_for_linearly_autopilot then
            direction_velocity.x = direction_velocity.x / direction_velocity_norm * self.min_speed_for_linearly_autopilot
            direction_velocity.y = direction_velocity.y / direction_velocity_norm * self.min_speed_for_linearly_autopilot
            direction_velocity.z = direction_velocity.z / direction_velocity_norm * self.min_speed_for_linearly_autopilot
        end
        self:SetDirectionVelocity(direction_velocity)
    end
    self:ChangeVelocity(Def.ChangeVelocityType.Both ,self.direction_velocity, self.angular_velocity)
    self.autopilot_time = self.autopilot_time + delta
end

return Engine