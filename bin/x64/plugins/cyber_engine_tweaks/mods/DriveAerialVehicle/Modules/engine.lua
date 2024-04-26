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
    obj.model_index = 1

    obj.roll_speed = nil
    obj.pitch_speed = nil
    obj.yaw_speed = nil
    obj.roll_restore_speed = nil
    obj.pitch_restore_speed = nil
    obj.max_roll = nil
    obj.min_roll = nil
    obj.max_pitch = nil
    obj.min_pitch = nil
    obj.max_lift_force = nil
    obj.min_lift_force = nil
    obj.time_to_max = nil
    obj.time_to_min = nil
    obj.mess = nil
    obj.gravity_constant = 9.8
    obj.air_resistance_constant = nil
    obj.rebound_constant = nil
    obj.max_speed = 300

    obj.power_on_off_wait = 2 -- 0.2s
    obj.max_spinner_horizenal_force = nil
    obj.max_spinner_vertical_force = nil
    obj.time_to_max_spinner_horizenal_force = nil
    obj.time_to_max_spinner_vertical_force = nil

    -- set default parameters
    obj.next_indication = {roll = 0, pitch = 0, yaw = 0}
    obj.base_angle = nil
    obj.is_finished_init = false
    obj.horizenal_x_speed = 0
    obj.horizenal_y_speed = 0
    obj.horizenal_speed = 0
    obj.vertical_speed = 0
    obj.clock = 0
    obj.dynamic_lift_force = 0
    obj.current_speed = 0
    obj.current_mode = Def.PowerMode.Off
    obj.is_falling = false
    obj.heli_horizenal_boost_ratio = DAV.heli_horizenal_boost_ratio

    obj.spinner_horizenal_force = 0
    obj.spinner_vertical_force = 0
    obj.spinner_horizenal_force_sign = 1
    obj.spinner_vertical_force_sign = 1

    return setmetatable(obj, self)
end

function Engine:SetModel(index)
    -- set pyhsical parameters
    self.roll_speed = self.all_models[index].roll_speed
    self.pitch_speed = self.all_models[index].pitch_speed
    self.yaw_speed = self.all_models[index].yaw_speed
    self.roll_restore_speed = self.all_models[index].roll_restore_speed
    self.pitch_restore_speed = self.all_models[index].pitch_restore_speed
    self.max_roll = self.all_models[index].max_roll
    self.min_roll = self.all_models[index].min_roll
    self.max_pitch = self.all_models[index].max_pitch
    self.min_pitch = self.all_models[index].min_pitch

    self.mess = self.all_models[index].mess
    self.air_resistance_constant = self.all_models[index].air_resistance_constant
    self.max_lift_force = self.mess * self.gravity_constant + self.all_models[index].max_lift_force
    self.min_lift_force = self.mess * self.gravity_constant - self.all_models[index].min_lift_force
    self.lift_force = self.min_lift_force
    self.time_to_max = self.all_models[index].time_to_max * 10 -- 10 times for clocking 0.1s
    self.time_to_min = self.all_models[index].time_to_min * 10
    self.rebound_constant = self.all_models[index].rebound_constant

    self.spinner_roll_speed = self.all_models[index].spinner_roll_speed
    self.spinner_yaw_speed = self.all_models[index].spinner_yaw_speed
    self.spinner_roll_restore_speed = self.all_models[index].spinner_roll_restore_speed
    self.max_spinner_roll = self.all_models[index].max_spinner_roll
    self.min_spinner_roll = self.all_models[index].min_spinner_roll
    self.max_spinner_horizenal_force = self.all_models[index].max_spinner_horizenal_force
    self.max_spinner_vertical_force = self.all_models[index].max_spinner_vertical_force
    self.time_to_max_spinner_horizenal_force = self.all_models[index].time_to_max_spinner_horizenal_force * 10
    self.time_to_max_spinner_natural_horizenal_force = self.all_models[index].time_to_max_spinner_natural_horizenal_force * 10
    self.time_to_max_spinner_vertical_force = self.all_models[index].time_to_max_spinner_vertical_force * 10
    self.time_to_max_spinner_natural_vertical_force = self.all_models[index].time_to_max_spinner_natural_horizenal_force * 10
    self.spinner_air_resistance_constant = self.all_models[index].spinner_air_resistance_constant

    self.heli_horizenal_boost_ratio = DAV.heli_horizenal_boost_ratio
end

function Engine:Init()
    if not self.is_finished_init then
        Cron.Every(0.1, {tick = 1}, function(timer)
            self.clock = self.clock + 1
        end)
        self.base_angle = self.position_obj:GetEulerAngles()
    end
    if DAV.flight_mode == Def.FlightMode.Heli then
        self.current_mode = Def.PowerMode.Hover
    end
    self.horizenal_x_speed = 0
    self.horizenal_y_speed = 0
    self.vertical_speed = 0
    self.clock = 0
    self.is_finished_init = true
end

function Engine:GetNextPosition(movement)

    -- wait for init
    if not self.is_finished_init then
        return 0, 0, 0, 0, 0, 0
    end

    if DAV.flight_mode == Def.FlightMode.Heli then
        local roll, pitch, yaw = self:CalculateHeliIndication(movement)
        self:CalculateLiftPower(movement)
        local x, y, z = self:CalcureteHeliVelocity()
        return x, y, z, roll, pitch, yaw
    elseif DAV.flight_mode == Def.FlightMode.Spinner then
        self:CalculateSpinnerPower(movement)
        local roll, pitch, yaw = self:CalculateSpinnerIndication(movement)
        local x, y, z = self:CalcureteSpinnerVelocity()
        return x, y, z, roll, pitch, yaw
    else
        return 0, 0, 0, 0, 0, 0
    end

end

function Engine:SetSpeedForcibly(vel)
    self.current_speed = vel
end

function Engine:GetSpeed()
    return self.current_speed
end

function Engine:CalculateHeliIndication(movement)

    local actually_indication = self.position_obj:GetEulerAngles()
    self.next_indication["roll"] = actually_indication.roll
    self.next_indication["pitch"] = actually_indication.pitch
    self.next_indication["yaw"] = actually_indication.yaw

    -- set indication
    if movement == Def.ActionList.HeliForward then
        self.next_indication["pitch"] = actually_indication.pitch - self.pitch_speed
    elseif movement == Def.ActionList.HeliBackward then
        self.next_indication["pitch"] = actually_indication.pitch + self.pitch_speed
    elseif movement == Def.ActionList.HeliRight then
        self.next_indication["roll"] = actually_indication.roll + self.roll_speed
    elseif movement == Def.ActionList.HeliLeft then
        self.next_indication["roll"] = actually_indication.roll - self.roll_speed
    elseif movement == Def.ActionList.HeliTurnRight then
        self.next_indication["yaw"] = actually_indication.yaw + self.yaw_speed
    elseif movement == Def.ActionList.HeliTurnLeft then
        self.next_indication["yaw"] = actually_indication.yaw - self.yaw_speed
    else
        -- set roll restoration
        if math.abs(self.next_indication["roll"] - self.base_angle.roll) > self.roll_restore_speed then
            if self.next_indication["roll"] > self.base_angle.roll then
                self.next_indication["roll"] = actually_indication.roll - self.roll_restore_speed
            else
                self.next_indication["roll"] = actually_indication.roll + self.roll_restore_speed
            end
        else
            self.next_indication["roll"] = self.base_angle.roll
        end

        -- set pitch restoration
        if math.abs(self.next_indication["pitch"] - self.base_angle.pitch) > self.pitch_restore_speed then
            if self.next_indication["pitch"] > self.base_angle.pitch then
                self.next_indication["pitch"] = actually_indication.pitch - self.pitch_restore_speed
            else
                self.next_indication["pitch"] = actually_indication.pitch + self.pitch_restore_speed
            end
        else
            self.next_indication["pitch"] = self.base_angle.pitch
        end

    end

    -- check limitation
    if self.next_indication["roll"] > self.max_roll then
        self.next_indication["roll"] = self.max_roll
    elseif self.next_indication["roll"] < self.min_roll then
        self.next_indication["roll"] = self.min_roll
    end
    if self.next_indication["pitch"] > self.max_pitch then
        self.next_indication["pitch"] = self.max_pitch
    elseif self.next_indication["pitch"] < self.min_pitch then
        self.next_indication["pitch"] = self.min_pitch
    end

    -- calculate delta
    local roll = self.next_indication["roll"] - actually_indication.roll
    local pitch = self.next_indication["pitch"] - actually_indication.pitch
    local yaw = self.next_indication["yaw"] - actually_indication.yaw

    return roll, pitch, yaw

end

function Engine:CalculateLiftPower(movement)
    if movement == Def.ActionList.HeliDown then
        self.log_obj:Record(LogLevel.Trace, "Change Power Off")
        self.clock = 0
        self.dynamic_lift_force = self.lift_force
        self.current_mode = Def.PowerMode.Off
        self.position_obj:SetEngineState(self.current_mode)
    elseif movement == Def.ActionList.HeliHold then
        self.log_obj:Record(LogLevel.Trace, "Change Power Hold")
        self.clock = 0
        self.dynamic_lift_force = self.lift_force
        self.current_mode = Def.PowerMode.Hold
    elseif movement == Def.ActionList.HeliUp or self.current_mode == Def.PowerMode.On then
        if self.current_mode ~= Def.PowerMode.On then
            self.log_obj:Record(LogLevel.Trace, "Change Power On")
            self.clock = 0
            self.dynamic_lift_force = self.lift_force
            self.current_mode = Def.PowerMode.On
            self.position_obj:SetEngineState(self.current_mode)
        else
            self:SetLiftPowerUpCurve(self.clock)
        end
    elseif movement == Def.ActionList.HeliHover or self.current_mode == Def.PowerMode.Hover then
        if self.current_mode ~= Def.PowerMode.Hover then
            self.log_obj:Record(LogLevel.Trace, "Change Power Hover")
            self.clock = 0
            self.dynamic_lift_force = self.lift_force
            self.current_mode = Def.PowerMode.Hover
        else
            self:SetLiftPowerUpCurve(self.clock)
        end
    else
        self:SetLiftPowerDownCurve(self.clock)
    end
end

function Engine:SetLiftPowerUpCurve(time)
    if time <= self.time_to_max then
        self.lift_force = self.dynamic_lift_force + (self.max_lift_force - self.min_lift_force) * (time / self.time_to_max)
        if self.lift_force > self.max_lift_force then
            self.lift_force = self.max_lift_force
        end
    else
        self.lift_force = self.max_lift_force
    end
end

function Engine:SetLiftPowerDownCurve(time)
    if time <= self.time_to_min then
        self.lift_force = self.dynamic_lift_force - (self.max_lift_force - self.min_lift_force) * (time / self.time_to_min)
        if self.lift_force < self.min_lift_force then
            self.lift_force = self.min_lift_force
        end
    else
        self.lift_force = self.min_lift_force
    end
end

function Engine:CalcureteHeliVelocity()
    local quot = self.position_obj:GetQuaternion()
    local force_local = {x = 0, y = 0, z = self.lift_force}

    -- calculate vertical list force of av in world coordinate
    local force_quat = {r = 0, i = force_local.x, j = force_local.y, k = force_local.z}
    local q_conj = Utils:QuaternionConjugate(quot)
    local temp = Utils:QuaternionMultiply(quot, force_quat)
    local force_world = Utils:QuaternionMultiply(temp, q_conj)

    if self.current_mode == Def.PowerMode.Hold or self.current_mode == Def.PowerMode.Hover then
        local speed = math.sqrt(force_world.i * force_world.i + force_world.j * force_world.j + force_world.k * force_world.k)
        self.vertical_speed = 0
        force_world.k = -self.vertical_speed * self.mess / DAV.time_resolution + self.mess * self.gravity_constant
        local new_speed = math.sqrt(force_world.i * force_world.i + force_world.j * force_world.j + force_world.k * force_world.k)
        force_world.i = force_world.i * speed / new_speed
        force_world.j = force_world.j * speed / new_speed
    else
        self.vertical_speed = self.vertical_speed + (DAV.time_resolution / self.mess) * (force_world.k - self.mess * self.gravity_constant - self.air_resistance_constant * self.vertical_speed)
    end

    self.horizenal_x_speed = self.horizenal_x_speed + (DAV.time_resolution / self.mess) * (force_world.i * self.heli_horizenal_boost_ratio - self.air_resistance_constant * self.horizenal_x_speed)
    self.horizenal_y_speed = self.horizenal_y_speed + (DAV.time_resolution / self.mess) * (force_world.j * self.heli_horizenal_boost_ratio - self.air_resistance_constant * self.horizenal_y_speed)

    -- check limitation
    self.current_speed = math.sqrt(self.horizenal_x_speed * self.horizenal_x_speed + self.horizenal_y_speed * self.horizenal_y_speed + self.vertical_speed * self.vertical_speed)
    if self.current_speed > self.max_speed then
        self.horizenal_x_speed = self.horizenal_x_speed * self.max_speed / self.current_speed
        self.horizenal_y_speed = self.horizenal_y_speed * self.max_speed / self.current_speed
        self.vertical_speed = self.vertical_speed * self.max_speed / self.current_speed
    end

    local x, y, z = self.horizenal_x_speed * DAV.time_resolution, self.horizenal_y_speed * DAV.time_resolution, self.vertical_speed * DAV.time_resolution

    return x, y, z
end

function Engine:SetSpeedAfterRebound()
    local reflection_vector = self.position_obj:GetReflectionVector()
    local reflection_vector_norm = math.sqrt(reflection_vector.x * reflection_vector.x + reflection_vector.y * reflection_vector.y + reflection_vector.z * reflection_vector.z)
    local reflection_value = reflection_vector_norm * self.current_speed * self.rebound_constant

    self.horizenal_x_speed = reflection_vector.x * reflection_value
    self.horizenal_y_speed = reflection_vector.y * reflection_value
    self.vertical_speed = reflection_vector.z * reflection_value

    -- check falling
    local horizenal_speed = math.sqrt(self.horizenal_x_speed * self.horizenal_x_speed + self.horizenal_y_speed * self.horizenal_y_speed)
    if self.vertical_speed > 0 and math.abs(self.vertical_speed) > horizenal_speed then
        self.is_falling = true
    else
        self.is_falling = false
    end
end

function Engine:IsInFalling()
    if self.is_falling then
        return true
    else
        return false
    end
end

function Engine:CalculateSpinnerIndication(movement)

    local actually_indication = self.position_obj:GetEulerAngles()
    self.next_indication["roll"] = actually_indication.roll
    self.next_indication["pitch"] = actually_indication.pitch
    self.next_indication["yaw"] = actually_indication.yaw

    -- set indication
    local roll_speed = self.spinner_roll_speed * (self.current_speed / self.max_speed)
    if movement == Def.ActionList.SpinnerRight then
        self.next_indication["roll"] = actually_indication.roll + roll_speed
        self.next_indication["yaw"] = actually_indication.yaw - self.spinner_yaw_speed * self.spinner_horizenal_force_sign
    elseif movement == Def.ActionList.SpinnerLeft then
        self.next_indication["roll"] = actually_indication.roll - roll_speed
        self.next_indication["yaw"] = actually_indication.yaw + self.spinner_yaw_speed * self.spinner_horizenal_force_sign
    else
        -- set roll restoration
        local roll_restore_speed = self.spinner_roll_restore_speed * (1 - (self.current_speed / self.max_speed))
        if math.abs(self.next_indication["roll"] - self.base_angle.roll) > roll_restore_speed then
            if self.next_indication["roll"] > self.base_angle.roll then
                self.next_indication["roll"] = actually_indication.roll - roll_restore_speed
            else
                self.next_indication["roll"] = actually_indication.roll + roll_restore_speed
            end
        else
            self.next_indication["roll"] = self.base_angle.roll
        end

    end

    -- check limitation
    if self.next_indication["roll"] > self.max_spinner_roll then
        self.next_indication["roll"] = self.max_spinner_roll
    elseif self.next_indication["roll"] < self.min_spinner_roll then
        self.next_indication["roll"] = self.min_spinner_roll
    end

    -- calculate delta
    local roll = self.next_indication["roll"] - actually_indication.roll
    local pitch = self.next_indication["pitch"] - actually_indication.pitch
    local yaw = self.next_indication["yaw"] - actually_indication.yaw

    return roll, pitch, yaw
end

function Engine:CalculateSpinnerPower(movement)

    -- natural power down
    if self.spinner_horizenal_force ~= 0 then
        self:SetSpinnerHorizenalPowerDown(self.time_to_max_spinner_natural_horizenal_force)
    end
    if self.spinner_vertical_force ~= 0 then
        self:SetSpinnerVerticalPowerDown(self.time_to_max_spinner_natural_horizenal_force)
    end

    if movement == Def.ActionList.SpinnerForward then
        self.log_obj:Record(LogLevel.Trace, "Forward Move")
        if self.current_mode == Def.PowerMode.Off then
            if self.clock > self.power_on_off_wait then
                self.current_mode = Def.PowerMode.On
                self.clock = 0
                self.position_obj:SetEngineState(self.current_mode)
            end
        elseif self.spinner_horizenal_force_sign < 0 then
                self.spinner_horizenal_force_sign = 1
                self.spinner_horizenal_force = 0
        else
            self:SetSpinnerHorizenalPowerUp(self.time_to_max_spinner_horizenal_force)
        end
    elseif movement == Def.ActionList.SpinnerBackward then
        self.log_obj:Record(LogLevel.Trace, "Backward Move")
        if self.current_mode == Def.PowerMode.Off then
            if self.clock > self.power_on_off_wait then
                self.current_mode = Def.PowerMode.On
                self.clock = 0
                self.position_obj:SetEngineState(self.current_mode)
            end
        elseif self.spinner_horizenal_force_sign > 0 then
            self.spinner_horizenal_force_sign = -1
            self.spinner_horizenal_force = 0
        else
            self:SetSpinnerHorizenalPowerUp(self.time_to_max_spinner_horizenal_force)
        end
    elseif movement == Def.ActionList.SpinnerUp then
        self.log_obj:Record(LogLevel.Trace, "Up Move")
        if self.current_mode == Def.PowerMode.Off then
            if self.clock > self.power_on_off_wait then
                self.current_mode = Def.PowerMode.On
                self.clock = 0
                self.position_obj:SetEngineState(self.current_mode)
            end
        elseif self.spinner_vertical_force_sign < 0 then
            self.spinner_vertical_force_sign = 1
            self.spinner_vertical_force = 0
        else
            self:SetSpinnerVerticalPowerUp(self.time_to_max_spinner_vertical_force)
        end
    elseif movement == Def.ActionList.SpinnerDown then
        self.log_obj:Record(LogLevel.Trace, "Down Move")
        if self.current_mode == Def.PowerMode.Off then
            if self.clock > self.power_on_off_wait then
                self.current_mode = Def.PowerMode.On
                self.clock = 0
                self.position_obj:SetEngineState(self.current_mode)
            end
        elseif self.spinner_vertical_force_sign > 0 then
            self.spinner_vertical_force_sign = -1
            self.spinner_vertical_force = 0
        else
            self:SetSpinnerVerticalPowerUp(self.time_to_max_spinner_vertical_force)

        end
    else
        if self.current_mode == Def.PowerMode.On and self.spinner_horizenal_force == 0 and self.spinner_vertical_force == 0 then
            self.clock = 0
            self.current_mode = Def.PowerMode.Off
            self.position_obj:SetEngineState(self.current_mode)
        end
    end

end

function Engine:SetSpinnerHorizenalPowerUp(time)
    self.spinner_horizenal_force = self.spinner_horizenal_force + (self.max_spinner_horizenal_force / time)
    if self.spinner_horizenal_force > self.max_spinner_horizenal_force then
        self.spinner_horizenal_force = self.max_spinner_horizenal_force
    end
end

function Engine:SetSpinnerHorizenalPowerDown(time)
    self.spinner_horizenal_force = self.spinner_horizenal_force - (self.max_spinner_horizenal_force / time)
    if self.spinner_horizenal_force < 0 then
        self.spinner_horizenal_force = 0
    end
end

function Engine:SetSpinnerVerticalPowerUp(time)

    self.spinner_vertical_force = self.spinner_vertical_force + (self.max_spinner_vertical_force / time)
    if self.spinner_vertical_force > self.max_spinner_vertical_force then
        self.spinner_vertical_force = self.max_spinner_vertical_force
    end

end

function Engine:SetSpinnerVerticalPowerDown(time)

    self.spinner_vertical_force = self.spinner_vertical_force - (self.max_spinner_vertical_force / time)
    if self.spinner_vertical_force < 0 then
        self.spinner_vertical_force = 0
    end

end

function Engine:CalcureteSpinnerVelocity()
    local forward = self.position_obj:GetForward()
    local forward_xy_lenght = math.sqrt(forward.x * forward.x + forward.y * forward.y)
    local forward_xy_basic = {x = forward.x / forward_xy_lenght, y = forward.y / forward_xy_lenght}

    local current_xy_speed = math.sqrt(self.horizenal_x_speed * self.horizenal_x_speed + self.horizenal_y_speed * self.horizenal_y_speed)

    -- Calculate the difference between current velocity vector and desired direction
    local velocity_diff_x = 0
    local velocity_diff_y = 0
    if self.spinner_horizenal_force_sign > 0 then
        velocity_diff_x = self.horizenal_x_speed - forward_xy_basic.x * current_xy_speed
        velocity_diff_y = self.horizenal_y_speed - forward_xy_basic.y * current_xy_speed
    else
        velocity_diff_x = self.horizenal_x_speed + forward_xy_basic.x * current_xy_speed
        velocity_diff_y = self.horizenal_y_speed + forward_xy_basic.y * current_xy_speed
    end

    -- Gradually adjust velocity towards desired direction
    local adjustment_factor = 0.1
    self.horizenal_x_speed = self.horizenal_x_speed - adjustment_factor * velocity_diff_x
    self.horizenal_y_speed = self.horizenal_y_speed - adjustment_factor * velocity_diff_y

    self.horizenal_x_speed = self.horizenal_x_speed + (DAV.time_resolution / self.mess)
                            * (self.spinner_horizenal_force_sign * self.spinner_horizenal_force * forward_xy_basic.x - self.spinner_air_resistance_constant * self.horizenal_x_speed * math.abs(self.horizenal_x_speed))
    self.horizenal_y_speed = self.horizenal_y_speed + (DAV.time_resolution / self.mess)
                            * (self.spinner_horizenal_force_sign * self.spinner_horizenal_force * forward_xy_basic.y - self.spinner_air_resistance_constant * self.horizenal_y_speed * math.abs(self.horizenal_y_speed))
    self.vertical_speed = self.vertical_speed + (DAV.time_resolution / self.mess) * (self.spinner_vertical_force_sign * self.spinner_vertical_force - self.spinner_air_resistance_constant * self.vertical_speed * math.abs(self.vertical_speed))

    -- check limitation
    self.current_speed = math.sqrt(self.horizenal_x_speed * self.horizenal_x_speed + self.horizenal_y_speed * self.horizenal_y_speed + self.vertical_speed * self.vertical_speed)
    if self.current_speed > self.max_speed then
        self.horizenal_x_speed = self.horizenal_x_speed * self.max_speed / self.current_speed
        self.horizenal_y_speed = self.horizenal_y_speed * self.max_speed / self.current_speed
        self.vertical_speed = self.vertical_speed * self.max_speed / self.current_speed
        self.current_speed = self.max_speed
    end

    local x, y, z = self.horizenal_x_speed * DAV.time_resolution, self.horizenal_y_speed * DAV.time_resolution, self.vertical_speed * DAV.time_resolution

    return x, y, z
end

return Engine
