local Def = require("Tools/def.lua")
local Log = require("Tools/log.lua")
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
    obj.max_speed = 80


    -- set default parameters
    obj.next_indication = {roll = 0, pitch = 0, yaw = 0}
    obj.base_angle = nil
    obj.is_finished_init = false
    obj.horizenal_x_speed = 0
    obj.horizenal_y_speed = 0
    obj.vertical_speed = 0
    obj.clock = 0
    obj.dynamic_lift_force = 0
    obj.current_speed = 0
    obj.current_mode = Def.PowerMode.Off

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
    self.time_to_max = self.all_models[index].time_to_max
    self.time_to_min = self.all_models[index].time_to_min
    self.rebound_constant = self.all_models[index].rebound_constant

end

function Engine:Init()
    if not self.is_finished_init then
        DAV.Cron.Every(1, {tick = 1}, function(timer)
            self.clock = self.clock + 1
        end)
        self.base_angle = self.position_obj:GetEulerAngles()
    end
    self.current_mode = Def.PowerMode.Hover
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

    local roll, pitch, yaw = self:CalculateIndication(movement)
    self:CalculatePower(movement)
    local x, y, z = self:CalcureteVelocity()

    return x, y, z, roll, pitch, yaw
end

function Engine:CalculateIndication(movement)

    local actually_indication = self.position_obj:GetEulerAngles()
    self.next_indication["roll"] = actually_indication.roll
    self.next_indication["pitch"] = actually_indication.pitch
    self.next_indication["yaw"] = actually_indication.yaw

    -- set indication
    if movement == Def.ActionList.Forward then
        self.next_indication["pitch"] = actually_indication.pitch - self.pitch_speed
    elseif movement == Def.ActionList.Backward then
        self.next_indication["pitch"] = actually_indication.pitch + self.pitch_speed
    elseif movement == Def.ActionList.Right then
        self.next_indication["roll"] = actually_indication.roll + self.roll_speed
    elseif movement == Def.ActionList.Left then
        self.next_indication["roll"] = actually_indication.roll - self.roll_speed
    elseif movement == Def.ActionList.TurnRight then
        self.next_indication["yaw"] = actually_indication.yaw + self.yaw_speed
    elseif movement == Def.ActionList.TurnLeft then
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

function Engine:CalculatePower(movement)
    if movement == Def.ActionList.Down then
        self.log_obj:Record(LogLevel.Trace, "Change Power Off")
        self.clock = 0
        self.dynamic_lift_force = self.lift_force
        self.current_mode = Def.PowerMode.Off
        self.position_obj:SetEngineState(self.current_mode)
    elseif movement == Def.ActionList.Hold then
        self.log_obj:Record(LogLevel.Trace, "Change Power Hold")
        self.clock = 0
        self.dynamic_lift_force = self.lift_force
        self.current_mode = Def.PowerMode.Hold
    elseif movement == Def.ActionList.Up or self.current_mode == Def.PowerMode.On then
        if self.current_mode ~= Def.PowerMode.On then
            self.log_obj:Record(LogLevel.Trace, "Change Power On")
            self.clock = 0
            self.dynamic_lift_force = self.lift_force
            self.current_mode = Def.PowerMode.On
            self.position_obj:SetEngineState(self.current_mode)
        else
            self:SetPowerUpCurve(self.clock)
        end
    elseif movement == Def.ActionList.Hover or self.current_mode == Def.PowerMode.Hover then
        if self.current_mode ~= Def.PowerMode.Hover then
            self.log_obj:Record(LogLevel.Trace, "Change Power Hover")
            self.clock = 0
            self.dynamic_lift_force = self.lift_force
            self.current_mode = Def.PowerMode.Hover
        else
            self:SetPowerUpCurve(self.clock)
        end
    else
        self:SetPowerDownCurve(self.clock)
    end
end

function Engine:SetPowerUpCurve(time)
    if time <= self.time_to_max then
        self.lift_force = self.dynamic_lift_force + (self.max_lift_force - self.min_lift_force) * (time / self.time_to_max)
        if self.lift_force > self.max_lift_force then
            self.lift_force = self.max_lift_force
        end
    else
        self.lift_force = self.max_lift_force
    end
end

function Engine:SetPowerDownCurve(time)
    if time <= self.time_to_min then
        self.lift_force = self.dynamic_lift_force - (self.max_lift_force - self.min_lift_force) * (time / self.time_to_min)
        if self.lift_force < self.min_lift_force then
            self.lift_force = self.min_lift_force
        end
    else
        self.lift_force = self.min_lift_force
    end
end

function Engine:CalcureteVelocity()
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

    self.horizenal_x_speed = self.horizenal_x_speed + (DAV.time_resolution / self.mess) * (force_world.i - self.air_resistance_constant * self.horizenal_x_speed)
    self.horizenal_y_speed = self.horizenal_y_speed + (DAV.time_resolution / self.mess) * (force_world.j - self.air_resistance_constant * self.horizenal_y_speed)

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
end

return Engine
