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
    obj.tpp_close_camera_distance = 7.5
    obj.tpp_close_camera_high = 1.5
    obj.tpp_medium_camera_distance = 12.0
    obj.tpp_medium_camera_high = 2.0
    obj.tpp_far_camera_distance = 15.0
    obj.tpp_far_camera_high = 2.5

    -- set default parameters
    obj.current_camera_mode = Def.CameraDistanceLevel.Fpp

    return setmetatable(obj, self)
end

function Camera:Init(av_obj)
    self.av_obj = av_obj
    local index = DAV.model_index
    local seat_number = DAV.seat_index

    self.x_offset = self.av_obj.all_models[index].seat_position[seat_number].x * -1
    self.y_offset = self.av_obj.all_models[index].seat_position[seat_number].y * -1
    self.yaw_offset = self.av_obj.all_models[index].seat_position[seat_number].yaw

end

function Camera:SetCameraPosition(level)
    local fpp_component = Game.GetPlayer():GetFPPCameraComponent()
    if level == Def.CameraDistanceLevel.Fpp then
        fpp_component:SetLocalPosition(Vector4.new(0.0, 0.0, 0.0, 1.0))
        fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, 0)))
        fpp_component.pitchMax = 80
        fpp_component.pitchMin = -80
        fpp_component.yawMaxRight = -360
        fpp_component.yawMaxLeft = 360
        fpp_component:ResetPitch()
        self.current_camera_mode = Def.CameraDistanceLevel.Fpp
    elseif level == Def.CameraDistanceLevel.TppClose then
        if self.yaw_offset == 0 then
            fpp_component:SetLocalPosition(Vector4.new(self.x_offset, (self.y_offset - self.tpp_close_camera_distance), self.tpp_close_camera_high, 1.0))
        elseif self.yaw_offset == 180 then
            fpp_component:SetLocalPosition(Vector4.new(-1 * self.x_offset, -1 * (self.y_offset - self.tpp_close_camera_distance), self.tpp_close_camera_high, 1.0))
        elseif self.yaw_offset == 90 then
            fpp_component:SetLocalPosition(Vector4.new(-1 *(self.y_offset + self.tpp_close_camera_distance), -1 * self.x_offset, self.tpp_close_camera_high, 1.0))
        elseif self.yaw_offset == -90 then
            fpp_component:SetLocalPosition(Vector4.new((self.y_offset + self.tpp_close_camera_distance), self.x_offset, self.tpp_close_camera_high, 1.0))
        end
        fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, -1 * self.yaw_offset)))
        fpp_component.pitchMax = 120
        fpp_component.pitchMin = -120
        fpp_component.yawMaxRight = -360
        fpp_component.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.TppClose
    elseif level == Def.CameraDistanceLevel.TppMedium then
        if self.yaw_offset == 0 then
            fpp_component:SetLocalPosition(Vector4.new(self.x_offset, (self.y_offset - self.tpp_medium_camera_distance), self.tpp_medium_camera_high, 1.0))
        elseif self.yaw_offset == 180 then
            fpp_component:SetLocalPosition(Vector4.new(-1 * self.x_offset, -1 * (self.y_offset - self.tpp_medium_camera_distance), self.tpp_medium_camera_high, 1.0))
        elseif self.yaw_offset == 90 then
            fpp_component:SetLocalPosition(Vector4.new(-1 *(self.y_offset + self.tpp_medium_camera_distance), -1 * self.x_offset, self.tpp_medium_camera_high, 1.0))
        elseif self.yaw_offset == -90 then
            fpp_component:SetLocalPosition(Vector4.new((self.y_offset + self.tpp_medium_camera_distance), self.x_offset, self.tpp_medium_camera_high, 1.0))
        end
        fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, -1 * self.yaw_offset)))
        fpp_component.pitchMax = 120
        fpp_component.pitchMin = -120
        fpp_component.yawMaxRight = -360
        fpp_component.yawMaxLeft = 360
        self.current_camera_mode = Def.CameraDistanceLevel.TppMedium
    elseif level == Def.CameraDistanceLevel.TppFar then
        if self.yaw_offset == 0 then
            fpp_component:SetLocalPosition(Vector4.new(self.x_offset, (self.y_offset - self.tpp_far_camera_distance), self.tpp_far_camera_high, 1.0))
        elseif self.yaw_offset == 180 then
            fpp_component:SetLocalPosition(Vector4.new(-1 * self.x_offset, -1 * (self.y_offset - self.tpp_far_camera_distance), self.tpp_far_camera_high, 1.0))
        elseif self.yaw_offset == 90 then
            fpp_component:SetLocalPosition(Vector4.new(-1 *(self.y_offset + self.tpp_far_camera_distance), -1 * self.x_offset, self.tpp_far_camera_high, 1.0))
        elseif self.yaw_offset == -90 then
            fpp_component:SetLocalPosition(Vector4.new((self.y_offset + self.tpp_far_camera_distance), self.x_offset, self.tpp_far_camera_high, 1.0))
        end
        fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, -1 * self.yaw_offset)))
        fpp_component.pitchMax = 120
        fpp_component.pitchMin = -120
        fpp_component.yawMaxRight = -360
        fpp_component.yawMaxLeft = 360
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