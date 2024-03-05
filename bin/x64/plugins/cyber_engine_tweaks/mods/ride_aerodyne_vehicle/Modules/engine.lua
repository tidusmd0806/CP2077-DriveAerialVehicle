local Log = require("Modules/log.lua")
local Utils = require("Modules/utils.lua")
Engine = {}
Engine.__index = Engine

Movement = {
    Nothing = 0,
    Up = 1,
    Down = 2,
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
    obj.roll_restore_speed = 0.05
    obj.pitch_restore_speed = 0.05
    obj.max_roll = 30
    obj.min_roll = -30
    obj.max_pitch = 30
    obj.min_pitch = -30

    obj.mess = 2000
    obj.gravity_constant = 9.8
    obj.air_resistance_constant = 100
    obj.max_lift_force = 20000
    obj.min_lift_force = obj.mess * obj.gravity_constant - 50
    obj.lift_force = obj.min_lift_force
    obj.time_to_max = 5
    obj.time_to_min = 5

    -- set default parameters
    obj.next_indication = {roll = 0, pitch = 0, yaw = 0}
    obj.base_angle = nil
    obj.is_finished_init = false
    obj.is_power_on = false
    obj.is_hover = false
    obj.horizenal_x_speed = 0
    obj.horizenal_y_speed = 0
    obj.vertical_speed = 0
    obj.clock = 0

    return setmetatable(obj, self)
end

function Engine:Init()
    if not self.is_finished_init then
        RAV.Cron.Every(1, {tick = 1}, function(timer)
            self.clock = self.clock + 1
        end)
    end
    self.base_angle = self.position_obj:GetEulerAngles()
    self.is_finished_init = true
    self.is_power_on = false
    self.is_hover = false
    self.horizenal_x_speed = 0
    self.horizenal_y_speed = 0
    self.vertical_speed = 0
    self.clock = 0
    self.clock_tmp_store = 0
end

function Engine:GetNextPosition(movement)

    local roll, pitch, yaw = self:CalcurateIndication(movement)
    local x, y, z = self:CalcureteVelocity(movement)

    return x, y, z, roll, pitch, yaw
end

function Engine:CalcurateIndication(movement)

    if not self.is_finished_init then
        return 0, 0, 0
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
    local roll = self.next_indication["roll"] - actually_indication.roll
    local pitch = self.next_indication["pitch"] - actually_indication.pitch
    local yaw = self.next_indication["yaw"] - actually_indication.yaw

    return roll, pitch, yaw

end

function Engine:CalcureteVelocity(movement)
    local foword_vector = self.position_obj:GetFoword()
    local angle = self.position_obj:GetEulerAngles()
    -- Normalizing the direction vector
    local norm = math.sqrt(foword_vector.x * foword_vector.x + foword_vector.y * foword_vector.y)
    local unit_vector_x = foword_vector.x / norm
    local unit_vector_y = foword_vector.y / norm

    -- Calcurate power
    self:CalcuratePower(movement)

    self.horizenal_x_speed = self.horizenal_x_speed + (RAV.time_resolution / self.mess) * (self.lift_power * math.sin(angle.pitch) * unit_vector_x - self.air_resistance_constant * self.horizenal_x_speed)
    self.horizenal_y_speed = self.horizenal_y_speed + (RAV.time_resolution / self.mess) * (self.lift_power * math.sin(angle.roll) * unit_vector_y - self.air_resistance_constant * self.horizenal_y_speed)
    self.vertical_speed = self.vertical_speed + (RAV.time_resolution / self.mess) * (self.lift_power * math.sqrt( math.cos(angle.pitch) * math.cos(angle.pitch) * unit_vector_x * unit_vector_x + math.cos(angle.roll) * math.cos(angle.roll) * unit_vector_y * unit_vector_y) / norm - self.mess * self.gravity_constant - self.air_resistance_constant * self.vertical_speed)
    self.SetState(movement)

    return self.horizenal_x_speed * RAV.time_resolution, self.horizenal_y_speed * RAV.time_resolution, self.vertical_speed * RAV.time_resolution
end

function Engine:CalcuratePower(movement)
    if movement == Movement.Up or self.is_power_on then
        if not self.is_power_on then
            self.clock = 0
            self.clock_tmp_store = self.clock     
        end
        self:SetPowerUpCurve(self.clock - self.clock_tmp_store)
        self.clock_tmp_store = self.clock

    elseif movement == Movement.Down or not self.is_power_on then
        if self.is_power_on then
            self.clock = 0
            self.clock_tmp_store = self.clock
        end
        self:SetPowerDownCurve(self.clock_tmp_store - self.clock)
        self.clock_tmp_store = self.clock
    end
end

function Engine:SetPowerUpCurve(time)
    if time < self.time_to_max then
        self.lift_power = self.lift_force + (self.max_lift_force - self.min_lift_force) * (time / self.time_to_max)
        if self.lift_power > self.max_lift_force then
            self.lift_power = self.max_lift_force
        end
    else
        self.lift_power = self.max_lift_force
    end
end

function Engine:SetPowerDownCurve(time)
    if time < self.time_to_min then
        self.lift_power = self.lift_force - (self.max_lift_force - self.min_lift_force) * (time / self.time_to_min)
        if self.lift_power < self.min_lift_force then
            self.lift_power = self.min_lift_force
        end
    else
        self.lift_power = self.min_lift_force
    end
end

function Engine:SetState(movement)
    if movement == Movement.Up then
        self.is_power_on = true
        self.is_hover = false
    elseif movement == Movement.Down then
        self.is_power_on = false
    elseif movement == Movement.Hover then
        self.is_hover = true
    end

end

return Engine