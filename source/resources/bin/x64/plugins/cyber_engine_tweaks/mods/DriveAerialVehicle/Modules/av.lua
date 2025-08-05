local Camera = require("Modules/camera.lua")
local Position = require("Modules/position.lua")
local Engine = require("Modules/engine.lua")
local Utils = require("Etc/utils.lua")
local AV = {}
AV.__index = AV

--- Constractor.
---@param core_obj any Core instance
---@return table instance av instance
function AV:New(core_obj)
	---instance---
	local obj = {}
	obj.core_obj = core_obj
	obj.all_models = core_obj.all_models
	-- obj.position_obj = Position:New(core_obj.all_models)
	obj.engine_obj = Engine:New(obj)
	obj.camera_obj = Camera:New(core_obj.all_models)
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "AV")
	---static---
	-- door
	obj.duration_zero_wait = 0.5
	-- summon
	obj.spawn_distance = 5.5
	obj.spawn_height = 20
	obj.down_timeout = 500
	obj.up_timeout = 350
	obj.down_speed = -5.0
	-- autopiolt
	obj.profile_path = "Data/autopilot_profile.json"
	obj.destination_range = 3
	obj.destination_z_offset = 10
	obj.autopilot_angle_restore_rate = 0.01
	obj.autopilot_landing_angle_restore_rate = 0.1
	obj.standard_leaving_height = 20
	obj.exception_area_path = "Data/autopilot_exception_area.json"
	obj.check_cell_distance = 5.0 -- check cell distance when leaving
	-- thruster
	obj.thruster_angle_step = 0.6
	obj.thruster_angle_restore = 0.3
	---dynamic---
	-- common
	obj.entity_id = nil
	-- door
	obj.combat_door = nil
	obj.door_input_lock_list = {seat_front_left = false, seat_front_right = false, seat_back_left = false, seat_back_right = false, trunk = false, hood = false}
	-- summon
	obj.vehicle_model_tweakdb_id = nil
	obj.vehicle_model_type = nil
	obj.active_seat = nil
	obj.active_door = nil
	obj.seat_index = 1
	obj.is_crystal_dome = false
	obj.search_ground_offset = 2
	obj.search_ground_distance = 100
	obj.collision_filters =  {"Static", "Terrain", "Water"}
	obj.weak_collision_filters = {"Static", "Terrain"}
	obj.minimum_distance_to_ground = 1.2
	-- av status
	obj.is_landed = false
	obj.is_leaving = false
	obj.is_auto_pilot = false
	obj.is_unmounting = false
	obj.is_spawning = false
	obj.is_combat = false
	-- autopiolt
	obj.autopilot_profile = nil
	obj.mappin_destination_position = Vector4.new(0, 0, 0, 1)
	obj.favorite_destination_position = Vector4.new(0, 0, 0, 1)
	obj.autopilot_speed = 1
	obj.autopilot_turn_speed = 0.01
	obj.autopilot_land_offset = -1.0
	obj.autopilot_down_time_count = 100
	obj.autopilot_leaving_height = 100
	obj.autopilot_searching_range = 50
	obj.autopilot_searching_step = 5
	obj.is_failture_auto_pilot = false
	obj.autopilot_horizontal_sign = 0
	obj.autopilot_vertical_sign = 0
	obj.auto_speed_reduce_rate = 1
	obj.search_range = 1
	obj.is_search_start_swing_reverse = false
	obj.initial_destination_length = 1
	obj.dest_dir_vector_norm = 1
	obj.pre_speed_list = {x = 0, y = 0, z = 0}
	obj.autopilot_exception_area_list = {}
	obj.autopilot_prevention_length = 10
	-- appearance
	obj.is_enable_crystal_dome = false
	obj.is_enable_landing_vfx = false
	obj.landing_vfx_component = nil
	obj.is_landing_projection = false
	obj.destroy_app = nil
	-- audio
	obj.engine_audio_name = nil
	obj.is_acceleration_sound = false
	obj.is_thruster_sound = false
	-- truster
	obj.is_available_thruster = false
	obj.engine_component_name_list = {}
	obj.engine_offset_list = {}
	obj.thruster_fx_name_list = {}
	obj.thruster_offset_list = {}
	obj.engine_components = {}
	obj.thruster_fxs = {}
	obj.thruster_angle = 0
	obj.thruster_angle_max = 0
	-- enter and exit
	obj.enter_point = {}
	obj.entry_area_radius = 0
	obj.exit_point = {}
	-- landing
	obj.minimum_distance_to_ground = 1.2
	return setmetatable(obj, self)
end

--- Initialize
function AV:Init()
	self.camera_obj:Init()

	local index = DAV.model_index
	local type_number = DAV.model_type_index

	self.vehicle_model_tweakdb_id = self.all_models[index].tweakdb_id
	self.vehicle_model_type = self.all_models[index].type[type_number]
	self.active_seat = self.all_models[index].actual_allocated_seat
	self.active_door = self.all_models[index].actual_allocated_door
	self.exit_duration = self.all_models[index].exit_duration
	self.combat_door = self.all_models[index].combat_door
	self.is_enable_crystal_dome = self.all_models[index].crystal_dome
	self.is_enable_landing_vfx = self.all_models[index].landing_vfx
	self.projection_offset = self.all_models[index].projection_offset
	self.engine_audio_name = self.all_models[index].engine_audio_name
	self.is_enable_manual_speed_meter = self.all_models[index].manual_speed_meter
	self.is_enable_manual_rpm_meter = self.all_models[index].manual_rpm_meter
	self.is_armed = self.all_models[index].armed
	self.engine_component_name_list = self.all_models[index].engine_component_name
	self.engine_offset_list = self.all_models[index].engine_component_offset
	self.thruster_fx_name_list = self.all_models[index].thruster_fx_name
	self.thruster_offset_list = self.all_models[index].thruster_fx_offset
	self.thruster_angle_max = self.all_models[index].thruster_angle_max
	self.destroy_app = self.all_models[index].destroy_app
	self.entry_point = { x = self.all_models[index].entry_point.x, y = self.all_models[index].entry_point.y, z = self.all_models[index].entry_point.z }
    self.entry_area_radius = self.all_models[index].entry_area_radius
	self.exit_point = {x = self.all_models[index].exit_point.x, y = self.all_models[index].exit_point.y, z = self.all_models[index].exit_point.z}
	self.minimum_distance_to_ground = self.all_models[index].minimum_distance_to_ground
	self.flight_mode = self.all_models[DAV.model_index].flight_mode

	-- read autopilot profile
	local speed_level = DAV.user_setting_table.autopilot_speed_level
	self.autopilot_profile = Utils:ReadJson(self.profile_path)
	self.autopilot_speed = self.autopilot_profile[speed_level].speed
	self.autopilot_turn_speed = self.autopilot_profile[speed_level].turn_speed
	self.autopilot_land_offset = self.autopilot_profile[speed_level].land_offset
	self.autopilot_down_time_count = self.autopilot_profile[speed_level].down_time_count
	self.autopilot_leaving_height = self.autopilot_profile[speed_level].leaving_height
	self.autopilot_searching_range = self.autopilot_profile[speed_level].searching_range
	self.autopilot_searching_step = self.autopilot_profile[speed_level].searching_step
	self.autopilot_min_speed_rate = self.autopilot_profile[speed_level].min_speed_rate
	self.autopilot_is_only_horizontal = self.autopilot_profile[speed_level].is_only_horizontal
	self.autopilot_exception_area_list = Utils:ReadJson(self.exception_area_path)
	self.autopilot_prevention_length = self.all_models[index].autopilot_prevention_length
end

--- Check if player is mounted.
---@return boolean
function AV:IsPlayerIn()
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		return false
	end
	return entity:IsPlayerMounted()
end

--- Check if AV is spawning.
---@return boolean
function AV:IsSpawning()
	return self.is_spawning
end

--- Check if AV is destroyed.
---@return boolean
function AV:IsDestroyed()
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		return true
	end
	return entity:IsDestroyed()
end

--- Check if AV is despawned.
---@return boolean
function AV:IsDespawned()
	if Game.FindEntityByID(self.entity_id) == nil then
		return true
	else
		return false
	end
end

--- Get AV position.
---@return Vector4
function AV:GetPosition()
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		return Vector4.Zero()
	end
	return entity:GetWorldPosition()
end

--- Get Vehicle Forward Vector
---@return Vector4
function AV:GetForward()
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetForward")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldForward()
end

--- Get Vehicle Right Vector
---@return Vector4
function AV:GetRight()
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetRight")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldRight()
end

--- Get Vehicle Up Vector
---@return Vector4
function AV:GetUp()
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetUp")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldUp()
end

--- Get Vehicle Quaternion
---@return Quaternion
function AV:GetQuaternion()
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetQuaternion")
        return Quaternion.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldOrientation()
end

--- Get Vehicle EulerAngles
---@return EulerAngles
function AV:GetEulerAngles()
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetEulerAngles")
        return EulerAngles.new(0, 0, 0)
    end
    return entity:GetWorldOrientation():ToEulerAngles()
end

--- Get Ground Position
---@return number z
function AV:GetGroundPosition()
    local current_position = self:GetPosition()
	if current_position == nil then
		self.log_obj:Record(LogLevel.Warning, "No position to get ground position")
		return 0
	end
    current_position.z = current_position.z + self.search_ground_offset
    for _, filter in ipairs(self.collision_filters) do
        local is_success, trace_result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_position, Vector4.new(current_position.x, current_position.y, current_position.z - self.search_ground_distance, 1.0), filter, false, false)
        if is_success then
            return trace_result.position.z
        end
    end
    return current_position.z - self.search_ground_distance - 1
end

--- Get Height between ground and vehicle
---@return number height
function AV:GetHeight()
    return self:GetPosition().z - self:GetGroundPosition()
end

--- Check if player is mounted combat seat.
---@return boolean
function AV:IsMountedCombatSeat()
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to check combat seat")
		return false
	end
	if not entity:IsPlayerMounted() then
		self.log_obj:Record(LogLevel.Trace, "Check Combat Seat: No player mounted")
		return false
	end
	if self.is_armed and self.active_seat[self.seat_index] == "seat_front_left" then
		return true
	else
		return false
	end
end

--- Check if engine is on.
---@return boolean
function AV:IsEngineOn()
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to check engine")
		return false
	end
	return entity:IsEngineTurnedOn()
end

--- Spawn AV.
---@return boolean
function AV:Spawn(position, angle)
	if self.entity_id ~= nil then
		self.log_obj:Record(LogLevel.Info, "Entity already spawned")
		return false
	end

	self.is_spawning = true

	local entity_system = Game.GetDynamicEntitySystem()
	local entity_spec = DynamicEntitySpec.new()

	entity_spec.recordID = self.vehicle_model_tweakdb_id
	entity_spec.appearanceName = self.vehicle_model_type
	entity_spec.position = position
	entity_spec.orientation = angle
	entity_spec.persistState = false
	entity_spec.persistSpawn = false
	self.entity_id = entity_system:CreateEntity(entity_spec)

	-- set entity id to position object
	Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			self.is_spawning = false
			self.landing_vfx_component = entity:FindComponentByName("LandingVFXSlot")
			self.engine_obj:Init(self.entity_id)
			self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.engine_obj:EnableGravity(false)
			Cron.After(0.5, function()
				self.core_obj.event_obj.sound_obj:StartEngineSound(self.flight_mode, 1.5)
				if self:SetThrusterComponent() then
					self.is_available_thruster = true
				else
					self.is_available_thruster = false
				end
			end)
			Cron.Halt(timer)
		end
	end)

	return true
end

--- Spawn AV at sky.
function AV:SpawnToSky()
	local position = self:GetSpawnPosition(self.spawn_distance, 0.0)
	position.z = position.z + self.spawn_height
	local angle = self:GetSpawnOrientation(90.0)
	self:Spawn(position, angle)
	Cron.Every(0.01, { tick = 1 }, function(timer)
		if not self.core_obj.event_obj:IsInMenuOrPopupOrPhoto() and not self.is_spawning then
			if timer.tick == 1 then
				self:DisableAllDoorInteractions()
				self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, self.down_speed))
				self.log_obj:Record(LogLevel.Info, "Initial Spawn Velocity: " .. self.engine_obj:GetDirectionVelocity().z)
			elseif self:GetHeight() < 10 and self.engine_obj:GetControlType() ~= Def.EngineControlType.FluctuationVelocity then
				self.engine_obj:SetFluctuationVelocityParams(-2, 1)
				self.log_obj:Record(LogLevel.Info, "Fluctuation Velocity")
			elseif self:GetHeight() < self.minimum_distance_to_ground or timer.tick > self.down_timeout then
				self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
				self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
				self.is_landed = true
				self.log_obj:Record(LogLevel.Info, "Spawn to sky success")
				Cron.Halt(timer)
			end
			timer.tick = timer.tick + 1
		end
	end)
end

--- Despawn AV.
---@return boolean
function AV:Despawn()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to despawn")
		return false
	end
	local entity_system = Game.GetDynamicEntitySystem()
	entity_system:DeleteEntity(self.entity_id)
	self.entity_id = nil
	return true
end

--- Despawn AV when it is on ground.
function AV:DespawnFromGround()
	Cron.Every(0.01, { tick = 1 }, function(timer)
		if not self.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
			if timer.tick == 1 then
				self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
				self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 1))
				self.log_obj:Record(LogLevel.Info, "Initial Despawn Velocity: " .. self.engine_obj:GetDirectionVelocity().z)
			elseif timer.tick == 2 then
				self.engine_obj:SetFluctuationVelocityParams(1, -self.down_speed)
				self.log_obj:Record(LogLevel.Info, "Fluctuation Velocity")
			elseif timer.tick >= self.up_timeout then
				self.log_obj:Record(LogLevel.Info, "Despawn Timeout")
				self.core_obj.event_obj.sound_obj:StopEngineSound(self.flight_mode, 1.5)
				Cron.After(1.5, function()
					self:Despawn()
				end)
				Cron.Halt(timer)
			end
			timer.tick = timer.tick + 1
		end
	end)
end

--- Toggle crystal dome ON/OFF.
---@return boolean
function AV:ToggleCrystalDome()
	local entity = Game.FindEntityByID(self.entity_id)
	local effect_name
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change crystal dome")
		return false
	elseif not self.is_enable_crystal_dome then
		self.log_obj:Record(LogLevel.Trace, "This vehicle does not have a crystal dome")
		return false
	end
	if not self.is_crystal_dome then
		effect_name = CName.new("crystal_dome_start")
		self.is_crystal_dome = true
	else
		effect_name = CName.new("crystal_dome_stop")
		self.is_crystal_dome = false
	end
	GameObjectEffectHelper.StartEffectEvent(entity, effect_name, false)
	return true
end

--- (Unused) Unlock all doors.
---@return boolean
function AV:UnlockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:UnlockAllVehDoors()
	return true
end

--- (Unused) Lock all doors.
---@return boolean
function AV:LockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:QuestLockAllVehDoors()
	return true
end

--- Disable all door interactions for preventing unexpected mounting.
---@return boolean
function AV:DisableAllDoorInteractions()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:DisableAllVehInteractions()
	return true
end

--- Get door state.
---@param e_veh_door EVehicleDoor
---@return VehicleDoorState | nil
function AV:GetDoorState(e_veh_door)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Trace, "No entity id to get door state")
		return nil
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Trace, "No entity to get door state")
		return nil
	end
	local vehicle_ps = entity:GetVehiclePS()
	return vehicle_ps:GetDoorState(e_veh_door)
end

--- Change door state.
---@param door_state Def.DoorOperation
---@return boolean
function AV:ChangeDoorState(door_state, door_name_list)
	for _, input_lock in pairs(self.door_input_lock_list) do
		if input_lock then
			self.log_obj:Record(LogLevel.Info, "Door input is locked")
			return false
		end
	end

	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to get door state")
		return false
	end

	-- local vehicle_ps = self.position_obj.entity:GetVehiclePS()
	local vehicle_ps = Game.FindEntityByID(self.entity_id):GetVehiclePS()

	if door_name_list == nil then
		door_name_list = self.active_door
	end

	for _, door_name in ipairs(door_name_list) do
		local e_veh_door = EVehicleDoor.seat_front_left
		if door_name == "seat_front_left" then
			e_veh_door = EVehicleDoor.seat_front_left
		elseif door_name == "seat_front_right" then
			e_veh_door = EVehicleDoor.seat_front_right
		elseif door_name == "seat_back_left" then
			e_veh_door = EVehicleDoor.seat_back_left
		elseif door_name == "seat_back_right" then
			e_veh_door = EVehicleDoor.seat_back_right
		elseif door_name == "trunk" then
			e_veh_door = EVehicleDoor.trunk
		elseif door_name == "hood" then
			e_veh_door = EVehicleDoor.hood
		end

		local door_event = nil
		if door_state == Def.DoorOperation.Open then
			door_event = VehicleDoorOpen.new()
		elseif door_state == Def.DoorOperation.Close then
			door_event = VehicleDoorClose.new()
		elseif door_state == Def.DoorOperation.Change then
			if self:GetDoorState(e_veh_door) == VehicleDoorState.Closed then
				door_event = VehicleDoorOpen.new()
			elseif self:GetDoorState(e_veh_door) == VehicleDoorState.Open then
				door_event = VehicleDoorClose.new()
			end
		end
		if door_event == nil then
			self.log_obj:Record(LogLevel.Error, "Door event is not valid")
			return false
		end

		self.log_obj:Record(LogLevel.Info, "Change Door State : " .. door_name .. " : " .. door_state)

		door_event.slotID = CName.new(door_name)
        door_event.forceScene = false
		vehicle_ps:QueuePSEvent(vehicle_ps, door_event)

	end
	return true
end

--- Toggle crystal dome ON/OFF.
function AV:ControlCrystalDome()
	local e_veh_door = EVehicleDoor.seat_front_left
	if not self.is_crystal_dome then
		Cron.Every(1, {tick = 1}, function(timer)
			if self:GetDoorState(e_veh_door) == VehicleDoorState.Closed then
				if self.vehicle_model_tweakdb_id == DAV.excalibur_record then
					Cron.After(3.0, function()
						self:ToggleCrystalDome()
					end)
				else
					self:ToggleCrystalDome()
				end
				Cron.Halt(timer)
			end
		end)
	elseif self.is_crystal_dome then
		self:ToggleCrystalDome()
	end
end

--- Mount AV.
---@return boolean
function AV:Mount()
	self.is_landed = false
	self.camera_obj:SetPerspective(self.seat_index)

	local seat_number = self.seat_index

	self.log_obj:Record(LogLevel.Debug, "Mount Aerial Vehicle : " .. seat_number)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to mount")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local player = Game.GetPlayer()
	local ent_id = entity:GetEntityID()
	local seat = self.active_seat[seat_number]

	local mount_data = MountEventData.new()
	mount_data.isInstant = false
	mount_data.slotName = seat
	mount_data.mountParentEntityId = ent_id

	local slot_id = MountingSlotId.new()
	slot_id.id = seat

	local mounting_info = MountingInfo.new()
	mounting_info.childId = player:GetEntityID()
	mounting_info.parentId = ent_id
	mounting_info.slotId = slot_id

	local mounting_request = MountingRequest.new()
	mounting_request.lowLevelMountingInfo = mounting_info
	mounting_request.mountData = mount_data

	Game.GetMountingFacility():Mount(mounting_request)

	if self.active_seat[seat_number] ~= "seat_front_left" and not self.is_crystal_dome then
		self:ToggleCrystalDome()
	else
		self.is_crystal_dome = true
	end

	return true
end

--- Unmount AV.
---@return boolean
function AV:Unmount()
	if self.is_unmounting then
		return false
	end

	self.is_unmounting = true

	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to unmount")
		self.is_unmounting = false
		return false
	end

	if self.is_crystal_dome then
		self:ControlCrystalDome()
	end

	self:ChangeDoorState(Def.DoorOperation.Open)

	local unmount_wait_time = self.exit_duration
	if unmount_wait_time == 0 then
		unmount_wait_time = self.duration_zero_wait
	end

	Cron.After(unmount_wait_time, function()

		self.log_obj:Record(LogLevel.Trace, "Unmount Aerial Vehicle : " .. self.seat_index)

		-- set entity id to position object
		Cron.Every(0.01, {tick = 1}, function(timer)
			timer.tick = timer.tick + 1
			if not self:IsPlayerIn() then
				self.log_obj:Record(LogLevel.Info, "Unmounted")
				local player = Game.GetPlayer()
				local entity = Game.FindEntityByID(self.entity_id)
				local vehicle_angle = entity:GetWorldOrientation():ToEulerAngles()
				local teleport_angle = EulerAngles.new(vehicle_angle.roll, vehicle_angle.pitch, vehicle_angle.yaw + 90)
				local position = self:GetExitPosition()
				Game.GetTeleportationFacility():Teleport(player, Vector4.new(position.x, position.y, position.z, 1.0), teleport_angle)
				self.is_unmounting = false
				Cron.Halt(timer)
			elseif timer.tick > 350 then
				self.log_obj:Record(LogLevel.Error, "Unmount failed")
				self:ChangeDoorState(Def.DoorOperation.Close)
				self.is_unmounting = false
				Cron.Halt(timer)
			end
		end)
	end)
	return true
end

--- Execute action commands.
--- @param action_command_lists table
function AV:Operate(action_command_lists)
	local x_total, y_total, z_total, roll_total, pitch_total, yaw_total = 0, 0, 0, 0, 0, 0
	self.log_obj:Record(LogLevel.Debug, "Operation Count:" .. #action_command_lists)
	for _, action_command_list in ipairs(action_command_lists) do
		if action_command_list[1] >= Def.ActionList.Enter then
			self.log_obj:Record(LogLevel.Critical, "Invalid Event Command:" .. action_command_list[1])
			return false
		end
		if action_command_list[1] ~= Def.ActionList.Nothing then
			self.log_obj:Record(LogLevel.Trace, "Operation:" .. action_command_list[1])
		end
		if action_command_list[1] == Def.ActionList.Idle then
			self.engine_obj:SetIdle(true)
		else
			self.engine_obj:SetIdle(false)
		end
		if not self.is_auto_pilot then
			local x, y, z, roll, pitch, yaw = self.engine_obj:CalculateAddVelocity(action_command_list)
			x = x * action_command_list[2]
			y = y * action_command_list[2]
			z = z * action_command_list[2]
			roll = roll * action_command_list[2]
			pitch = pitch * action_command_list[2]
			yaw = yaw * action_command_list[2]
			x_total = x_total + x
			y_total = y_total + y
			z_total = z_total + z
			roll_total = roll_total + roll
			pitch_total = pitch_total + pitch
			yaw_total = yaw_total + yaw
		end
	end

	if not self.is_auto_pilot then
		self.engine_obj:Run(x_total, y_total, z_total, roll_total, pitch_total, yaw_total)
		self:MoveThruster(action_command_lists)
		self:ControlSound(action_command_lists)
	end

	return true
end

--- Control sound.
---@param action_command_lists table
---@return boolean
function AV:ControlSound(action_command_lists)
	local is_acceleration_sound = false
	local is_thruster_sound = false
	for _, action_command_list in ipairs(action_command_lists) do
		if action_command_list[1] >= Def.ActionList.Enter then
			self.log_obj:Record(LogLevel.Trace, "Invalid Sound Command:" .. action_command_list[1])
			return false
		end
		for _, acceleration_command in pairs(Def.AccelerationActionList) do
			if action_command_list[1] == acceleration_command then
				is_acceleration_sound = true
				break
			end
		end
		for _, thruster_command in pairs(Def.ThrusterActionList) do
			if action_command_list[1] == thruster_command then
				is_thruster_sound = true
				break
			end
		end
		if is_acceleration_sound or is_thruster_sound then
			break
		end
	end

	if not self.is_acceleration_sound and is_acceleration_sound then
		self.log_obj:Record(LogLevel.Info, "Start Acceleration Sound")
		self.core_obj.event_obj.sound_obj:StartAccelerationSound(self.flight_mode, 1.5)
		self.is_acceleration_sound = true
		return true
	elseif self.is_acceleration_sound and not is_acceleration_sound then
		self.log_obj:Record(LogLevel.Info, "Stop Acceleration Sound")
		self.core_obj.event_obj.sound_obj:StopAccelerationSound(self.flight_mode, 1.5)
		self.is_acceleration_sound = false
		return true
	elseif not self.is_thruster_sound and is_thruster_sound then
		self.log_obj:Record(LogLevel.Info, "Start Thruster Sound")
		self.core_obj.event_obj.sound_obj:StartThrusterSound(self.flight_mode, 1.5)
		self.is_thruster_sound = true
		return true
	elseif self.is_thruster_sound and not is_thruster_sound then
		self.log_obj:Record(LogLevel.Info, "Stop Thruster Sound")
		self.core_obj.event_obj.sound_obj:StopThrusterSound(self.flight_mode, 1.5)
		self.is_thruster_sound = false
		return true
	end
	self.log_obj:Record(LogLevel.Trace, "No Sound Change")
	return true

end

--- Set destination by mappin.
---@param position Vector4
function AV:SetMappinDestination(position)
	self.mappin_destination_position = position
end

--- Set registered favorite destination.
---@param position Vector4
function AV:SetFavoriteDestination(position)
	self.favorite_destination_position = position
end

--- Excute Auto Pilot.
---@return boolean
function AV:AutoPilot()
	self.log_obj:Record(LogLevel.Info, "AutoPilot Start")
	self.is_auto_pilot = true
	local destination_position = Vector4.new(0, 0, 0, 1)
	local relay_position = nil
	if DAV.user_setting_table.autopilot_selected_index == 0 then
		if self.mappin_destination_position:IsZero() then
			self.log_obj:Record(LogLevel.Warning, "No Mappin Destination")
			self:InterruptAutoPilot()
			return false
		end
		destination_position = self.mappin_destination_position
		self.log_obj:Record(LogLevel.Info, "AutoPilot to Mappin Destination")
	else
		destination_position = self.favorite_destination_position
		self.log_obj:Record(LogLevel.Info, "AutoPilot to Favorite Destination")
	end

	destination_position.z = destination_position.z + self.destination_z_offset

	local current_position = self:GetPosition()

	local direction_vector = Vector4.new(destination_position.x - current_position.x, destination_position.y - current_position.y, destination_position.z - current_position.z, 1)
	self.initial_destination_length = Vector4.Length(direction_vector)

	if self.autopilot_is_only_horizontal then
		self:AutoLeaving(direction_vector, self.autopilot_leaving_height)
		self.log_obj:Record(LogLevel.Info, "Select Leaving Only Horizontal")
	else
		self:AutoLeaving(direction_vector, self.standard_leaving_height)
		self.log_obj:Record(LogLevel.Info, "Select Leaving Horizontal and Vertical")
	end

	-- autopilot parameter initialize
	self.autopilot_angle = 0
	self.autopilot_horizontal_sign = 0
	self.autopilot_vertical_sign = 0
	self.auto_speed_reduce_rate = 1
	self.pre_speed_list = {x = 0, y = 0, z = 0}

	-- autopilot loop
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1

		if self.is_leaving or self.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
			return
		end

		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			Cron.Halt(timer)
			return
		elseif self:IsCollision() then
			self.log_obj:Record(LogLevel.Info, "Collision Detected")
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end

		-- set destination vector
		current_position = self:GetPosition()
		local dest_dir_vector = Vector4.new(destination_position.x - current_position.x, destination_position.y - current_position.y, destination_position.z - current_position.z, 1)
		if self.autopilot_is_only_horizontal then
			dest_dir_vector.z = 0
		elseif dest_dir_vector.z < 0 then
			dest_dir_vector.z = 0
		end
		self.dest_dir_vector_norm = Vector4.Length2D(dest_dir_vector)

		-- check destination
		if self.dest_dir_vector_norm < self.destination_range then
			self.log_obj:Record(LogLevel.Info, "Arrived at destination")
			self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:AutoLanding(current_position.z - destination_position.z)
			Cron.Halt(timer)
			return
		end

		-- set direction vector
		if relay_position ~= nil then
			direction_vector = Vector4.new(relay_position.x - current_position.x, relay_position.y - current_position.y, relay_position.z - current_position.z, 1)
		end
		local direction_vector_norm = Vector4.Length(direction_vector)

		-- check destination
		if self.autopilot_is_only_horizontal then
			relay_position = Vector4.new(destination_position.x, destination_position.y, current_position.z, 1)
		elseif relay_position ~= nil and direction_vector_norm < self.destination_range then
			relay_position = nil
		end

		-- decide relay position
		if relay_position == nil then
			local dest_dir_2d = Vector4.new(dest_dir_vector.x, dest_dir_vector.y, 0, 1)
			local search_vec = Vector4.Zero()
			local is_wall = true
			local res, vec
			for r_2 = 1, 2 do
				self.search_range = self.autopilot_searching_range
				if self.dest_dir_vector_norm < self.autopilot_searching_range then
					self.search_range = self.dest_dir_vector_norm + 0.1
				end

				self.search_range = self.search_range / (2 ^ (r_2 - 1))
				if self.search_range < self.autopilot_searching_step then
					self.search_range = self.autopilot_searching_step
				end
				for i = 1, 2 do
					local search_angle_step = 6
					local min_search_angle = 90 * (i - 1)
					local max_search_angle = 90 * (i - 1) + 90 - search_angle_step
					for _, swing in ipairs({"Down", "Left", "Right", "Up"}) do
						local sign = 1
						local swing_direction = "Horizontal"
						if swing == "Down" or swing == "Left" then
							sign = -1
						end
						if swing == "Down" or swing == "Up" then
							swing_direction = "Vertical"
						end
						local find_angle = 0
						for search_angle = min_search_angle, max_search_angle, search_angle_step do
							if (swing_direction == "Horizontal" and self.autopilot_horizontal_sign * sign >= 0 and search_angle < 90) or (swing_direction == "Vertical" and self.autopilot_vertical_sign * sign >= 0 and search_angle * sign > -90 ) then
								if search_angle == 0 then
									res, vec = self:IsWall(dest_dir_vector, self.search_range, sign * search_angle, swing_direction, true)
								else
									local is_check_exception_area = true
									if swing_direction == "Vertical" and search_angle * sign >= 90 then
										is_check_exception_area = false
									end
									res, vec = self:IsWall(dest_dir_2d, self.search_range, sign * search_angle, swing_direction, is_check_exception_area)
								end
								if not res then
									find_angle = search_angle
									is_wall = false
									search_vec = vec
									self.autopilot_angle = sign * search_angle
									if swing_direction == "Horizontal" then
										if self.autopilot_horizontal_sign * sign <= 0 then
											self.autopilot_horizontal_sign = sign
										end
									elseif swing_direction == "Vertical" then
										if self.autopilot_vertical_sign * sign <= 0 and sign > 0 then
											self.autopilot_vertical_sign = sign
										end
									end
									break
								end
							end
						end
						if not is_wall then
							local find_angle_abs = math.abs(find_angle)
							if find_angle_abs < 30 then
								self:MoveThruster({{Def.ActionList.Forward, 1}})
							else
								self:MoveThruster({{Def.ActionList.Nothing, 1}})
							end
							self.auto_speed_reduce_rate = (90 - find_angle_abs) / 90
							if self.auto_speed_reduce_rate < self.autopilot_min_speed_rate then
								self.auto_speed_reduce_rate = self.autopilot_min_speed_rate
							end
							if find_angle_abs == 90 then
								self.auto_speed_reduce_rate = 1
							end
							break
						end
					end
					if not is_wall then
						break
					end
				end
				if not search_vec:IsZero() then
					local pos = relay_position or current_position
					relay_position = Vector4.new(pos.x + self.autopilot_searching_step * search_vec.x, pos.y + self.autopilot_searching_step * search_vec.y, pos.z + self.autopilot_searching_step * search_vec.z, 1)
				end
				if self.autopilot_angle == 0 then
					-- reset search angle
					self.autopilot_horizontal_sign = 0
					self.autopilot_vertical_sign = 0
				end
				if not is_wall then
					if relay_position ~= nil then
						self.log_obj:Record(LogLevel.Trace, "Relay Position : " .. relay_position.x .. ", " .. relay_position.y .. ", " .. relay_position.z)
					else
						self.log_obj:Record(LogLevel.Critical, "Relay Position : nil")
					end
					break
				end
				if r_2 >= 2 then
					if self.autopilot_vertical_sign <= 0 then
						self.autopilot_vertical_sign = 1
						return
					else
						self.log_obj:Record(LogLevel.Info, "AutoPilot Move Interrupted")
						self:InterruptAutoPilot()
						Cron.Halt(timer)
						return
					end
				end
			end
		end

		-- recheck relay position
		if relay_position ~= nil then
			direction_vector = Vector4.new(relay_position.x - current_position.x, relay_position.y - current_position.y, relay_position.z - current_position.z, 1)
		end
		direction_vector_norm = Vector4.Length(direction_vector)

		-- speed control
		if self.auto_speed_reduce_rate < self.autopilot_min_speed_rate then
			self.auto_speed_reduce_rate = self.autopilot_min_speed_rate
		elseif self.auto_speed_reduce_rate > 1 then
			self.auto_speed_reduce_rate = 1
		end
		-- local autopilot_speed = self.autopilot_speed * self.auto_speed_reduce_rate
		local autopilot_speed = 10 * self.auto_speed_reduce_rate
		local fix_direction_vector = Vector4.new(autopilot_speed * direction_vector.x / direction_vector_norm, autopilot_speed * direction_vector.y / direction_vector_norm, autopilot_speed * direction_vector.z / direction_vector_norm, 1)

		-- yaw control
		local vehicle_angle = self:GetForward()
		local vehicle_angle_norm = Vector4.Length(vehicle_angle)
		local yaw_vehicle = math.atan2(vehicle_angle.y / vehicle_angle_norm, vehicle_angle.x / vehicle_angle_norm) * 180 / Pi()
		local yaw_dist = yaw_vehicle
		if self.dest_dir_vector_norm ~= 0 then
			yaw_dist = math.atan2(dest_dir_vector.y / self.dest_dir_vector_norm, dest_dir_vector.x / self.dest_dir_vector_norm) * 180 / Pi()
		end
		local yaw_diff = yaw_dist - yaw_vehicle
		if yaw_diff > 180 then
			yaw_diff = yaw_diff - 360
		elseif yaw_diff < -180 then
			yaw_diff = yaw_diff + 360
		end
		local yaw_diff_half = yaw_diff * self.autopilot_turn_speed
		if math.abs(yaw_diff_half) < 0.1 then
			yaw_diff_half = yaw_diff
		end

		-- restore angle
		local current_angle = self:GetEulerAngles()
		local roll_diff = 0
		local pitch_diff = 0
		roll_diff = roll_diff - current_angle.roll * self.autopilot_angle_restore_rate
		pitch_diff = pitch_diff - current_angle.pitch * self.autopilot_angle_restore_rate

		-- roll and pitch control
		local forward = vehicle_angle
		local dir = direction_vector
		forward.z = 0
		dir.z = 0
		local forward_base_vec = Vector4.Normalize(forward)
		local direction_base_vec = Vector4.Normalize(dir)
		local between_angle = 0
		if not direction_base_vec:IsXYZZero() then
			between_angle = Vector4.GetAngleDegAroundAxis(forward_base_vec, direction_base_vec, Vector4.new(0, 0, 1, 1))
		end
		local between_angle_rad = math.rad(between_angle)
		if math.abs(current_angle.roll) < self.engine_obj.max_roll * 0.5 and math.abs(current_angle.pitch) < self.engine_obj.max_pitch * 0.5 then
			-- helicopter pitch control
			if self.engine_obj.flight_mode == Def.FlightMode.Helicopter then
				pitch_diff = pitch_diff - math.cos(between_angle_rad) * 0.5 * (1 - math.abs(current_angle.pitch) / (self.engine_obj.max_pitch * 0.5))
			end
			roll_diff = roll_diff - math.sin(between_angle_rad) * 0.5 * (1 - math.abs(current_angle.roll) / (self.engine_obj.max_roll * 0.5))
		end

		self.log_obj:Record(LogLevel.Debug, "AutoPilot Move : " .. fix_direction_vector.x .. ", " .. fix_direction_vector.y .. ", " .. fix_direction_vector.z .. ", " .. roll_diff .. ", " .. pitch_diff .. ", " .. yaw_diff_half)
		local dummy_inertia = Utils:ScaleListValues(self.pre_speed_list, 1)
		local x, y, z, roll, pitch, yaw = fix_direction_vector.x, fix_direction_vector.y, fix_direction_vector.z, roll_diff, pitch_diff, yaw_diff_half
		local new_x, new_y, new_z = x + dummy_inertia.x, y + dummy_inertia.y, z + dummy_inertia.z
		local new_vector_norm = math.sqrt(new_x * new_x + new_y * new_y + new_z * new_z)
		local fix_direction_vector_norm = Vector4.Length(Vector4.new(fix_direction_vector.x, fix_direction_vector.y, fix_direction_vector.z, 1))
		local adjust_x, adjust_y, adjust_z = new_x * fix_direction_vector_norm / new_vector_norm, new_y * fix_direction_vector_norm / new_vector_norm, new_z * fix_direction_vector_norm / new_vector_norm
		self.pre_speed_list = {x = adjust_x, y = adjust_y, z = adjust_z}

		local _, _, _, roll_nothing ,pitch_nothing ,_ = self.engine_obj:CalculateAddVelocity({Def.ActionList.Nothing, 1})
		roll = roll + roll_nothing
		pitch = pitch + pitch_nothing
		-- limit
		if current_angle.roll > self.engine_obj.max_roll or current_angle.roll < -self.engine_obj.max_roll then
			roll = 0
		end
		if current_angle.pitch > self.engine_obj.max_pitch or current_angle.pitch < -self.engine_obj.max_pitch then
			pitch = 0
		end
		self.engine_obj:Run(adjust_x, adjust_y, adjust_z, roll, pitch, yaw)
	end)
	return true
end

--- Excute Leaving when auto pilot is on.
---@param dist_vector Vector4 vector to destination position
---@param height number | nil height to end leaving
function AV:AutoLeaving(dist_vector, height)
	self.is_leaving = true

	local res, _, area_height = self:IsInExceptionArea(self:GetPosition())
	if res then
		height = area_height + 10
	end

	local current_position = self:GetPosition()
	local leaving_height = height or self.autopilot_leaving_height - current_position.z
	local leaving_position = Vector4.new(current_position.x, current_position.y, current_position.z + leaving_height, 1)
	self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0.5))
	self.engine_obj:SetFluctuationVelocityParams(1, 5)
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			self.is_leaving = false
			Cron.Halt(timer)
			return
		elseif self:IsCollision() then
			self.log_obj:Record(LogLevel.Info, "Collision Detected")
			self:InterruptAutoPilot()
			self.is_leaving = false
			Cron.Halt(timer)
			return
		end

		local is_dettected_celling, _ = self:IsWall(Vector4.new(0,0,1), self.check_cell_distance, 90, "Vertical", true)
		local current_position_in_leaving = self:GetPosition()

		if current_position_in_leaving.z > leaving_position.z or is_dettected_celling then
			self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
				timer.tick = timer.tick + 1
				if not self.is_auto_pilot then
					self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted by Canceling")
					self:InterruptAutoPilot()
					self.is_leaving = false
					Cron.Halt(timer)
					return
				elseif self:IsCollision() then
					self.log_obj:Record(LogLevel.Info, "Collision Detected")
					self:InterruptAutoPilot()
					self.is_leaving = false
					Cron.Halt(timer)
					return
				end

				-- yaw control
				local vehicle_angle = self:GetForward()
				local vehicle_angle_norm = Vector4.Length(vehicle_angle)
				local yaw_vehicle = math.atan2(vehicle_angle.y / vehicle_angle_norm, vehicle_angle.x / vehicle_angle_norm) * 180 / Pi()
				local yaw_dist = yaw_vehicle
				local dist_vector_norm = dist_vector:Length2D()
				if dist_vector_norm ~= 0 then
					yaw_dist = math.atan2(dist_vector.y / dist_vector_norm, dist_vector.x / dist_vector_norm) * 180 / Pi()
				end
				local yaw_diff = yaw_dist - yaw_vehicle
				if yaw_diff > 180 then
					yaw_diff = yaw_diff - 360
				elseif yaw_diff < -180 then
					yaw_diff = yaw_diff + 360
				end
				local yaw_diff_half = yaw_diff * self.autopilot_turn_speed
				if math.abs(yaw_diff_half) < 0.1 then
					yaw_diff_half = yaw_diff
				end

				self.engine_obj:Run(0.0, 0.0, 0.0, 0.0, 0.0, yaw_diff_half)

				if math.abs(yaw_diff_half) < 0.1 then
					self.engine_obj:Run(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
					self.is_leaving = false
					Cron.Halt(timer)
				end
			end)
			Cron.Halt(timer)
		end
		self:MoveThruster({{Def.ActionList.Nothing, 1}})
	end)
end

--- Excute Landing when auto pilot is on.
--- @param height number height to start landing
function AV:AutoLanding(height)
	if height <= self.standard_leaving_height then
		self.log_obj:Record(LogLevel.Info, "AutoPilot Landing : Already Arrived")
		self.is_landed = true
		self:SeccessAutoPilot()
		return
	end
	local down_time_count = height / self.autopilot_speed
	self.log_obj:Record(LogLevel.Info, "AutoPilot Landing Start :" .. tostring(down_time_count) .. "s, " .. tostring(height) .. "m")
	self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, -5.0))
	self.engine_obj:SetFluctuationVelocityParams(-0.5, 1.0)
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted by Canceling")
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end

		-- restore angle 
		local current_angle = self:GetEulerAngles()
		local roll_diff = 0
		local pitch_diff = 0
		roll_diff = roll_diff - current_angle.roll * self.autopilot_landing_angle_restore_rate
		pitch_diff = pitch_diff - current_angle.pitch * self.autopilot_landing_angle_restore_rate

		if timer.tick > self.down_timeout or self:GetHeight() < self.minimum_distance_to_ground or self:IsCollision() then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Success.")
			self.is_landed = true
			self:SeccessAutoPilot()
			Cron.Halt(timer)
		end

		self:MoveThruster({{Def.ActionList.Nothing, 1}})
	end)
end

--- Set AV.is_failture_auto_pilot and AV.is_auto_pilot when AutoPilot Success.
function AV:SeccessAutoPilot()
	self.is_auto_pilot = false
	self.is_failture_auto_pilot = false
	self.core_obj:SetAutoPilotHistory()
end

--- Set AV.is_failture_auto_pilot and AV.is_auto_pilot when AutoPilot Failed.
function AV:InterruptAutoPilot()
	self.is_auto_pilot = false
	self.is_failture_auto_pilot = true
end

--- Set AV.is_failture_auto_pilot and get Failture AutoPilot Flag.
---@return boolean
function AV:IsFailedAutoPilot()
	local is_failture_auto_pilot = self.is_failture_auto_pilot
	self.is_failture_auto_pilot = false
	return is_failture_auto_pilot
end

--- Reload Autopilot Profile from settings file.
function AV:ReloadAutopilotProfile()
	local speed_level = DAV.user_setting_table.autopilot_speed_level
	self.autopilot_speed = self.autopilot_profile[speed_level].speed
	self.autopilot_turn_speed = self.autopilot_profile[speed_level].turn_speed
	self.autopilot_land_offset = self.autopilot_profile[speed_level].land_offset
	self.autopilot_down_time_count = self.autopilot_profile[speed_level].down_time_count
	self.autopilot_leaving_height = self.autopilot_profile[speed_level].leaving_height
	self.autopilot_searching_range = self.autopilot_profile[speed_level].searching_range
	self.autopilot_searching_step = self.autopilot_profile[speed_level].searching_step
	self.autopilot_min_speed_rate = self.autopilot_profile[speed_level].min_speed_rate
	self.autopilot_is_only_horizontal = self.autopilot_profile[speed_level].is_only_horizontal
end

--- Toggle radio ON or next radioStation.
function AV:ToggleRadio()
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change radio")
		return
	end
	if entity:IsRadioReceiverActive() then
		entity:NextRadioReceiverStation()
	else
		entity:ToggleRadioReceiver(true)
	end
end

--- Change appearance.
---@param type string appearance name
function AV:ChangeAppearance(type)
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change appearance")
		return
	end
	entity:ScheduleAppearanceChange(type)
	Cron.After(0.1, function()
		if self:SetThrusterComponent() then
			self.is_available_thruster = true
		else
			self.is_available_thruster = false
		end
	end)
end

--- Set landing vfx position.
---@param position Vector4 offset center position
function AV:SetLandingVFXPosition(position)
	if self.is_enable_landing_vfx and DAV.user_setting_table.is_enable_landing_vfx then
		self.landing_vfx_component:SetLocalPosition(position)
	end
end

--- Toggle landing warning ON/OFF.
---@param on boolean
function AV:ProjectLandingWarning(on)
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Trace, "No entity to project landing warning")
		return
	end
	if self.is_enable_landing_vfx and DAV.user_setting_table.is_enable_landing_vfx then
		if on and not self.is_landing_projection then
			GameObjectEffectHelper.StartEffectEvent(entity, CName.new("landingWarning"), false)
			GameObjectEffectHelper.StartEffectEvent(entity, CName.new("projectorVFX"), false)
			self.is_landing_projection = true
		elseif not on and self.is_landing_projection then
			GameObjectEffectHelper.StopEffectEvent(entity, CName.new("landingWarning"))
			GameObjectEffectHelper.StopEffectEvent(entity, CName.new("projectorVFX"))
			self.is_landing_projection = false
		end
	end
end

--- Set thruster component to move its angle.
---@return boolean
function AV:SetThrusterComponent()
	if self.engine_obj.flight_mode == Def.FlightMode.Helicopter then
		return false
	end

	self.engine_components = {}
	self.thruster_fxs = {}

	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end

	if self.engine_component_name_list ~= nil then
		for pos, component_name in pairs(self.engine_component_name_list) do
			self.engine_components[pos] = entity:FindComponentByName(component_name)
			if self.engine_components[pos] == nil then
				self.log_obj:Record(LogLevel.Warning, "No thruster component : " .. component_name)
				return false
			end
			self.engine_components[pos]:SetLocalPosition(Vector4.new(self.engine_offset_list[pos].x, self.engine_offset_list[pos].y, self.engine_offset_list[pos].z, 1))
		end
	end

	if self.thruster_fx_name_list ~= nil then
		for pos, thruster_name in pairs(self.thruster_fx_name_list) do
			self.thruster_fxs[pos] = entity:FindComponentByName(thruster_name)
			if self.thruster_fxs[pos] == nil then
				self.log_obj:Record(LogLevel.Warning, "No thruster fx : " .. thruster_name)
				return false
			end
			self.thruster_fxs[pos]:SetLocalPosition(Vector4.new(self.thruster_offset_list[pos].x, self.thruster_offset_list[pos].y, self.thruster_offset_list[pos].z, 1))
		end
	else
		return false
	end
	return true
end

--- Change thruster angle by action commands.
---@param action_command_lists table
---@return boolean
function AV:MoveThruster(action_command_lists)
	if self.thruster_angle > self.thruster_angle_restore then
		self.thruster_angle = self.thruster_angle - self.thruster_angle_restore
	elseif self.thruster_angle < -self.thruster_angle_restore then
		self.thruster_angle = self.thruster_angle + self.thruster_angle_restore
	else
		self.thruster_angle = 0
	end

	if not self.is_available_thruster then
		return false
	end

	for _, action_command_list in ipairs(action_command_lists) do
		if action_command_list[1] == Def.ActionList.Forward then
			self.thruster_angle = self.thruster_angle - self.thruster_angle_step
		elseif action_command_list[1] == Def.ActionList.Backward then
			self.thruster_angle = self.thruster_angle + self.thruster_angle_step
		end
	end

	if self.thruster_angle > self.thruster_angle_max then
		self.thruster_angle = self.thruster_angle_max
	elseif self.thruster_angle < -self.thruster_angle_max then
		self.thruster_angle = -self.thruster_angle_max
	end

	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end

	local angle = EulerAngles.new(0, self.thruster_angle, 0)

	for _, component in pairs(self.engine_components) do
		component:SetLocalOrientation(angle:ToQuat())
	end

	for _, thruster in pairs(self.thruster_fxs) do
		thruster:SetLocalOrientation(angle:ToQuat())
	end
	return true
end

--- Toggle thruster ON/OFF.
---@param on boolean
---@return boolean
function AV:ToggleThruster(on)
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end
	if not self.is_available_thruster then
		return false
	end

	if on then
		GameObjectEffectHelper.StartEffectEvent(entity, CName.new("thrusters"))
	else
		GameObjectEffectHelper.StopEffectEvent(entity, CName.new("thrusters"))
	end
	return true
end

--- Toggle helicopter thruster ON/OFF.
---@param on boolean
---@return boolean
function AV:ToggleHeliThruster(on)
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end
	if self.engine_obj.flight_mode ~= Def.FlightMode.Helicopter then
		return false
	end

	if on then
		GameObjectEffectHelper.StartEffectEvent(entity, CName.new("thruster"))
	else
		GameObjectEffectHelper.StopEffectEvent(entity, CName.new("thruster"))
	end
	return true
end

--- Set destroy appearance.
---@return boolean
function AV:SetDestroyAppearance()
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set destroy appearance")
		return false
	end

	if self.destroy_app == nil then
		self.log_obj:Record(LogLevel.Warning, "No destroy appearance")
		return false
	end

	self:ChangeAppearance(self.destroy_app)
	return true
end

--- Change engine status.
---@param on boolean
---@return boolean
function AV:TurnEngineOn(on)
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change engine status")
		return false
	end
	entity:TurnEngineOn(on)
	return true
end

--- Get Player Around Direction (for spawn position)
---@param angle number
function AV:GetPlayerAroundDirection(angle)
    return Vector4.RotateAxis(Game.GetPlayer():GetWorldForward(), Vector4.new(0, 0, 1, 0), angle / 180.0 * Pi())
end

--- Get Spawn Position Vector
---@param distance number
---@param angle number
---@return Vector4
function AV:GetSpawnPosition(distance, angle)
    local pos = Game.GetPlayer():GetWorldPosition()
    local heading = self:GetPlayerAroundDirection(angle)
    return Vector4.new(pos.x + (heading.x * distance), pos.y + (heading.y * distance), pos.z + heading.z, pos.w + heading.w)
end

--- Get Spawn Orientation Quaternion
---@param angle number
---@return Quaternion
function AV:GetSpawnOrientation(angle)
    return EulerAngles.ToQuat(Vector4.ToRotation(self:GetPlayerAroundDirection(angle)))
end

--- Check Player in Exception Area
---@param position Vector4
---@return boolean is_in_area If or not in exception area
---@return string tag Tag
---@return number z max height of exception area
function AV:IsInExceptionArea(position)
    for _, area in ipairs(self.autopilot_exception_area_list) do
        if position.x >= area.min_x and position.x <= area.max_x and position.y >= area.min_y and position.y <= area.max_y and position.z >= area.min_z and position.z <= area.max_z then
            return true, area.tag, area.max_z
        end
    end
    return false, "None", 0
end

--- Get Exit Position Vector
---@return Vector4
function AV:GetExitPosition()
    local basic_vector = self:GetPosition()
    return self:ChangeWorldCordinate(basic_vector, {self.exit_point})[1]
end

--- Check Player in Entry Area
---@return boolean
function AV:IsPlayerInEntryArea()
    local basic_vector = self:GetPosition()
    if basic_vector:IsZero() then
        return false
    end
    local world_entry_point = self:ChangeWorldCordinate(basic_vector, {self.entry_point})
    local player = Game.GetPlayer()
    if player == nil then
        return false
    end
    local player_pos = player:GetWorldPosition()
    if player_pos == nil then
        return false
    end
    local player_vector = {x = player_pos.x, y = player_pos.y, z = player_pos.z}

    local norm = math.sqrt((player_vector.x - world_entry_point[1].x) * (player_vector.x - world_entry_point[1].x) + (player_vector.y - world_entry_point[1].y) * (player_vector.y - world_entry_point[1].y) + (player_vector.z - world_entry_point[1].z) * (player_vector.z - world_entry_point[1].z))
    if norm <= self.entry_area_radius then
        return true
    else
        return false
    end
end

--- Change World Cordinate
---@param basic_vector Vector4
---@param point_list Vector4[]
---@return Vector4[]
function AV:ChangeWorldCordinate(basic_vector, point_list)
    local quaternion = self:GetQuaternion()
    local result_list = {}
    for i, corner in ipairs(point_list) do
        local rotated = Utils:RotateVectorByQuaternion(corner, quaternion)
        result_list[i] = {x = rotated.x + basic_vector.x, y = rotated.y + basic_vector.y, z = rotated.z + basic_vector.z}
    end
    return result_list
end

--- This function returns collision status.
---@return boolean
function AV:IsCollision()
    return self.engine_obj:IsOnGround()
end

--- Check Wall
---@param dir_vec Vector4 direction vector
---@param distance number distance
---@param angle number angle
---@param swing_direction string "Vertical" or "Horizontal"
---@param is_check_exception_area boolean
---@return boolean
---@return Vector4
function AV:IsWall(dir_vec, distance, angle, swing_direction, is_check_exception_area)
    local dir_base_vec = Vector4.Normalize(dir_vec)
    local up_vec = Vector4.new(0, 0, 1, 1)
    local right_vec = Vector4.Cross(dir_base_vec, up_vec)
    local search_vec
    if swing_direction == "Vertical" then
        search_vec = Vector4.RotateAxis(dir_base_vec, right_vec, angle / 180 * Pi())
    else
        search_vec = Vector4.RotateAxis(dir_base_vec, up_vec, angle / 180 * Pi())
    end
    for _, i in ipairs({0, self.autopilot_prevention_length, -self.autopilot_prevention_length}) do
        for _, j in ipairs({0, self.autopilot_prevention_length, -self.autopilot_prevention_length}) do
            for _, k in ipairs({0, self.autopilot_prevention_length, -self.autopilot_prevention_length}) do
                local current_position = self:GetPosition()
                current_position.x = current_position.x + dir_base_vec.x * i + right_vec.x * j + up_vec.x * k
                current_position.y = current_position.y + dir_base_vec.y * i + right_vec.y * j + up_vec.y * k
                current_position.z = current_position.z + dir_base_vec.z * i + right_vec.z * j + up_vec.z * k
                for _, filter in ipairs(self.weak_collision_filters) do
                    local is_success, _ = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_position, Vector4.new(current_position.x + distance * search_vec.x, current_position.y + distance * search_vec.y, current_position.z + distance * search_vec.z, 1.0), filter, false, false)
                    if is_success then
                        self.log_obj:Record(LogLevel.Trace, "Wall Detected: " .. filter .. " " .. i .. " " .. j .. " " .. k)
                        return true, search_vec
                    end
                end
                -- check exception area
                if is_check_exception_area then
                    local is_exception, tag, _ = self:IsInExceptionArea(Vector4.new(current_position.x + distance * search_vec.x, current_position.y + distance * search_vec.y, current_position.z + distance * search_vec.z, 1.0))
                    if is_exception then
                        self.log_obj:Record(LogLevel.Trace, "Exception Area Detected: " .. tag)
                        return true, search_vec
                    end
                end
            end
        end
    end
    -- check exception area here
    if is_check_exception_area then
        local is_exception, tag, _ = self:IsInExceptionArea(self:GetPosition())
        if is_exception then
            self.log_obj:Record(LogLevel.Trace, "Here is Exception Area: " .. tag)
            return true, search_vec
        end
    end

    return false, search_vec
end

return AV