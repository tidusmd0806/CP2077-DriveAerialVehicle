local Log = require("Tools/log.lua")
local Camera = {}
Camera.__index = Camera

function Camera:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Camera")
    obj.av_obj = nil

    obj.x_offset = 0.0
    obj.yaw_offset = 0.0

    obj.fpp_component = nil

    -- set default parameters
    obj.current_camera_mode = Def.CameraDistanceLevel.Fpp

    return setmetatable(obj, self)
end

function Camera:Init(av_obj)
    self.av_obj = av_obj
    local index = self.av_obj.model_index
    local seat_number = self.av_obj.seat_index
    self.x_offset = -1 * self.av_obj.all_models[index].seat_position[seat_number].x
    self.yaw_offset = self.av_obj.all_models[index].seat_position[seat_number].yaw

    self.fpp_component = Game.GetPlayer():GetFPPCameraComponent()
end

function Camera:ChangePosition()
    self.fpp_component.pitchMax = self.pitchMax
    self.fpp_component.pitchMin = self.pitchMin
    self.fpp_component.yawMaxRight = self.yawMaxRight
    self.fpp_component.yawMaxLeft = self.yawMaxLeft
    self.fpp_component:SetLocalPosition(self.camera_vector)
    self.fpp_component:SetLocalOrientation(EulerAngles.ToQuat(self.camera_angle))

    -- local temp = vehicleCameraPerspective.TPPFar
    -- local event = vehicleRequestCameraPerspectiveEvent.new()
    -- event.cameraPerspective = temp
    -- Game.GetPlayer():QueueEvent(event)

    -- local tppCamera = GetPlayer():FindComponentByName('tppCamera')
    -- tppCamera:SetLocalPosition(self.camera_vector)
    -- tppCamera:SetLocalOrientation(EulerAngles.ToQuat(self.camera_angle))
    -- local tpp = ActivateTPPRepresentationEvent.new()
    -- tpp.playerController = Game.GetPlayer()
    -- GetPlayer():QueueEvent(tpp)
    -- tppCamera:Activate(2)
    -- local carCam = fpp_component:FindComponentByName(CName.new("vehicleTPPCamera"))
	-- carCam:Activate(2, true)
end

function Camera:SetCameraPosition(level)
    self.fpp_component = Game.GetPlayer():GetFPPCameraComponent()
    -- self.fpp_component.headingLocked = false
    if level == Def.CameraDistanceLevel.Fpp then
        self.fpp_component:SetLocalPosition(Vector4.new(0.0, 0.0, 0.0, 1.0))
        self.fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, 0)))
        self.fpp_component.pitchMax = 80
        self.fpp_component.pitchMin = -80
        self.fpp_component.yawMaxRight = -360
        self.fpp_component.yawMaxLeft = 360
        self.fpp_component:ResetPitch()
        self.current_camera_mode = Def.CameraDistanceLevel.Fpp
    elseif level == Def.CameraDistanceLevel.TppClose then
        self.fpp_component:SetLocalTransform(Vector4.new(0, 0, 0, 1.0), EulerAngles.ToQuat(EulerAngles.new(0, 0, 0)))
        self.fpp_component:SetLocalPosition(Vector4.new(self.x_offset, -7.5, 1.5, 1.0))
        self.fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, self.yaw_offset)))
        self.fpp_component.pitchMax = 80
        self.fpp_component.pitchMin = -80
        self.fpp_component.yawMaxRight = -360
        self.fpp_component.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.TppClose
    elseif level == Def.CameraDistanceLevel.TppMedium then
        self.fpp_component:SetLocalPosition(Vector4.new(self.x_offset, -10.0, 2.0, 1.0))
        self.fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, self.yaw_offset)))
        self.fpp_component.pitchMax = 80
        self.fpp_component.pitchMin = -80
        self.fpp_component.yawMaxRight = -360
        self.fpp_component.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.TppMedium
    elseif level == Def.CameraDistanceLevel.TppFar then
        self.fpp_component:SetLocalPosition(Vector4.new(self.x_offset, -15.0, 2.8, 1.0))
        self.fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, self.yaw_offset)))
        self.fpp_component.pitchMax = 80
        self.fpp_component.pitchMin = -80
        self.fpp_component.yawMaxRight = -360
        self.fpp_component.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.TppFar
    end
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