local Utils = require("Tools/utils.lua")
local Camera = {}
Camera.__index = Camera

--- Constractor
---@param position_obj any Position instance
---@param all_models table all models data
---@return table
function Camera:New(position_obj, all_models)
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Camera")
    obj.position_obj = position_obj
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

    return setmetatable(obj, self)

end

--- Set camera parameters
---@param seat_index number mounted seat index
function Camera:SetPerspective(seat_index)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close.baseBoomLength"), self.default_high_close_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close.boomLengthOffset"), self.default_high_close_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close.baseBoomLength"), self.default_low_close_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close.boomLengthOffset"), self.default_low_close_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium.baseBoomLength"), self.default_high_medium_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium.boomLengthOffset"), self.default_high_medium_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium.baseBoomLength"), self.default_low_medium_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium.boomLengthOffset"), self.default_low_medium_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far.baseBoomLength"), self.default_high_far_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far.boomLengthOffset"), self.default_high_far_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far.baseBoomLength"), self.default_low_far_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far.boomLengthOffset"), self.default_low_far_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose.baseBoomLength"), self.default_high_close_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose.boomLengthOffset"), self.default_high_close_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose.baseBoomLength"), self.default_low_close_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose.boomLengthOffset"), self.default_low_close_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium.baseBoomLength"), self.default_high_medium_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium.boomLengthOffset"), self.default_high_medium_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium.baseBoomLength"), self.default_low_medium_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium.boomLengthOffset"), self.default_low_medium_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar.baseBoomLength"), self.default_high_far_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar.boomLengthOffset"), self.default_high_far_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar.baseBoomLength"), self.default_low_far_distance * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar.boomLengthOffset"), self.default_low_far_distance_offset * self.all_models[DAV.model_index].camera_distance_ratio[seat_index])
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar.lookAtOffset"), Vector3.new(self.all_models[DAV.model_index].camera_center_offset[seat_index].x, self.all_models[DAV.model_index].camera_center_offset[seat_index].y, self.all_models[DAV.model_index].camera_center_offset[seat_index].z))
end

--- Reset camera parameters
function Camera:ResetPerspective()
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close.baseBoomLength"), self.default_high_close_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close.boomLengthOffset"), self.default_high_close_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Close.lookAtOffset"), Vector3.new(self.high_close_center_offset.x, self.high_close_center_offset.y, self.high_close_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close.baseBoomLength"), self.default_low_close_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close.boomLengthOffset"), self.default_low_close_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Close.lookAtOffset"), Vector3.new(self.low_close_center_offset.x, self.low_close_center_offset.y, self.low_close_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium.baseBoomLength"), self.default_high_medium_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium.boomLengthOffset"), self.default_high_medium_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Medium.lookAtOffset"), Vector3.new(self.high_medium_center_offset.x, self.high_medium_center_offset.y, self.high_medium_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium.baseBoomLength"), self.default_low_medium_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium.boomLengthOffset"), self.default_low_medium_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Medium.lookAtOffset"), Vector3.new(self.low_medium_center_offset.x, self.low_medium_center_offset.y, self.low_medium_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far.baseBoomLength"), self.default_high_far_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far.boomLengthOffset"), self.default_high_far_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_Far.lookAtOffset"), Vector3.new(self.high_far_center_offset.x, self.high_far_center_offset.y, self.high_far_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far.baseBoomLength"), self.default_low_far_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far.boomLengthOffset"), self.default_low_far_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_Far.lookAtOffset"), Vector3.new(self.low_far_center_offset.x, self.low_far_center_offset.y, self.low_far_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose.baseBoomLength"), self.default_high_close_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose.boomLengthOffset"), self.default_high_close_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatClose.lookAtOffset"), Vector3.new(self.high_driver_combat_close_center_offset.x, self.high_driver_combat_close_center_offset.y, self.high_driver_combat_close_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose.baseBoomLength"), self.default_low_close_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose.boomLengthOffset"), self.default_low_close_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatClose.lookAtOffset"), Vector3.new(self.low_driver_combat_close_center_offset.x, self.low_driver_combat_close_center_offset.y, self.low_driver_combat_close_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium.baseBoomLength"), self.default_high_medium_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium.boomLengthOffset"), self.default_high_medium_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatMedium.lookAtOffset"), Vector3.new(self.high_driver_combat_medium_center_offset.x, self.high_driver_combat_medium_center_offset.y, self.high_driver_combat_medium_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium.baseBoomLength"), self.default_low_medium_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium.boomLengthOffset"), self.default_low_medium_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatMedium.lookAtOffset"), Vector3.new(self.low_driver_combat_medium_center_offset.x, self.low_driver_combat_medium_center_offset.y, self.low_driver_combat_medium_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar.baseBoomLength"), self.default_high_far_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar.boomLengthOffset"), self.default_high_far_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_High_DriverCombatFar.lookAtOffset"), Vector3.new(self.high_driver_combat_far_center_offset.x, self.high_driver_combat_far_center_offset.y, self.high_driver_combat_far_center_offset.z))
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar.baseBoomLength"), self.default_low_far_distance)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar.boomLengthOffset"), self.default_low_far_distance_offset)
    TweakDB:SetFlat(TweakDBID.new("Camera.VehicleTPP_4w_Preset_Low_DriverCombatFar.lookAtOffset"), Vector3.new(self.low_driver_combat_far_center_offset.x, self.low_driver_combat_far_center_offset.y, self.low_driver_combat_far_center_offset.z))
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
    if self.current_camera_mode ~= Def.CameraDistanceLevel.TppFar then
        self.current_camera_mode = self.current_camera_mode + 1
    elseif self.current_camera_mode == Def.CameraDistanceLevel.TppFar then
        self.current_camera_mode = Def.CameraDistanceLevel.Fpp
    end
    self:ChangePosition(self.current_camera_mode)
    return self.current_camera_mode
end

return Camera