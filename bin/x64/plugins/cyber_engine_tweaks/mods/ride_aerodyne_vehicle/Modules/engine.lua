local Log = require("Modules/log.lua")
Engine = {}
Engine.__index = Engine

Movement = {
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

function Engine:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Engine")

    -- set pyhsical parameters
    obj.roll_speed = 1
    obj.roll_back_speed = 0.1
    obj.pitch_speed = 1
    obj.pitch_back_speed = 0.1
    obj.yaw_speed = 1
    obj.yaw_back_speed = 0.1

    -- set default parameters
    obj.indicate = {roll = 0, pitch = 0, yaw = 0}

    return setmetatable(obj, self)
end

function Engine:CalcurateIndication(movement)
    if movement == Movement.Forward then
        self.indicate["pitch"] = self.indicate["pitch"] - self.pitch_speed
    elseif movement == Movement.Backward then
        self.indicate["pitch"] = self.indicate["pitch"] + self.pitch_speed
    elseif movement == Movement.Right then
        self.indicate["roll"] = self.indicate["roll"] + self.roll_speed
    elseif movement == Movement.Left then
        self.indicate["roll"] = self.indicate["roll"] - self.roll_speed
    elseif movement == Movement.TurnRight then
        self.indicate["yaw"] = self.indicate["yaw"] + self.yaw_speed
    elseif movement == Movement.TurnLeft then
        self.indicate["yaw"] = self.indicate["yaw"] - self.yaw_speed
    end

    if self.indicate["roll"] >= self.roll_back_speed then
        self.indicate["roll"] = self.indicate["roll"] - self.roll_back_speed
    elseif self.indicate["roll"] <= (-1 * self.roll_back_speed) then
        self.indicate["roll"] = self.indicate["roll"] + self.roll_back_speed
    elseif self.indicate["roll"] < self.roll_back_speed and self.indicate["roll"] > (-1 * self.roll_back_speed) then
        self.indicate["roll"] = 0
    end

    if self.indicate["pitch"] >= self.pitch_back_speed then
        self.indicate["pitch"] = self.indicate["pitch"] - self.pitch_back_speed
    elseif self.indicate["pitch"] <= (-1 * self.pitch_back_speed) then
        self.indicate["pitch"] = self.indicate["pitch"] + self.pitch_back_speed
    elseif self.indicate["pitch"] < self.pitch_back_speed and self.indicate["pitch"] > (-1 * self.pitch_back_speed) then
        self.indicate["pitch"] = 0
    end
    print(self.indicate["roll"] .. " " .. self.indicate["pitch"] .. " " .. self.indicate["yaw"])

    return self.indicate

end

return Engine