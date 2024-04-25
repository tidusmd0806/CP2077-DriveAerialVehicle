local Camera = require("Modules/camera.lua")
local Position = require("Modules/position.lua")
local Engine = require("Modules/engine.lua")
-- local Log = require("Tools/log.lua")
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

	obj.collision_aboidance_max_step = 20
	obj.collision_aboidance_default_step = 500
	obj.error_range = 0.5
	obj.turn_speed = 0.5

	-- This parameter is used for collision when player done not operate AV
	obj.seat_index = 1
	obj.is_collision = false
	obj.max_collision_count = obj.position_obj.collision_max_count
	obj.colison_count = 0
	obj.door_open_time = 1.5
	obj.is_landed = false
	obj.is_leaving = false
	obj.is_auto_pilot = false
	obj.is_unmounting = false
	obj.is_spawning = false

	obj.destination_position = {x = 0, y = 0, z = 0}
	obj.auto_pilot_speed = 1
	obj.avoidance_range = 5
	obj.max_avoidance_speed = 10
	obj.sensing_constant = 0.001

	obj.is_auto_avoidance = false
	obj.limit_stack_count = 500
	obj.max_stack_count = 200
	obj.min_stack_count = 10
	obj.is_failture_auto_pilot = false

	obj.freeze_count = 0
	obj.x_total = 0
	obj.y_total = 0
	obj.z_total = 0
	obj.roll_total = 0
	obj.pitch_total = 0
	obj.yaw_total = 0
	obj.max_freeze_count = 50

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
	self.entity_id = entity_system:CreateEntity(entity_spec)

	-- set entity id to position object
	Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			self.is_spawning = false
			self.position_obj:SetEntity(entity)
			self.engine_obj:Init()
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
		timer.tick = timer.tick + 1
		if timer.tick == self.spawn_wait_count then
			self:LockDoor()
		elseif timer.tick > self.spawn_wait_count then
			if not self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset ,self.spawn_high , timer.tick - self.spawn_wait_count + 1), 0.0, 0.0, 0.0) then
				self.is_landed = true
				Cron.Halt(timer)
			elseif timer.tick >= self.spawn_wait_count + self.down_time_count then
				self.is_landed = true
				Cron.Halt(timer)
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
		timer.tick = timer.tick + 1

		if timer.tick > self.spawn_wait_count then
			self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset ,self.spawn_high , timer.tick - self.spawn_wait_count + 1 + self.down_time_count), 0.0, 0.0, 0.0)
			if timer.tick >= self.spawn_wait_count + self.down_time_count then
				self:Despawn()
				Cron.Halt(timer)
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

	x_total = x_total / #action_commands + self.x_total
	y_total = y_total / #action_commands + self.y_total
	z_total = z_total / #action_commands + self.z_total
	roll_total = roll_total / #action_commands + self.roll_total
	pitch_total = pitch_total / #action_commands + self.pitch_total
	yaw_total = yaw_total / #action_commands + self.yaw_total

	if x_total == 0 and y_total == 0 and z_total == 0 and roll_total == 0 and pitch_total == 0 and yaw_total == 0 then
		self.log_obj:Record(LogLevel.Debug, "No operation")
		return false
	end

	-- to freeze for spawning vehicle and pedistrian
	if self.freeze_count < 2 and DAV.core_obj:IsEnableFreeze() then
		self.freeze_count = self.freeze_count + 1
		self.x_total = x_total
		self.y_total = y_total
		self.z_total = z_total
		self.roll_total = roll_total
		self.pitch_total = pitch_total
		self.yaw_total = yaw_total
		return false
	elseif self.freeze_count >= self.max_freeze_count then
		self.freeze_count = 0
	elseif self.freeze_count >= 1 then
		self.freeze_count = self.freeze_count + 1
		self.x_total = 0
		self.y_total = 0
		self.z_total = 0
		self.roll_total = 0
		self.pitch_total = 0
		self.yaw_total = 0
	end

	if DAV.is_disable_heli_roll_tilt or DAV.is_disable_spinner_roll_tilt then
		roll_total = 0
	end
	if DAV.is_disable_heli_pitch_tilt then
		pitch_total = 0
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

	local far_corner_distance = self.position_obj:GetFarCornerDistance()

	local current_position = self.position_obj:GetPosition()

	local direction_vector = {x = self.destination_position.x - current_position.x, y = self.destination_position.y - current_position.y, z = 0}
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

		local stack_count = self.position_obj:CheckAutoPilotStackCount(self.destination_position)

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

		direction_vector = {x = self.destination_position.x - current_position.x, y = self.destination_position.y - current_position.y, z = 0}

		local direction_vector_norm = math.sqrt(direction_vector.x * direction_vector.x + direction_vector.y * direction_vector.y)

		if direction_vector_norm < self.error_range then
			self.log_obj:Record(LogLevel.Info, "Arrived at destination")
			self:AutoLanding(current_position.z)
			Cron.Halt(timer)
			return
		end

		local auto_pilot_speed = self.auto_pilot_speed

		if stack_count > self.min_stack_count and stack_count <= self.max_stack_count then
			auto_pilot_speed = auto_pilot_speed * ((self.max_stack_count - stack_count) / self.max_stack_count)
		end

		self.engine_obj:SetSpeedForcibly(auto_pilot_speed)

		local fix_direction_vector = {x = auto_pilot_speed * direction_vector.x / direction_vector_norm, y = auto_pilot_speed * direction_vector.y / direction_vector_norm, z = 0}

		local next_positon = {x = fix_direction_vector.x + sum_vector.x, y = fix_direction_vector.y + sum_vector.y, z = sum_vector.z}

		if self.is_auto_avoidance then
			next_positon = {x = 0, y = 0, z = self.auto_pilot_speed}
		end

		local vehicle_angle = self.position_obj:GetForward()
		local yaw_vehicle = math.atan2(vehicle_angle.y, vehicle_angle.x) * 180 / Pi()
		local yaw_dist = math.atan2(fix_direction_vector.y / auto_pilot_speed, fix_direction_vector.x / auto_pilot_speed) * 180 / Pi()
		local yaw_diff = yaw_dist - yaw_vehicle
		local yaw_diff_half = yaw_diff / 2
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
end

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
		self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset, 200 - current_position.z, timer.tick + self.down_time_count + 1), -angle.roll * 0.8, -angle.pitch * 0.8, 0.0)
		if timer.tick >= self.down_time_count then
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
				current_direction = Utils:Normalize(current_direction)
				local target_direction = Utils:Normalize(dist_vector)
				local sign = 1
				if current_direction.x * target_direction.y - current_direction.y * target_direction.x > 0 then
					sign = 1
				else
					sign = -1
				end

				if not self:Move(0.0, 0.0, 0.0, 0.0, 0.0, sign * self.turn_speed) then
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

function AV:AutoLanding(hight)
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end
		if not self:Move(0.0, 0.0, Utils:CalculationQuadraticFuncSlope(self.down_time_count, self.land_offset, hight, timer.tick + 1), 0.0, 0.0, 0.0) then
			self.is_landed = true
			self:InterruptAutoPilot()
			Cron.Halt(timer)
		elseif timer.tick >= self.down_time_count then
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