local Log = require("Modules/log.lua")
local Camera = {}
Camera.__index = Camera

function Camera:new()
    local obj = {}
    obj.log_obj = Log:new()
    obj.log_obj:setLevel(LogLevel.INFO, "Camera")

    return setmetatable(obj, self)
end

function Camera:setPosition()
    local fpp_comp = Game.GetPlayer():GetFPPCameraComponent()
    fpp_comp:SetLocalPosition(self.camera_vector)
    fpp_comp.pitchMax = self.pitchMax
    fpp_comp.pitchMin = self.pitchMin
    fpp_comp.yawMaxRight = self.yawMaxRight
    fpp_comp.yawMaxLeft = self.yawMaxLeft
end

function Camera:setDefaultPosition()
    self.target = Game.GetPlayer()
    self.camera_vector = Vector4.new(0, 0, 0, 1.0)
    self.pitchMax = 80
    self.pitchMin = -80
    self.yawMaxRight = -360
    self.yawMaxLeft = 360
    self:setPosition()
end

function Camera:setVehiclePosition()
    self.target = Game.GetPlayer()
    self.camera_vector = Vector4.new(0, -10, 2.0, 0)
    self.pitchMax = 80
    self.pitchMin = -80
    self.yawMaxRight = -360
    self.yawMaxLeft = 360
    self:setPosition()
end

return Camera