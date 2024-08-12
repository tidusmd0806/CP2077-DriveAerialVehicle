local Camera = require("Modules/camera.lua")
local Position = require("Modules/position.lua")
local Engine = require("Modules/engine.lua")
local Radio = require("Modules/radio.lua")
local Utils = require("Tools/utils.lua")
local AV = {}
AV.__index = AV

function AV:New(all_models)
	---instance---
	local obj = {}
	obj.position_obj = Position:New(all_models)
	obj.engine_obj = Engine:New(obj.position_obj, all_models)
	obj.camera_obj = Camera:New(obj.position_obj, all_models)
	obj.radio_obj = Radio:New(obj.position_obj)
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "AV")
	---static---
	obj.all_models = all_models
	-- summon
	obj.spawn_distance = 5.5
	obj.spawn_high = 3
	obj.spawn_wait_count = 150
	obj.down_time_count = 30
	obj.land_offset = -1.0
	obj.door_open_time = 1.0
	-- collision
	obj.max_collision_count = obj.position_obj.collision_max_count
	-- autopiolt
	obj.profile_path = "Data/autopilot_profile.json"
	obj.error_range = 3
	obj.max_stack_count = 200
	obj.min_stack_count = 10
	obj.limit_stack_count = 500
	-- for spawning vehicle and pedistrian
	obj.freeze_stage_num = 10
	---dynamic---
	-- summon
	obj.entity_id = nil
	obj.vehicle_model_tweakdb_id = nil
	obj.vehicle_model_type = nil
	obj.active_seat = nil
	obj.active_door = nil
	obj.seat_index = 1
	obj.is_crystal_dome = false
	-- collision
	obj.is_collision = false
	obj.colison_count = 0
	-- av status
	obj.is_player_in = false
	obj.is_landed = false
	obj.is_leaving = false
	obj.is_auto_pilot = false
	obj.is_unmounting = false
	obj.is_spawning = false
	-- autopiolt
	obj.mappin_destination_position = Vector4.new(0, 0, 0, 1)
	obj.favorite_destination_position = Vector4.new(0, 0, 0, 1)
	obj.auto_pilot_info = {location = "Not Registered", type = "Not Registered", dist_pos = {x = 0, y = 0, z = 0}, start_pos = {x = 0, y = 0, z = 0}}
	obj.auto_pilot_speed = 1
	obj.avoidance_range = 5
	obj.max_avoidance_speed = 10
	obj.sensing_constant = 0.001
	obj.autopilot_turn_speed = 0.8
	obj.autopilot_land_offset = -1.0
	obj.autopilot_down_time_count = 100
	obj.autopilot_leaving_hight = 100
	obj.is_auto_avoidance = false
	obj.is_failture_auto_pilot = false
	-- for spawning vehicle and pedistrian
	obj.freeze_count = 0
	obj.max_freeze_count = 30
	obj.min_freeze_count = 8
	obj.max_speed_for_freezing = 100
	return setmetatable(obj, self)
end

function AV:Init()

	local index = DAV.model_index
	local type_number = DAV.model_type_index
	self.vehicle_model_tweakdb_id = self.all_models[index].tweakdb_id
	self.vehicle_model_type = self.all_models[index].type[type_number]
	self.active_seat = self.all_models[index].actual_allocated_seat
	self.active_door = self.all_models[index].actual_allocated_door
	self.engine_obj:SetModel(index)
	self.position_obj:SetModel(index)

	-- read autopilot profile
	local autopilot_profile = Utils:ReadJson(self.profile_path)
	local speed_level = DAV.user_setting_table.autopilot_speed_level
	self.auto_pilot_speed = autopilot_profile[speed_level].speed
	self.avoidance_range = autopilot_profile[speed_level].avoidance_range
	self.max_avoidance_speed = autopilot_profile[speed_level].max_avoidance_speed
	self.sensing_constant = autopilot_profile[speed_level].sensing_constant
	self.autopilot_turn_speed = autopilot_profile[speed_level].turn_speed
	self.autopilot_land_offset = autopilot_profile[speed_level].land_offset
	self.autopilot_down_time_count = autopilot_profile[speed_level].down_time_count
	self.autopilot_leaving_hight = autopilot_profile[speed_level].leaving_hight
	self.position_obj:SetSensorPairVectorNum(autopilot_profile[speed_level].sensor_pair_vector_num)
	self.position_obj:SetJudgedStackLength(autopilot_profile[speed_level].judged_stack_length)

end

function AV:IsPlayerIn()
	return self.is_player_in
end

function AV:IsSpawning()
	return self.is_spawning
end

function AV:IsDespawned()
	if self.entity_id == nil then
		return true
	else
		return false
	end
end

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
			self.position_obj:SetEntity(entity)
			self.engine_obj:Init(self.entity_id)
			Cron.Halt(timer)
		end
	end)

	return true

end

function AV:SpawnToSky()

	local position = self.position_obj:GetSpawnPosition(self.spawn_distance, 0.0)
	position.z = position.z + self.spawn_high
	local angle = self.position_obj:GetSpawnOrientation(90.0)
	self:Spawn(position, angle)
	Cron.Every(0.01, { tick = 1 }, function(timer)
		if not DAV.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
			timer.tick = timer.tick + 1
			if timer.tick == self.spawn_wait_count then
				self:LockDoor()
			elseif timer.tick > self.spawn_wait_count then
				if not self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset ,self.spawn_high , timer.tick - self.spawn_wait_count + 1), 0.0, 0.0, 0.0) then
					self.is_landed = true
					Cron.Halt(timer)
				elseif timer.tick >= self.spawn_wait_count + self.down_time_count then
					self.is_landed = true
					self.position_obj:SetDestinationHeight(self.position_obj:GetPosition().z)
					Cron.Halt(timer)
				end
			end
		end
	end)

end

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

function AV:DespawnFromGround()

	Cron.Every(0.01, { tick = 1 }, function(timer)
		if not DAV.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
			timer.tick = timer.tick + 1
			if timer.tick > self.spawn_wait_count then
				self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset ,self.spawn_high , timer.tick - self.spawn_wait_count + 1 + self.down_time_count), 0.0, 0.0, 0.0)
				if timer.tick >= self.spawn_wait_count + self.down_time_count then
					self:Despawn()
					Cron.Halt(timer)
				end
			end
		end
	end)

end

function AV:ToggleCrystalDome()

	local entity = Game.FindEntityByID(self.entity_id)
	local effect_name
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change crystal dome")
		return false
	elseif self.vehicle_model_tweakdb_id ~= "Vehicle.av_rayfield_excalibur_dav"
			and self.vehicle_model_tweakdb_id ~= "Vehicle.av_militech_manticore_dav" then
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

function AV:LockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:QuestLockAllVehDoors()
	return true
end

---@param e_veh_door EVehicleDoor
---@return string
function AV:GetDoorState(e_veh_door)

	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to get door state")
		return nil
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	return vehicle_ps:GetDoorState(e_veh_door).value

end

---@param door_state Def.DoorOperation
---@return number
function AV:ChangeDoorState(door_state)

	local change_counter = 0

	for _, door_name in ipairs(self.active_door) do
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

		local state = self:GetDoorState(e_veh_door)

		local door_event = nil
		local can_change = true
		if state == "Closed" then
			if door_state == Def.DoorOperation.Close then
				can_change = false
			end
			door_event = VehicleDoorOpen.new()
		elseif state == "Open" then
			if door_state == Def.DoorOperation.Open then
				can_change = false
			end
			door_event = VehicleDoorClose.new()
		else
			self.log_obj:Record(LogLevel.Error, "Door state is not valid : " .. state)
			return nil
		end

		if self.entity_id == nil then
			self.log_obj:Record(LogLevel.Warning, "No entity to get door state")
			return nil
		end
		local entity = Game.FindEntityByID(self.entity_id)
		local vehicle_ps = entity:GetVehiclePS()
		if can_change then
			change_counter = change_counter + 1
			door_event.slotID = CName.new(door_name)
			door_event.forceScene = false
			vehicle_ps:QueuePSEvent(vehicle_ps, door_event)
		end
	end
	return change_counter

end

function AV:ControlCrystalDome()

	local e_veh_door = EVehicleDoor.seat_front_left
	if not self.is_crystal_dome then
		Cron.Every(1, {tick = 1}, function(timer)
			if self:GetDoorState(e_veh_door) == "Closed" then
				if self.vehicle_model_tweakdb_id == "Vehicle.av_rayfield_excalibur_dav" then
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


	local data = NewObject('handle:gameMountEventData')
	data.isInstant = false
	data.slotName = seat
	data.mountParentEntityId = ent_id
	data.entryAnimName = "stand__2h_on_sides__01__to__sit_couch__AV_excalibur__01__turn270__getting_into_AV__01"


	local slot_id = NewObject('gamemountingMountingSlotId')
	slot_id.id = seat

	local mounting_info = NewObject('gamemountingMountingInfo')
	mounting_info.childId = player:GetEntityID()
	mounting_info.parentId = ent_id
	mounting_info.slotId = slot_id

	local mounting_request = NewObject('handle:gamemountingMountingRequest')
	mounting_request.lowLevelMountingInfo = mounting_info
	mounting_request.mountData = data

	Game.GetMountingFacility():Mount(mounting_request)

	self.position_obj:ChangePosition()

	if not self.is_crystal_dome then
		-- self:ControlCrystalDome()
	end

	-- return position near mounted vehicle	
	Cron.Every(0.01, {tick = 1}, function(timer)
		local entity = player:GetMountedVehicle()
		if entity ~= nil then
			Cron.After(1.5, function()
				self.is_player_in = true
			end)
			Cron.Halt(timer)
		end
	end)

	return true

end

function AV:Unmount()

	if self.is_ummounting then
		return false
	end

	self.is_ummounting = true

	self.camera_obj:ResetPerspective()

	local seat_number = self.seat_index
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to unmount")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local player = Game.GetPlayer()
	local ent_id = entity:GetEntityID()
	local seat = self.active_seat[seat_number]

	local data = NewObject('handle:gameMountEventData')
	data.isInstant = true
	data.slotName = seat
	data.mountParentEntityId = ent_id
	data.entryAnimName = "forcedTransition"

	local slotID = NewObject('gamemountingMountingSlotId')
	slotID.id = seat

	local mounting_info = NewObject('gamemountingMountingInfo')
	mounting_info.childId = player:GetEntityID()
	mounting_info.parentId = ent_id
	mounting_info.slotId = slotID

	local mount_event = NewObject('handle:gamemountingUnmountingRequest')
	mount_event.lowLevelMountingInfo = mounting_info
	mount_event.mountData = data

	if self.is_crystal_dome then
		self:ControlCrystalDome()
	end

	-- if all door are open, wait time is short
	local open_door_wait = self.door_open_time
	if self:ChangeDoorState(Def.DoorOperation.Open) == 0 then
		open_door_wait = 0.1
	end

	Cron.After(open_door_wait, function()

		Game.GetMountingFacility():Unmount(mount_event)

		-- set entity id to position object
		Cron.Every(0.01, {tick = 1}, function(timer)
			local entity = Game.FindEntityByID(self.entity_id)
			if entity ~= nil then
				local angle = entity:GetWorldOrientation():ToEulerAngles()
				angle.yaw = angle.yaw + 90
				local position = self.position_obj:GetExitPosition()
				Game.GetTeleportationFacility():Teleport(player, Vector4.new(position.x, position.y, position.z, 1.0), angle)
				self.is_player_in = false
				self.is_ummounting = false
				Cron.Halt(timer)
			end
		end)
	end)

	return true
end

function AV:Move(x, y, z, roll, pitch, yaw)

	if not self.position_obj:SetNextPosition(x, y, z, roll, pitch, yaw, false) then
		return false
	end

	return true

end

function AV:Operate(action_commands)

	local x_total, y_total, z_total, roll_total, pitch_total, yaw_total = 0, 0, 0, 0, 0, 0
	self.log_obj:Record(LogLevel.Debug, "Operation Count:" .. #action_commands)
	for _, action_command in ipairs(action_commands) do
		if action_command >= Def.ActionList.Enter then
			self.log_obj:Record(LogLevel.Critical, "Invalid Event Command:" .. action_command)
			return false
		end
		-- local x, y, z, roll, pitch, yaw = self.engine_obj:GetNextPosition(action_command)
		self.engine_obj:SetVelocity(action_command)
		-- x_total = x_total + x
		-- y_total = y_total + y
		-- z_total = z_total + z
		-- roll_total = roll_total + roll
		-- pitch_total = pitch_total + pitch
		-- yaw_total = yaw_total + yaw
	end
	if #action_commands == 0 then
		self.log_obj:Record(LogLevel.Critical, "Division by Zero")
		return false
	end

	-- self.is_collision = false

	-- x_total = x_total / #action_commands
	-- y_total = y_total / #action_commands
	-- z_total = z_total / #action_commands
	-- roll_total = roll_total / #action_commands
	-- pitch_total = pitch_total / #action_commands
	-- yaw_total = yaw_total / #action_commands

	-- if x_total == 0 and y_total == 0 and z_total == 0 and roll_total == 0 and pitch_total == 0 and yaw_total == 0 then
	-- 	self.log_obj:Record(LogLevel.Debug, "No operation")
	-- 	return false
	-- end

	-- local speed_count = self.max_freeze_count
	-- local level_speed_unit = self.max_speed_for_freezing / self.freeze_stage_num
	-- local speed_count_unit = math.ceil((self.max_freeze_count - self.min_freeze_count) / self.freeze_stage_num)
	-- for level = 1, self.freeze_stage_num do
	-- 	if self.engine_obj:GetSpeed() < level_speed_unit * level then
	-- 		speed_count = self.min_freeze_count + speed_count_unit * (level - 1)
	-- 		break
	-- 	end
	-- end

	-- local is_freeze = false
	-- -- Freeze for spawning vehicle and pedistrian
	-- if self.freeze_count < 1 and self:IsEnableFreeze() then
	-- 	self.freeze_count = self.freeze_count + 1
	-- 	is_freeze = true
	-- elseif self.freeze_count >= speed_count then
	-- 	self.freeze_count = 0
	-- elseif self.freeze_count >= 1 then
	-- 	self.freeze_count = self.freeze_count + 1
	-- end

	-- if DAV.user_setting_table.is_disable_spinner_roll_tilt then
	-- 	roll_total = 0
	-- end

	-- local res = self.position_obj:SetNextPosition(x_total, y_total, z_total, roll_total, pitch_total, yaw_total, is_freeze)

	-- if res == Def.TeleportResult.Collision then
	-- 	self.engine_obj:SetSpeedAfterRebound()
	-- 	self.is_collision = true
	-- 	self.colison_count = self.colison_count + 1
	-- 	if self.colison_count > self.max_collision_count then
	-- 		self.log_obj:Record(LogLevel.Info, "Collision Count Over. Engine Reset")
	-- 		self.colison_count = 0
	-- 	end
	-- 	return false
	-- elseif res == Def.TeleportResult.AvoidStack then
	-- 	self.log_obj:Record(LogLevel.Info, "Avoid Stack")
	-- 	self.colison_count = 0
	-- 	return false
	-- elseif res == Def.TeleportResult.Error then
	-- 	self.log_obj:Record(LogLevel.Error, "Teleport Error")
	-- 	self.colison_count = 0
	-- 	return false
	-- end

	-- self.colison_count = 0

	return true

end

function AV:IsEnableFreeze()

    if not DAV.user_setting_table.is_enable_community_spawn then
        return false
    end

    if self.engine_obj:GetSpeed() < self.max_speed_for_freezing then
        return true
    else
        return false
    end

end

---@param position Vector4
function AV:SetMappinDestination(position)
	self.mappin_destination_position = position
end

---@param position Vector4
function AV:SetFavoriteDestination(position)
	self.favorite_destination_position = position
end

---@param destination_position Vector4
---@return boolean
function AV:SetAutoPilotInfo(destination_position)

	local x, y, z = destination_position.x, destination_position.y, destination_position.z
	if x == 0 and y == 0 and z == 0 then
		self.log_obj:Record(LogLevel.Warning, "Destination is not set")
		self.auto_pilot_info.location = "Not Registered"
		self.auto_pilot_info.type = "Not Registered"
		return false
	end

	self.auto_pilot_info.dist_pos = destination_position
	self.auto_pilot_info.start_pos = self.position_obj:GetPosition()

	if DAV.core_obj.is_custom_mappin then
		local dist_near_ft_index = DAV.core_obj:GetFTIndexNearbyMappin()
		local dist_district_list = DAV.core_obj:GetNearbyDistrictList(dist_near_ft_index)
		self.auto_pilot_info.location = ""
		if dist_district_list ~= nil then
			for index, district in ipairs(dist_district_list) do
				if index == 1 then
					self.auto_pilot_info.location = district
				else
					self.auto_pilot_info.location = self.auto_pilot_info.location .. "/" .. district
				end
			end
		end
		local nearby_location = DAV.core_obj:GetNearbyLocation(dist_near_ft_index)
		if nearby_location ~= nil then
			self.auto_pilot_info.location = self.auto_pilot_info.location .. "/" .. nearby_location
		end
		local nearby_distance = DAV.core_obj:GetFT2MappinDistance()
		self.auto_pilot_info.location = self.auto_pilot_info.location .. " [" .. tostring(math.floor(nearby_distance)) .. "m]"
		self.auto_pilot_info.type = "Custom Mappin"
	else
		for index = 1, #DAV.user_setting_table.favorite_location_list do
			if DAV.user_setting_table.favorite_location_list[index].is_selected then
				self.auto_pilot_info.location = DAV.user_setting_table.favorite_location_list[index].name
				break
			end
		end
		self.auto_pilot_info.type = "Favorite Location"
	end
	return true
end

---@return boolean
function AV:AutoPilot()

	self.is_auto_pilot = true
	local destination_position = Vector4.new(0, 0, 0, 1)
	if DAV.core_obj.is_custom_mappin then
		destination_position = self.mappin_destination_position
	else
		destination_position = self.favorite_destination_position
	end

	if not self:SetAutoPilotInfo(destination_position) then
		self.log_obj:Record(LogLevel.Warning, "AutoPilot Destination is not set")
		self.is_auto_pilot = false
		return false
	end

	local far_corner_distance = self.position_obj:GetFarCornerDistance()

	local current_position = self.position_obj:GetPosition()

	local direction_vector = Vector4.new(destination_position.x - current_position.x, destination_position.y - current_position.y, 0, 1)
	self:AutoLeaving(direction_vector)

	self.is_auto_avoidance = false

	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1

		if self.is_leaving or DAV.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
			return
		end

		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			Cron.Halt(timer)
			return
		end

		local stack_count = self.position_obj:CheckAutoPilotStackCount(destination_position)

		if stack_count > self.limit_stack_count then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Stack Over")
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end

		current_position = self.position_obj:GetPosition()

		local sum_vector = self.position_obj:CalculateVectorField(far_corner_distance, far_corner_distance + self.avoidance_range, self.max_avoidance_speed, self.sensing_constant)

		local sum_vector_norm = math.sqrt(sum_vector.x * sum_vector.x + sum_vector.y * sum_vector.y + sum_vector.z * sum_vector.z)
		if sum_vector_norm < 0.001 then
			self.is_auto_avoidance = false
		end

		direction_vector = Vector4.new(destination_position.x - current_position.x, destination_position.y - current_position.y, 0, 1)

		local direction_vector_norm = Vector4.Length(direction_vector)

		if direction_vector_norm < self.error_range then
			self.log_obj:Record(LogLevel.Info, "Arrived at destination")
			self:AutoLanding(current_position.z)
			Cron.Halt(timer)
			return
		end

		local auto_pilot_speed = self.auto_pilot_speed * (1 - sum_vector_norm / (self.max_avoidance_speed + 1))

		if stack_count > self.min_stack_count and stack_count <= self.max_stack_count then
			auto_pilot_speed = auto_pilot_speed * ((self.max_stack_count - stack_count) / self.max_stack_count)
		end

		local fix_direction_vector = Vector4.new(auto_pilot_speed * direction_vector.x / direction_vector_norm, auto_pilot_speed * direction_vector.y / direction_vector_norm, 0, 1)

		local next_positon = {x = fix_direction_vector.x + sum_vector.x, y = fix_direction_vector.y + sum_vector.y, z = sum_vector.z}

		if self.is_auto_avoidance then
			next_positon = {x = 0, y = 0, z = self.auto_pilot_speed}
		end

		local vehicle_angle = self.position_obj:GetForward()
		local vehicle_angle_norm = Vector4.Length(vehicle_angle)
		local yaw_vehicle = math.atan2(vehicle_angle.y / vehicle_angle_norm, vehicle_angle.x / vehicle_angle_norm) * 180 / Pi()
		local fix_direction_vector_norm = Vector4.Length(fix_direction_vector)
		local yaw_dist = math.atan2(fix_direction_vector.y / fix_direction_vector_norm, fix_direction_vector.x / fix_direction_vector_norm) * 180 / Pi()
		local yaw_diff = yaw_dist - yaw_vehicle
		local yaw_diff_half = yaw_diff * 0.1
		if math.abs(yaw_diff_half) < 0.5 then
			yaw_diff_half = yaw_diff
		end

		if not self:Move(next_positon.x, next_positon.y, next_positon.z, 0.0, 0.0, yaw_diff_half) then
			self.log_obj:Record(LogLevel.Error, "AutoPilot Move Error")
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end
		if stack_count > self.max_stack_count then
			self.is_auto_avoidance = true
		end
	end)
	return true

end

---@param dist_vector Vector4
function AV:AutoLeaving(dist_vector)

	self.is_leaving = true

	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			self.is_leaving = false
			Cron.Halt(timer)
			return
		end
		local angle = self.position_obj:GetEulerAngles()
		local current_position = self.position_obj:GetPosition()
		self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.autopilot_down_time_count, self.autopilot_land_offset, self.autopilot_leaving_hight - current_position.z, timer.tick + self.autopilot_down_time_count + 1), -angle.roll * 0.8, -angle.pitch * 0.8, 0.0)
		if timer.tick >= self.autopilot_down_time_count then
			Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
				timer.tick = timer.tick + 1
				if not self.is_auto_pilot then
					self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
					self:InterruptAutoPilot()
					self.is_leaving = false
					Cron.Halt(timer)
					return
				end

				local current_direction = self.position_obj:GetForward()
				current_direction.z = 0
				current_direction = Vector4.Normalize(current_direction)
				local target_direction = Vector4.Normalize(dist_vector)
				local sign = 1
				if current_direction.x * target_direction.y - current_direction.y * target_direction.x > 0 then
					sign = 1
				else
					sign = -1
				end

				if not self:Move(0.0, 0.0, 0.0, 0.0, 0.0, sign * self.autopilot_turn_speed) then
					self.is_leaving = false
					self:InterruptAutoPilot()
					Cron.Halt(timer)
				end
				local inner_product = current_direction.x * target_direction.x + current_direction.y * target_direction.y
				if inner_product > 0.99 then
					local angle_difference = math.acos(current_direction.x * target_direction.x + current_direction.y * target_direction.y + current_direction.z * target_direction.z)
					self:Move(0.0, 0.0, 0.0, 0.0, 0.0, sign * math.abs(angle_difference * 180 / Pi()))
					self.is_leaving = false
					Cron.Halt(timer)
				end
			end)
			Cron.Halt(timer)
		end
	end)
end

---@param hight number
function AV:AutoLanding(hight)
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end
		local down_time_count = hight / self.auto_pilot_speed
		if not self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(down_time_count, self.autopilot_land_offset, hight, timer.tick + 1), 0.0, 0.0, 0.0) then
			self.is_landed = true
			self:InterruptAutoPilot()
			Cron.Halt(timer)
		elseif timer.tick >= down_time_count then
			self.is_landed = true
			self:SeccessAutoPilot()
			Cron.Halt(timer)
		end
	end)
end

function AV:SeccessAutoPilot()

	self.is_auto_pilot = false
	self.is_failture_auto_pilot = false
	self.position_obj:ResetStackCount()
	DAV.core_obj:SetAutoPilotHistory()

end

function AV:InterruptAutoPilot()
	self.is_auto_pilot = false
	self.is_failture_auto_pilot = true
	self.position_obj:ResetStackCount()
end

function AV:IsFailedAutoPilot()
	local is_failture_auto_pilot = self.is_failture_auto_pilot
	self.is_failture_auto_pilot = false
	return is_failture_auto_pilot
end

return AV