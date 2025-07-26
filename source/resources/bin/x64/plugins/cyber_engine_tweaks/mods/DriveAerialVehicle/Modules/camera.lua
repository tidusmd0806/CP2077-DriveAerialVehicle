local Camera = {}
Camera.__index = Camera

--- Constractor
---@param all_models table all models data
---@return table
function Camera:New(all_models)
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Camera")
    obj.all_models = all_models

    -- static --
    obj.default_high_close_distance = 5.0
    obj.default_high_close_distance_offset = 0.0
    obj.high_close_center_offset = {x = 0.0, y = 0.5, z = 1.5}
    obj.high_driver_combat_close_center_offset = {x = 0.0, y = 0.5, z = 1.8}
    obj.default_high_medium_distance = 5.0
    obj.default_high_medium_distance_offset = 1.75
    obj.high_medium_center_offset = {x = 0.0, y = 0.5, z = 1.5}
    obj.high_driver_combat_medium_center_offset = {x = 0.0, y = 0.5, z = 1.8}
    obj.default_high_far_distance = 5.0
    obj.default_high_far_distance_offset = 4.0
    obj.high_far_center_offset = {x = 0.0, y = 0.5, z = 1.5}
    obj.high_driver_combat_far_center_offset = {x = 0.0, y = 0.5, z = 1.8}
    obj.default_low_close_distance = 5.0
    obj.default_low_close_distance_offset = 0.0
    obj.low_close_center_offset = {x = 0.0, y = 0.5, z = 1.5}
    obj.low_driver_combat_close_center_offset = {x = 0.0, y = 0.5, z = 1.8}
    obj.default_low_medium_distance = 5.0
    obj.default_low_medium_distance_offset = 1.75
    obj.low_medium_center_offset = {x = 0.0, y = 0.5, z = 1.5}
    obj.low_driver_combat_medium_center_offset = {x = 0.0, y = 0.5, z = 1.8}
    obj.default_low_far_distance = 5.0
    obj.default_low_far_distance_offset = 4.0
    obj.low_far_center_offset = {x = 0.0, y = 0.5, z = 1.5}
    obj.low_driver_combat_far_center_offset = {x = 0.0, y = 0.5, z = 1.8}
    -- dynamic --
    -- set default parameters
    obj.current_camera_mode = Def.CameraDistanceLevel.Fpp
    obj.enable_fpp = true
    obj.camera_distance_ratio = {}
    obj.camera_center_offset = {}

    return setmetatable(obj, self)

end

--- Initialize
function Camera:Init()
	local index = DAV.model_index
    self.enable_fpp = self.all_models[index].fpp_camera
    self.camera_distance_ratio = self.all_models[index].camera_distance_ratio
    self.camera_center_offset = self.all_models[index].camera_center_offset
end

--- Set camera parameters
---@param seat_index number mounted seat index
function Camera:SetPerspective(seat_index)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close_DAV.baseBoomLength"), self.default_high_close_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close_DAV.boomLengthOffset"), self.default_high_close_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close_DAV.baseBoomLength"), self.default_low_close_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close_DAV.boomLengthOffset"), self.default_low_close_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium_DAV.baseBoomLength"), self.default_high_medium_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium_DAV.boomLengthOffset"), self.default_high_medium_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium_DAV.baseBoomLength"), self.default_low_medium_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium_DAV.boomLengthOffset"), self.default_low_medium_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far_DAV.baseBoomLength"), self.default_high_far_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far_DAV.boomLengthOffset"), self.default_high_far_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far_DAV.baseBoomLength"), self.default_low_far_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far_DAV.boomLengthOffset"), self.default_low_far_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose_DAV.baseBoomLength"), self.default_high_close_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose_DAV.boomLengthOffset"), self.default_high_close_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose_DAV.baseBoomLength"), self.default_low_close_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose_DAV.boomLengthOffset"), self.default_low_close_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium_DAV.baseBoomLength"), self.default_high_medium_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium_DAV.boomLengthOffset"), self.default_high_medium_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium_DAV.baseBoomLength"), self.default_low_medium_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium_DAV.boomLengthOffset"), self.default_low_medium_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar_DAV.baseBoomLength"), self.default_high_far_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar_DAV.boomLengthOffset"), self.default_high_far_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar_DAV.baseBoomLength"), self.default_low_far_distance * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar_DAV.boomLengthOffset"), self.default_low_far_distance_offset * self.camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar_DAV.lookAtOffset"), Vector3.new(self.camera_center_offset[seat_index].x, self.camera_center_offset[seat_index].y, self.camera_center_offset[seat_index].z))
    if not self.enable_fpp and self.current_camera_mode == Def.CameraDistanceLevel.Fpp then
        self.current_camera_mode = Def.CameraDistanceLevel.TppClose
        self:ChangePosition(self.current_camera_mode)
    end
end

--- Change camera perspective
---@param level number camera distance level
function Camera:ChangePosition(level)
    local camera_perspective = vehicleRequestCameraPerspectiveEvent.new()

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

    self.current_camera_mode = level

    Game.GetPlayer():QueueEvent(camera_perspective)
end

--- Toggle camera perspective
--- @return number current camera distance level
function Camera:Toggle()
    local veh_camera_perspective = Game.GetPlayer():FindVehicleCameraManager():GetActivePerspective()
    if veh_camera_perspective == vehicleCameraPerspective.FPP then
        self.current_camera_mode = Def.CameraDistanceLevel.TppClose
    elseif veh_camera_perspective == vehicleCameraPerspective.TPPClose or veh_camera_perspective == vehicleCameraPerspective.DriverCombatClose then
        self.current_camera_mode = Def.CameraDistanceLevel.TppMedium
    elseif veh_camera_perspective == vehicleCameraPerspective.TPPMedium or veh_camera_perspective == vehicleCameraPerspective.DriverCombatMedium then
        self.current_camera_mode = Def.CameraDistanceLevel.TppFar
    elseif veh_camera_perspective == vehicleCameraPerspective.TPPFar or veh_camera_perspective == vehicleCameraPerspective.DriverCombatFar then
        if self.enable_fpp then
            self.current_camera_mode = Def.CameraDistanceLevel.Fpp
        else
            self.current_camera_mode = Def.CameraDistanceLevel.TppClose
        end
    end
    self:ChangePosition(self.current_camera_mode)
    return self.current_camera_mode
end

return Camera