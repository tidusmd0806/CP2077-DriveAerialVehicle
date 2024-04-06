local Def = require("Tools/def.lua")
local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Camera = {}
Camera.__index = Camera

function Camera:New(position_obj, all_models)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Camera")
    obj.position_obj = position_obj
    obj.all_models = all_models

    obj.free_camera_ent_path = "base\\entities\\cameras\\simple_free_camera.ent"
    obj.camera_theta_speed = 0.7
    obj.camera_phi_speed = 0.7

    local camera_distance_ratio = all_models[DAV.model_index].camera_distance_ratio or 1.0
    obj.camera_distance_seat_offset = -0.1
    obj.camera_z_seat_offset = 1.3
    obj.camera_distance_close = 7.5 * camera_distance_ratio
    obj.camera_initial_theta_close = 0
    obj.camera_initial_phi_close = 15
    obj.camera_distance_medium = 12.0 * camera_distance_ratio
    obj.camera_initial_theta_medium = 0
    obj.camera_initial_phi_medium = 10
    obj.camera_distance_far = 15.0 * camera_distance_ratio
    obj.camera_initial_theta_far = 0
    obj.camera_initial_phi_far = 5

    -- set default parameters
    obj.current_camera_mode = Def.CameraDistanceLevel.Fpp
    obj.cam_entity = nil
    obj.fpp_component = nil
    obj.tpp_component = nil
    obj.is_active = true
    obj.cam_distance = 1
    obj.cam_theta = 0
    obj.cam_phi = 0

    obj.is_reverse_camera = false

    return setmetatable(obj, self)
end

function Camera:Create()

    self.fpp_component = Game.GetPlayer():GetFPPCameraComponent()

    local position = self.position_obj:GetPosition()
    position.z = position.z + 100.0
    local angle = self.position_obj:GetForward():ToRotation()

    local cam_transform = WorldTransform.new()
    cam_transform:SetPosition(position)
    cam_transform:SetOrientationEuler(angle)

    local cam_entity_id = exEntitySpawner.Spawn(self.free_camera_ent_path, cam_transform, '')

    DAV.Cron.Every(0.01, {tick = 1}, function(timer)
        self.cam_entity = Game.FindEntityByID(cam_entity_id)
        if self.cam_entity ~= nil then
            self.tpp_component = self.cam_entity:FindComponentByName("camera")
            DAV.Cron.Halt(timer)
        end
    end)

end

function Camera:Move()
    if self.cam_entity == nil then
        self.log_obj:Record(LogLevel.Debug, "Camera component is nil")
        return
    end

    local center_position = self.position_obj:GetPosition()
    local forward = self.position_obj:GetForward()
    local center_angle = forward:ToRotation()

    local base_theta = (center_angle.yaw - 90 + self.cam_theta) * Pi() / 180.0
    local cam_position = Vector4.new(center_position.x + self.cam_distance * math.cos(base_theta) * math.cos(self.cam_phi * Pi() / 180.0), center_position.y + self.cam_distance * math.sin(base_theta) * math.cos(self.cam_phi * Pi() / 180.0), center_position.z + self.cam_distance * math.sin(self.cam_phi * Pi() / 180.0), 1.0)
    local angle_dir = Vector4.new(center_position.x - cam_position.x, center_position.y - cam_position.y, cam_position.z - center_position.z, 1.0)

    if self.is_reverse_camera then
        angle_dir = Vector4.new(angle_dir.x * -1, angle_dir.y * -1, angle_dir.z * -1, 1.0)
    end

    Game.GetTeleportationFacility():Teleport(self.cam_entity, cam_position, angle_dir:ToRotation())

end

function Camera:SetLocalPosition(action)
    if self.cam_entity == nil then
        self.log_obj:Record(LogLevel.Debug, "Camera component is nil")
        return
    end

    if action == Def.ActionList.CamUp then
        self.cam_phi = self.cam_phi - self.camera_phi_speed
    elseif action == Def.ActionList.CamDown then
        self.cam_phi = self.cam_phi + self.camera_phi_speed
    elseif action == Def.ActionList.CamLeft then
        self.cam_theta = self.cam_theta + self.camera_theta_speed
    elseif action == Def.ActionList.CamRight then
        self.cam_theta = self.cam_theta - self.camera_theta_speed
    end

    if self.cam_phi > 80 then
        self.cam_phi = 80
    elseif self.cam_phi < -80 then
        self.cam_phi = -80
    end
end

-- function Camera:ChangePosition(level)

--     self.is_reverse_camera = false

--     if level == Def.CameraDistanceLevel.TppSeat then
--         local x = self.all_models[DAV.model_index].seat_position[DAV.seat_index].y * -1
--         local y = self.all_models[DAV.model_index].seat_position[DAV.seat_index].x
--         local z = self.all_models[DAV.model_index].seat_position[DAV.seat_index].z + self.camera_z_seat_offset
--         local yaw = self.all_models[DAV.model_index].seat_position[DAV.seat_index].yaw

--         local reverse_sign = 1

--         if yaw == 0 and self.all_models[DAV.model_index].seat_position[DAV.seat_index].y > 0 then
--             self.is_reverse_camera = true
--             reverse_sign = -1
--         elseif yaw == 180 and self.all_models[DAV.model_index].seat_position[DAV.seat_index].y < 0 then
--             self.is_reverse_camera = true
--             reverse_sign = -1
--         elseif yaw == 90 and self.all_models[DAV.model_index].seat_position[DAV.seat_index].x < 0 then
--             self.is_reverse_camera = true
--             reverse_sign = -1
--         elseif yaw == -90 and self.all_models[DAV.model_index].seat_position[DAV.seat_index].x > 0 then
--             self.is_reverse_camera = true
--             reverse_sign = -1
--         end

--         local r, theta, phi = Utils:ChangePolarCoordinates(x, y, z)
--         self.cam_distance = r + self.camera_distance_seat_offset * reverse_sign
--         self.cam_theta = theta
--         self.cam_phi = 90 - phi

--         self.tpp_component:Activate(0, false)
--         self.current_camera_mode = Def.CameraDistanceLevel.TppSeat
--     elseif level == Def.CameraDistanceLevel.Fpp then
--         self.fpp_component:SetLocalPosition(Vector4.new(0.0, 0.0, 0.0, 1.0))
--         self.fpp_component:SetLocalOrientation(EulerAngles.ToQuat(EulerAngles.new(0, 0, 0)))
--         self.fpp_component.pitchMax = 80
--         self.fpp_component.pitchMin = -80
--         self.fpp_component.yawMaxRight = -360
--         self.fpp_component.yawMaxLeft = 360
--         self.fpp_component:ResetPitch()
--         self.fpp_component:Activate(0, false)
--         self.current_camera_mode = Def.CameraDistanceLevel.Fpp
--     elseif level == Def.CameraDistanceLevel.TppClose then
--         self.cam_distance = self.camera_distance_close
--         self.cam_theta = self.camera_initial_theta_close
--         self.cam_phi = self.camera_initial_phi_close
--         self.tpp_component:Activate(0, false)
--         self.current_camera_mode = Def.CameraDistanceLevel.TppClose
--     elseif level == Def.CameraDistanceLevel.TppMedium then
--         self.cam_distance = self.camera_distance_medium
--         self.cam_theta = self.camera_initial_theta_medium
--         self.cam_phi = self.camera_initial_phi_medium
--         self.tpp_component:Activate(0, false)
--         self.current_camera_mode = Def.CameraDistanceLevel.TppMedium
--     elseif level == Def.CameraDistanceLevel.TppFar then
--         self.cam_distance = self.camera_distance_far
--         self.cam_theta = self.camera_initial_theta_far
--         self.cam_phi = self.camera_initial_phi_far
--         self.tpp_component:Activate(0, false)
--         self.current_camera_mode = Def.CameraDistanceLevel.TppFar
--     end
-- end

function Camera:ChangePosition(level)

    local camera_perspective = vehicleRequestCameraPerspectiveEvent.new()

    -- if level == Def.CameraDistanceLevel.TppSeat then
    --     camera_perspective.cameraPerspective = vehicleCameraPerspective.FPP
    if level == Def.CameraDistanceLevel.Fpp then
		self.log_obj:Record(LogLevel.Trace, "Change Camera : FPP")
        camera_perspective.cameraPerspective = vehicleCameraPerspective.FPP
    elseif level == Def.CameraDistanceLevel.TppClose then
		self.log_obj:Record(LogLevel.Trace, "Change Camera : TPPClose")
        camera_perspective.cameraPerspective = vehicleCameraPerspective.TPPClose
    elseif level == Def.CameraDistanceLevel.TppMedium then
		self.log_obj:Record(LogLevel.Trace, "Change Camera : TPPMedium")
        camera_perspective.cameraPerspective = vehicleCameraPerspective.TPPMedium
    elseif level == Def.CameraDistanceLevel.TppFar then
		self.log_obj:Record(LogLevel.Trace, "Change Camera : TPPFar")
        camera_perspective.cameraPerspective = vehicleCameraPerspective.TPPFar
    end
    Game.GetPlayer():QueueEvent(camera_perspective)

end

function Camera:Toggle()
    if self.current_camera_mode ~= Def.CameraDistanceLevel.TppFar then
        self.current_camera_mode = self.current_camera_mode + 1
    elseif self.current_camera_mode == Def.CameraDistanceLevel.TppFar then
        self.current_camera_mode = Def.CameraDistanceLevel.Fpp
    end
    self:ChangePosition(self.current_camera_mode)
    return self.current_camera_mode
end

return Camera