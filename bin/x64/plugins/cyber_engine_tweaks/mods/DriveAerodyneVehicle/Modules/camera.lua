local Log = require("Tools/log.lua")
local Camera = {}
Camera.__index = Camera

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
    obj.current_camera_mode = Def.CameraDistanceLevel.Fpp

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
    if level == Def.CameraDistanceLevel.Fpp then
        self.camera_vector = Vector4.new(0.0, 0.0, 0.0, 1.0)
        self.pitchMax = 80
        self.pitchMin = -80
        self.yawMaxRight = -360
        self.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.Fpp
    elseif level == Def.CameraDistanceLevel.TppClose then
        self.camera_vector = Vector4.new(0.0, -7.5, 1.5, 1.0)
        self.pitchMax = 80
        self.pitchMin = -80
        self.yawMaxRight = -360
        self.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.TppClose
    elseif level == Def.CameraDistanceLevel.TppMedium then
        self.camera_vector = Vector4.new(0.0, -10.0, 2.0, 1.0)
        self.pitchMax = 80
        self.pitchMin = -80
        self.yawMaxRight = -360
        self.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.TppMedium
    elseif level == Def.CameraDistanceLevel.TppFar then
        self.camera_vector = Vector4.new(0.0, -12.5, 2.5, 1.0)
        self.pitchMax = 80
        self.pitchMin = -80
        self.yawMaxRight = -360
        self.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.TppFar
    end
    self:ChangePosition()
end

function Camera:ToggleCameraPosition()
    if self.current_camera_mode ~= Def.CameraDistanceLevel.TppFar then
        self.current_camera_mode = self.current_camera_mode + 1
    elseif self.current_camera_mode == Def.CameraDistanceLevel.TppFar then
        self.current_camera_mode = Def.CameraDistanceLevel.Fpp
    end
    self:SetCameraPosition(self.current_camera_mode)
    return self.current_camera_mode
end

return Camera