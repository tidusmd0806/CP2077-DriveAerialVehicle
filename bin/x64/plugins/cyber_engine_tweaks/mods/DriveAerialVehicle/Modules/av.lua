local Camera = require("Modules/camera.lua")
local Position = require("Modules/position.lua")
local Def = require("Tools/def.lua")
local Engine = require("Modules/engine.lua")
local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local AV = {}
AV.__index = AV

function AV:New(all_models)
	local obj = {}
	obj.position_obj = Position:New(all_models)
	obj.engine_obj = Engine:New(obj.position_obj, all_models)
	obj.camera_obj = Camera:New(obj.position_obj, all_models)
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "AV")

	obj.all_models = all_models
	obj.spawn_distance = 5.5
	obj.spawn_high = 50
	obj.spawn_wait_count = 150
	obj.down_time_count = 300
	obj.land_offset = - 1.0

	-- set default parameters
	obj.entity_id = nil
	obj.vehicle_model_tweakdb_id = nil
	obj.vehicle_model_type = nil
	obj.is_player_in = false
	obj.is_default_mount = nil
	obj.active_seat = nil
	obj.active_door = nil

	obj.collision_aboidance_max_step = 50
	obj.collision_aboidance_pre_step = 1000
	obj.collision_aboidance_multiple_rate = 10
	obj.error_range = 0.5
	obj.turn_time = 2.0

	-- This parameter is used for collision when player done not operate AV
	obj.is_collision = false
	obj.max_collision_count = obj.position_obj.collision_max_count
	obj.colison_count = 0
	obj.door_open_time = 1.5
	obj.is_landed = false
	obj.is_leaving = false
	obj.is_auto_pilot = false
	obj.is_unmounting = false

	obj.destination_position = {x = 0, y = 0, z = 0}
	obj.auto_pilot_speed = 1

	return setmetatable(obj, self)
end

function AV:Init()
	local index = DAV.model_index
	local type_number = DAV.model_type_index
	self.vehicle_model_tweakdb_id = self.all_models[index].tweakdb_id
	self.vehicle_model_type = self.all_models[index].type[type_number]
	self.is_default_mount = self.all_models[index].is_default_mount
	self.active_seat = self.all_models[index].actual_allocated_seat
	self.active_door = self.all_models[index].actual_allocated_door
	self.engine_obj:SetModel(index)
	self.position_obj:SetModel(index)
end

function AV:IsPlayerIn()
	return self.is_player_in
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

	local entity_system = Game.GetDynamicEntitySystem()
	local entity_spec = DynamicEntitySpec.new()

	entity_spec.recordID = self.vehicle_model_tweakdb_id
	entity_spec.appearanceName = self.vehicle_model_type
	entity_spec.position = position
	entity_spec.orientation = angle
	entity_spec.persistState = false
	self.entity_id = entity_system:CreateEntity(entity_spec)

	-- set entity id to position object
	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			self.position_obj:SetEntity(entity)
			self.engine_obj:Init()
			DAV.Cron.Halt(timer)
		end
	end)

	return true
end

function AV:SpawnToSky()
	local position = self.position_obj:GetSpawnPosition(self.spawn_distance, 0.0)
	position.z = position.z + self.spawn_high
	local angle = self.position_obj:GetSpawnOrientation(90.0)
	self:Spawn(position, angle)
	DAV.Cron.Every(0.01, { tick = 1 }, function(timer)
		timer.tick = timer.tick + 1
		if timer.tick == self.spawn_wait_count then
			self:LockDoor()
		elseif timer.tick > self.spawn_wait_count then
			if not self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset ,self.spawn_high , timer.tick - self.spawn_wait_count + 1), 0.0, 0.0, 0.0) then
				self.is_landed = true
				DAV.Cron.Halt(timer)
			elseif timer.tick >= self.spawn_wait_count + self.down_time_count then
				self.is_landed = true
				DAV.Cron.Halt(timer)
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
	DAV.Cron.Every(0.01, { tick = 1 }, function(timer)
		timer.tick = timer.tick + 1

		if timer.tick > self.spawn_wait_count then
			self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset ,self.spawn_high , timer.tick - self.spawn_wait_count + 1 + self.down_time_count), 0.0, 0.0, 0.0)
			if timer.tick >= self.spawn_wait_count + self.down_time_count then
				self:Despawn()
				DAV.Cron.Halt(timer)
			end
		end
	end)
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

function AV:ChangeDoorState(door_state)

	local change_counter = 0

	for _, door_name in ipairs(self.active_door) do
		local door_number = EVehicleDoor.seat_front_left
		if door_name == "seat_front_left" then
			door_number = EVehicleDoor.seat_front_left
		elseif door_name == "seat_front_right" then
			door_number = EVehicleDoor.seat_front_right
		elseif door_name == "seat_back_left" then
			door_number = EVehicleDoor.seat_back_left
		elseif door_name == "seat_back_right" then
			door_number = EVehicleDoor.seat_back_right
		elseif door_name == "trunk" then
			door_number = EVehicleDoor.trunk
		elseif door_name == "hood" then
			door_number = EVehicleDoor.hood
		end

		if self.entity_id == nil then
			self.log_obj:Record(LogLevel.Warning, "No entity to change door state")
			return nil
		end
		local entity = Game.FindEntityByID(self.entity_id)
		local vehicle_ps = entity:GetVehiclePS()
		local state = vehicle_ps:GetDoorState(door_number).value

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
		if can_change then
			change_counter = change_counter + 1
			door_event.slotID = CName.new(door_name)
			door_event.forceScene = false
			vehicle_ps:QueuePSEvent(vehicle_ps, door_event)
		end
	end
	return change_counter
end

function AV:Mount()

	self.is_landed = false
	self.camera_obj:SetPerspective()

	local seat_number = DAV.seat_index

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

	-- return position near mounted vehicle	
	DAV.Cron.Every(0.01, {tick = 1}, function(timer)
		local entity = player:GetMountedVehicle()
		if entity ~= nil then
			DAV.Cron.After(1.5, function()
				self.is_player_in = true
			end)
			DAV.Cron.Halt(timer)
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

	local seat_number = DAV.seat_index
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

	-- if all door are open, wait time is short
	local open_door_wait = self.door_open_time
	if self:ChangeDoorState(Def.DoorOperation.Open) == 0 then
		open_door_wait = 0.1
	end

	DAV.Cron.After(open_door_wait, function()

		Game.GetMountingFacility():Unmount(mount_event)

		-- set entity id to position object
		DAV.Cron.Every(0.01, {tick = 1}, function(timer)
			local entity = Game.FindEntityByID(self.entity_id)
			if entity ~= nil then
				local angle = entity:GetWorldOrientation():ToEulerAngles()
				angle.yaw = angle.yaw + 90
				local position = self.position_obj:GetExitPosition()
				Game.GetTeleportationFacility():Teleport(player, Vector4.new(position.x, position.y, position.z, 1.0), angle)
				self.is_player_in = false
				self.is_ummounting = false
				DAV.Cron.Halt(timer)
			end
		end)
	end)

	return true
end

function AV:Move(x, y, z, roll, pitch, yaw)

	if not self.position_obj:SetNextPosition(x, y, z, roll, pitch, yaw) then
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
		local x, y, z, roll, pitch, yaw = self.engine_obj:GetNextPosition(action_command)
		x_total = x_total + x
		y_total = y_total + y
		z_total = z_total + z
		roll_total = roll_total + roll
		pitch_total = pitch_total + pitch
		yaw_total = yaw_total + yaw
	end
	if #action_commands == 0 then
		self.log_obj:Record(LogLevel.Critical, "Division by Zero")
		return false
	end

	self.is_collision = false

	x_total = x_total / #action_commands
	y_total = y_total / #action_commands
	z_total = z_total / #action_commands
	roll_total = roll_total / #action_commands
	pitch_total = pitch_total / #action_commands
	yaw_total = yaw_total / #action_commands

	if x_total == 0 and y_total == 0 and z_total == 0 and roll_total == 0 and pitch_total == 0 and yaw_total == 0 then
		self.log_obj:Record(LogLevel.Debug, "No operation")
		return false
	end

	local res = self.position_obj:SetNextPosition(x_total, y_total, z_total, roll_total, pitch_total, yaw_total)

	if res == Def.TeleportResult.Collision then
		self.engine_obj:SetSpeedAfterRebound()
		self.is_collision = true
		self.colison_count = self.colison_count + 1
		if self.colison_count > self.max_collision_count then
			self.log_obj:Record(LogLevel.Info, "Collision Count Over. Engine Reset")
			self.colison_count = 0
		end
		return false
	elseif res == Def.TeleportResult.AvoidStack then
		self.log_obj:Record(LogLevel.Info, "Avoid Stack")
		self.colison_count = 0
		return false
	elseif res == Def.TeleportResult.Error then
		self.log_obj:Record(LogLevel.Error, "Teleport Error")
		self.colison_count = 0
		return false
	end

	self.colison_count = 0

	return true
end

function AV:SetDestination(position)
	self.destination_position.x = position.x
	self.destination_position.y = position.y
	self.destination_position.z = position.z
end

function AV:AutoPilot()
	self.is_auto_pilot = true
	local current_position = self.position_obj:GetPosition()
	local direction_vector = {x = self.destination_position.x - current_position.x, y = self.destination_position.y - current_position.y, z = 0}
	self:AutoLeaving(direction_vector, current_position.z)

	DAV.Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1

		if self.is_leaving then
			return
		end

		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			DAV.Cron.Halt(timer)
			return
		end

		current_position = self.position_obj:GetPosition()
		direction_vector = {x = self.destination_position.x - current_position.x, y = self.destination_position.y - current_position.y, z = 0}

		local direction_vector_norm = math.sqrt(direction_vector.x * direction_vector.x + direction_vector.y * direction_vector.y)
		if direction_vector_norm < self.error_range then
			self.log_obj:Record(LogLevel.Info, "Arrived at destination")
			self:AutoLanding(current_position.z)
			DAV.Cron.Halt(timer)
			return
		end
		local next_prediction_position = {x = current_position.x + self.auto_pilot_speed * self.collision_aboidance_pre_step * direction_vector.x / direction_vector_norm,
		                                  y = current_position.y + self.auto_pilot_speed * self.collision_aboidance_pre_step * direction_vector.y / direction_vector_norm,
										  z = current_position.z + self.auto_pilot_speed * self.collision_aboidance_pre_step * direction_vector.z / direction_vector_norm}
		for step = 1, self.collision_aboidance_max_step do
			if self.position_obj:CheckCollision(current_position, next_prediction_position) then
				next_prediction_position.z = next_prediction_position.z * self.collision_aboidance_multiple_rate
			elseif step == self.collision_aboidance_max_step then
				self.log_obj:Record(LogLevel.Error, "Collision Aboidance Error")
				DAV.Cron.Halt(timer)
				self.is_auto_pilot = false
				return
			else
				break
			end
		end
		local fix_direction_vector = {x = next_prediction_position.x - current_position.x,
		                              y = next_prediction_position.y - current_position.y,
									  z = next_prediction_position.z - current_position.z}
		local fix_direction_vector_norm = math.sqrt(fix_direction_vector.x * fix_direction_vector.x +
		                                            fix_direction_vector.y * fix_direction_vector.y +
													fix_direction_vector.z * fix_direction_vector.z)
		local next_positon = {x = self.auto_pilot_speed * fix_direction_vector.x / fix_direction_vector_norm,
							  y = self.auto_pilot_speed * fix_direction_vector.y / fix_direction_vector_norm,
							  z = self.auto_pilot_speed * fix_direction_vector.z / fix_direction_vector_norm}
		if not self:Move(next_positon.x, next_positon.y, next_positon.z, 0.0, 0.0, 0.0) then
			self.log_obj:Record(LogLevel.Error, "AutoPilot Move Error")
			DAV.Cron.Halt(timer)
			self.is_auto_pilot = false
			return
		end
	end)
end

function AV:AutoLeaving(dist_vector, hight)
	self.is_leaving = true
	local current_direction = self.position_obj:GetForward()
	current_direction.z = 0
	current_direction = Utils:Normalize(current_direction)
    local target_direction = Utils:Normalize(dist_vector)
    local angle_difference = math.acos(current_direction.x * target_direction.x + current_direction.y * target_direction.y + current_direction.z * target_direction.z)
	DAV.Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, hight, self.spawn_high, timer.tick + self.down_time_count + 1),
																0.0, 0.0, 0.0)
		if timer.tick >= self.down_time_count then
			DAV.Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
				timer.tick = timer.tick + 1
				if not self.is_auto_pilot then
					self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
					DAV.Cron.Halt(timer)
					return
				end
				local turn_angle_degrees = -1 * angle_difference * 180 / Pi() * (DAV.time_resolution / self.turn_time )
				self:Move(0.0, 0.0, 0.0, 0.0, 0.0, turn_angle_degrees)
				if timer.tick >= self.turn_time / DAV.time_resolution then
					self.is_leaving = false
					DAV.Cron.Halt(timer)
				end
			end)
			DAV.Cron.Halt(timer)
		end
	end)
end

function AV:AutoLanding(hight)
	DAV.Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			DAV.Cron.Halt(timer)
			return
		end
		if not self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset, hight, timer.tick + 1),
																	   0.0, 0.0, 0.0) then
			self.is_landed = true
			self.is_auto_pilot = false
			DAV.Cron.Halt(timer)
		elseif timer.tick >= self.down_time_count then
			self.is_landed = true
			self.is_auto_pilot = false
			DAV.Cron.Halt(timer)
		end
	end)
end

function AV:InterruptAutoPilot()
	self.is_auto_pilot = false
end

return AV