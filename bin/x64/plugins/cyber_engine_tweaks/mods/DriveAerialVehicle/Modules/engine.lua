-- local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
Engine = {}
Engine.__index = Engine

function Engine:New(position_obj, all_models)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Engine")
    obj.position_obj = position_obj
    obj.all_models = all_models

    -- static
    obj.max_roll = 30
    obj.max_pitch = 30
    obj.force_restore_angle = 70
    obj.max_speed = 95

    -- Dynamic
    obj.fly_av_system = nil
    obj.current_speed = 0

    return setmetatable(obj, self)
end

function Engine:Init(entity_id)
    self.fly_av_system = FlyAVSystem.new()
    self.fly_av_system:SetVehicle(entity_id.hash)
end

function Engine:CalculateLinelyVelocity(action_commands)

    local x,y,z,roll,pitch,yaw = 0,0,0,0,0,0

    local dest_height = self.position_obj:GetDestinationHeight()
    local current_angle = self.position_obj:GetEulerAngles()

    local height_change_amount = DAV.user_setting_table.height_change_amount
    local height_acceleration = DAV.user_setting_table.height_acceleration
    local acceleration = DAV.user_setting_table.acceleration
    local left_right_acceleration = DAV.user_setting_table.left_right_acceleration
    local roll_change_amount = DAV.user_setting_table.roll_change_amount
    local roll_restore_amount = DAV.user_setting_table.roll_restore_amount
    local pitch_change_amount = DAV.user_setting_table.pitch_change_amount
    local pitch_restore_amount = DAV.user_setting_table.pitch_restore_amount
    local yaw_change_amount = DAV.user_setting_table.yaw_change_amount
    local rotate_roll_change_amount = DAV.user_setting_table.rotate_roll_change_amount

    local forward_vec = self.position_obj:GetForward()
    local right_vec = self.position_obj:GetRight()

    local local_roll = 0
    local local_pitch = 0

    if action_commands == Def.ActionList.Up then
        self.position_obj:SetDestinationHeight(dest_height + height_change_amount)
    elseif action_commands == Def.ActionList.Down then
        self.position_obj:SetDestinationHeight(dest_height - height_change_amount)
    elseif action_commands == Def.ActionList.Forward then
        x = x + acceleration * forward_vec.x
        y = y + acceleration * forward_vec.y
        self.position_obj:SetDestinationHeight(dest_height + acceleration * forward_vec.z)
    elseif action_commands == Def.ActionList.Backward then
        x = x - acceleration * forward_vec.x
        y = y - acceleration * forward_vec.y
        self.position_obj:SetDestinationHeight(dest_height - acceleration * forward_vec.z)
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
        z = z + left_right_acceleration * right_vec.z
        if current_angle.roll < self.max_roll then
            local_roll = local_roll + roll_change_amount
        end
    elseif action_commands == Def.ActionList.Left then
        x = x - left_right_acceleration * right_vec.x
        y = y - left_right_acceleration * right_vec.y
        z = z - left_right_acceleration * right_vec.z
        if current_angle.roll > -self.max_roll then
            local_roll = local_roll - roll_change_amount
        end
    elseif action_commands == Def.ActionList.LeanForward then
        if current_angle.pitch < -self.max_pitch then
            local_pitch = 0
        else
            local_pitch = local_pitch - pitch_change_amount
        end
    elseif action_commands == Def.ActionList.LeanBackward then
        if current_angle.pitch > self.max_pitch then
            local_pitch = 0
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

    if current_angle.roll > 0 then
        local_roll = local_roll - roll_restore_amount
    elseif current_angle.roll < 0 then
        local_roll = local_roll + roll_restore_amount
    end

    if current_angle.roll > self.force_restore_angle or current_angle.roll < -self.force_restore_angle then
        local_roll = - current_angle.roll
    elseif current_angle.pitch > self.force_restore_angle or current_angle.pitch < -self.force_restore_angle then
        local_pitch = - current_angle.pitch
    end

    -- Holding the height
    dest_height = self.position_obj:GetDestinationHeight()
    local current_height = self.position_obj:GetPosition().z
    z = z + (dest_height - current_height) * height_acceleration

    local d_roll, d_pitch, d_yaw = Utils:CalculateRotationalSpeed(local_roll, local_pitch, 0, current_angle.roll, current_angle.pitch, current_angle.yaw)

    roll = roll+ d_roll
    pitch = pitch + d_pitch
    yaw = yaw + d_yaw

    return x, y, z, roll, pitch, yaw

end

function Engine:AddLinelyVelocity(x, y, z, roll, pitch, yaw)
    local physics_state = self.fly_av_system:GetPhysicsState()
    if physics_state ~= 0 and physics_state ~= 32 then
        self.position_obj.entity:PhysicsWakeUp()
    end

    local vel_vec = self.fly_av_system:GetVelocity()
    local ang_vec = self.fly_av_system:GetAngularVelocity()

    self.current_speed = math.sqrt(x * x + y * y + z * z)
    if self.current_speed > self.max_speed then
        local ratio = self.max_speed / self.current_speed
        x = x * ratio
        y = y * ratio
        z = z * ratio
    end

    local air_resitance_const = 0.01

    -- Holding the position
    x = x - air_resitance_const * vel_vec.x
    y = y - air_resitance_const * vel_vec.y
    z = z - vel_vec.z
    roll = roll - ang_vec.x
    pitch = pitch - ang_vec.y
    yaw = yaw - ang_vec.z

    self.fly_av_system:AddLinelyVelocity(Vector3.new(x, y, z), Vector3.new(roll, pitch, yaw))
end

return Engine
