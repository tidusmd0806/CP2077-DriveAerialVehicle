local Log = require("Modules/log.lua")
Engine = {}
Engine.__index = Engine

Movement = {
    Nothing = 0,
    Up = 1,
    Stop = 2,
    Forward = 3,
    Backward = 4,
    Right = 5,
    Left = 6,
    TurnRight = 7,
    TurnLeft = 8,
    Hover = 9
}

function Engine:New(position_obj)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Engine")
    obj.position_obj = position_obj

    -- set pyhsical parameters
    obj.roll_speed = 1
    obj.pitch_speed = 1
    obj.yaw_speed = 1
    obj.roll_restore_speed = 0.5
    obj.pitch_restore_speed = 0.5
    obj.max_roll = 30
    obj.min_roll = -30
    obj.max_pitch = 30
    obj.min_pitch = -30
    obj.lift_force = 0.08
    obj.horizontal_auxiliary_rate = 3
    obj.air_resistance_constant = 0.1
    obj.gravity_constant_times_delta_time = 0.05

    -- set default parameters
    obj.next_indication = {roll = 0, pitch = 0, yaw = 0}
    obj.base_angle = nil
    obj.is_finished_init = false
    obj.is_power_on = false
    obj.is_hover = false
    obj.horizenal_x_speed = 0
    obj.horizenal_y_speed = 0
    obj.vertical_speed = 0

    return setmetatable(obj, self)
end

function Engine:Init()
    self.base_angle = self.position_obj:GetEulerAngles()
    self.is_finished_init = true
    self.is_power_on = false
    self.is_hover = false
    self.horizenal_x_speed = 0
    self.horizenal_y_speed = 0
    self.vertical_speed = 0
end

function Engine:CalcurateIndication(movement)


    if not self.is_finished_init then
        return {roll = 0, pitch = 0, yaw = 0}
    end

    local actually_indication = self.position_obj:GetEulerAngles()
    self.next_indication["roll"] = actually_indication.roll
    self.next_indication["pitch"] = actually_indication.pitch
    self.next_indication["yaw"] = actually_indication.yaw
    -- set indication
    if movement == Movement.Forward then
        self.next_indication["pitch"] = actually_indication.pitch - self.pitch_speed
    elseif movement == Movement.Backward then
        self.next_indication["pitch"] = actually_indication.pitch + self.pitch_speed
    elseif movement == Movement.Right then
        self.next_indication["roll"] = actually_indication.roll + self.roll_speed
    elseif movement == Movement.Left then
        self.next_indication["roll"] = actually_indication.roll - self.roll_speed
    elseif movement == Movement.TurnRight then
        self.next_indication["yaw"] = actually_indication.yaw + self.yaw_speed
    elseif movement == Movement.TurnLeft then
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
    local delta = {
        roll = self.next_indication["roll"] - actually_indication.roll,
        pitch = self.next_indication["pitch"] - actually_indication.pitch,
        yaw = self.next_indication["yaw"] - actually_indication.yaw
    }

    return delta

end

function Engine:CalcurateHorizenalMovement(movement)
    local foword_vector = self.position_obj:GetFoword()
    local angle = self.position_obj:GetEulerAngles()
    local x_y_vector_norm = math.sqrt(foword_vector.x * foword_vector.x + foword_vector.y * foword_vector.y)
    if movement == Movement.Up or self.is_power_on then
        self.horizenal_x_speed = self.horizenal_x_speed + self.lift_force * math.sin(angle.pitch) * (foword_vector.x / x_y_vector_norm) * self.horizontal_auxiliary_rate
        self.horizenal_y_speed = self.horizenal_y_speed + self.lift_force * math.sin(angle.roll) * (foword_vector.y / x_y_vector_norm) * self.horizontal_auxiliary_rate
        self.log_obj:Record(LogLevel.Debug, "Up Engine" .. "Current Horizenal Speed X :" .. self.horizenal_x_speed .. " Y :" .. self.horizenal_y_speed)
    end

    if self.horizenal_x_speed > 0 then
        self.horizenal_x_speed = self.horizenal_x_speed - self.air_resistance_constant * math.abs(self.horizenal_x_speed)
    elseif self.horizenal_x_speed < 0 then
        self.horizenal_x_speed = self.horizenal_x_speed + self.air_resistance_constant * math.abs(self.horizenal_x_speed)
    end
    if self.horizenal_y_speed > 0 then
        self.horizenal_y_speed = self.horizenal_y_speed - self.air_resistance_constant * math.abs(self.horizenal_y_speed)
    elseif self.horizenal_y_speed < 0 then
        self.horizenal_y_speed = self.horizenal_y_speed + self.air_resistance_constant * math.abs(self.horizenal_y_speed)
    end

    return self.horizenal_x_speed, self.horizenal_y_speed
end

function Engine:CalcurateVerticalMovement(movement)
    local foword_vector = self.position_obj:GetFoword()
    local x_y_vector_norm = math.sqrt(foword_vector.x * foword_vector.x + foword_vector.y * foword_vector.y)
    local angle = self.position_obj:GetEulerAngles()

    if movement == Movement.Stop then
        self.vertical_speed = self.vertical_speed - self.gravity_constant_times_delta_time + self.air_resistance_constant * math.abs(self.vertical_speed)
        self.log_obj:Record(LogLevel.Debug, "Stop Engine" .. "Current Vertical Speed :" .. self.vertical_speed)
        return self.vertical_speed
    elseif movement == Movement.Up or self.is_power_on then
        self.vertical_speed = self.vertical_speed + self.lift_force * (math.cos(angle.pitch) * (foword_vector.x / x_y_vector_norm) +
                                (math.cos(angle.roll) * (foword_vector.y / x_y_vector_norm))) - self.gravity_constant_times_delta_time
        if self.vertical_speed > 0 then
            self.vertical_speed = self.vertical_speed - self.air_resistance_constant * math.abs(self.vertical_speed)
        elseif self.vertical_speed < 0 then
            self.vertical_speed = self.vertical_speed + self.air_resistance_constant * math.abs(self.vertical_speed)
        end
        if not self.is_power_on then
            self.log_obj:Record(LogLevel.Debug, "Start Engine" .. "Current Vertical Speed :" .. self.vertical_speed)
        end
        return self.vertical_speed
    elseif movement == Movement.Hover then
        self.vertical_speed = 0
        self.log_obj:Record(LogLevel.Debug, "Hover Engine" .. "Current Vertical Speed :" .. self.vertical_speed)
        return self.vertical_speed
    elseif not self.is_hover then
        -- free fall
        self.vertical_speed = self.vertical_speed - self.gravity_constant_times_delta_time + self.air_resistance_constant * math.abs(self.vertical_speed)
        return self.vertical_speed
    end

end

function Engine:SetState(movement)
    if movement == Movement.Up then
        self.is_power_on = true
    elseif movement == Movement.Stop then
        self.is_power_on = false
    end

    if movement == Movement.Hover then
        self.is_hover = true
    elseif movement == Movement.Up then
        self.is_hover = false
    end

end

return Engine