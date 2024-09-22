-- local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
Engine = {}
Engine.__index = Engine

function Engine:New(position_obj, all_models)
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Engine")
    obj.position_obj = position_obj
    obj.all_models = all_models

    -- static --
    obj.max_roll = 30
    obj.max_pitch = 30
    obj.force_restore_angle = 70
    obj.max_speed = 95 -- Cannot take values ​​greater than 100
    obj.idle_height_offset = 0.8
    obj.rpm_count_step = 4
    obj.rpm_restore_step = 2
    obj.rpm_count_scale = 80
    obj.rpm_max_count = 10 * obj.rpm_count_scale
    -- dynamic --
    obj.flight_mode = Def.FlightMode.AV
    obj.fly_av_system = nil
    obj.current_speed = 0
    obj.heli_lift_acceleration = DAV.user_setting_table.h_lift_idle_acceleration
    obj.rpm_count = 0

    return setmetatable(obj, self)
end

function Engine:Init(entity_id)

    self.flight_mode = self.all_models[DAV.model_index].flight_mode
    self.fly_av_system = FlyAVSystem.new()
    self.fly_av_system:SetVehicle(entity_id.hash)

end

function Engine:CalculateLinelyVelocity(action_command)

    if action_command == Def.ActionList.Idle then
        if not self.fly_av_system:HasGravity() then
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
    end

end

function Engine:AddLinelyVelocity(x, y, z, roll, pitch, yaw)

    -- local physics_state = self.fly_av_system:GetPhysicsState()
    -- if physics_state ~= 0 and physics_state ~= 32 then
    --     self.position_obj.entity:PhysicsWakeUp()
    -- end

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
    if self.current_speed > self.max_speed then
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

    self.fly_av_system:AddLinelyVelocity(Vector3.new(x, y, z), Vector3.new(roll, pitch, yaw))

end

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
        if current_angle.pitch > 0 then
            local_pitch = local_pitch - pitch_restore_amount
        elseif current_angle.pitch < 0 then
            local_pitch = local_pitch + pitch_restore_amount
        end
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll+ d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    return x, y, z, roll, pitch, yaw

end

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
        -- x = x + ascend_acceleration * up_vec.x
        -- y = y + ascend_acceleration * up_vec.y
        z = z + ascend_acceleration * up_vec.z
        self.heli_lift_acceleration = self.heli_lift_acceleration + ascend_acceleration
    elseif action_commands == Def.ActionList.HDown then
        -- x = x + descend_acceleration * up_vec.x
        -- y = y + descend_acceleration * up_vec.y
        z = z - descend_acceleration * up_vec.z
        self.heli_lift_acceleration = self.heli_lift_acceleration - descend_acceleration
    end

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll+ d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    return x, y, z, roll, pitch, yaw

end

function Engine:CalculateIdleMode()

    local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0

    local vel_vec = self.fly_av_system:GetVelocity()
    local height = self.position_obj:GetHeight()
    local dest_height = self.position_obj.minimum_distance_to_ground + self.idle_height_offset
    z = z - vel_vec.z
    if height < dest_height then
        local diff = dest_height - height
        z = z + diff * diff
    end

    return x, y, z, roll, pitch, yaw

end

function Engine:GetRPMCount()
    return math.floor(self.rpm_count / self.rpm_count_scale)
end

return Engine