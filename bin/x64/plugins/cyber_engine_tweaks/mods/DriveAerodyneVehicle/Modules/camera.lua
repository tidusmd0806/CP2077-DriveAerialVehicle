local Log = require("Tools/log.lua")
local Camera = {}
Camera.__index = Camera

CameraDistanceLevel = {
    Fpp = 0,
    TppClose = 1,
    TppMedium = 2,
    TppFar = 3

}

function Camera:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Camera")

    obj.camera_vector = nil
    obj.pitchMax = 80
    obj.pitchMin = -80
    obj.yawMaxRight = -360
    obj.yawMaxLeft = 360

    -- set default parameters
    obj.current_camera_mode = CameraDistanceLevel.Fpp

    return setmetatable(obj, self)
end

function Camera:ChangePosition()
    local fpp_component = Game.GetPlayer():GetFPPCameraComponent()
    fpp_component.pitchMax = self.pitchMax
    fpp_component.pitchMin = self.pitchMin
    fpp_component.yawMaxRight = self.yawMaxRight
    fpp_component.yawMaxLeft = self.yawMaxLeft
    fpp_component:SetLocalPosition(self.camera_vector)
    fpp_component:ResetPitch()
end

function Camera:SetCameraPosition(level)
    if level == CameraDistanceLevel.Fpp then
        self.camera_vector = Vector4.new(0.0, 0.0, 0.0, 1.0)
        self.pitchMax = 80
        self.pitchMin = -80
        self.yawMaxRight = -360
        self.yawMaxLeft = 360
        self.current_camera_mode = CameraDistanceLevel.Fpp
    elseif level == CameraDistanceLevel.TppClose then
        self.camera_vector = Vector4.new(0.0, -7.5, 1.5, 1.0)
        self.pitchMax = 80
        self.pitchMin = -80
        self.yawMaxRight = -360
        self.yawMaxLeft = 360
        self.current_camera_mode = CameraDistanceLevel.TppClose
    elseif level == CameraDistanceLevel.TppMedium then
        self.camera_vector = Vector4.new(0.0, -15.0, 2.5, 1.0)
        self.pitchMax = 80
        self.pitchMin = -80
        self.yawMaxRight = -360
        self.yawMaxLeft = 360
        self.current_camera_mode = CameraDistanceLevel.TppMedium
    elseif level == CameraDistanceLevel.TppFar then
        self.camera_vector = Vector4.new(0.0, -20.0, 3.0, 1.0)
        self.pitchMax = 80
        self.pitchMin = -80
        self.yawMaxRight = -360
        self.yawMaxLeft = 360
        self.current_camera_mode = CameraDistanceLevel.TppFar
    end
    self:ChangePosition()
end

return Camera