local Position = require("Modules/position.lua")
local Def = require("Modules/def.lua")
local Engine = require("Modules/engine.lua")
local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local AV = {}
AV.__index = AV

function AV:New(all_models)
	local obj = {}
	obj.position_obj = Position:New(all_models)
	obj.engine_obj = Engine:New(obj.position_obj, all_models)
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "AV")
	obj.player_obj = nil

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
	obj.is_default_seat_position = nil
	obj.sit_pose = nil
	obj.seat_position = nil
	obj.active_seat = nil
	obj.active_door = nil

	return setmetatable(obj, self)
end

function AV:SetModel(list)
	local index = list[1]
	local type_number = list[2]
	self.vehicle_model_tweakdb_id = self.all_models[index].tweakdb_id
	self.vehicle_model_type = self.all_models[index].type[type_number]
	self.is_default_mount = self.all_models[index].is_default_mount
	self.is_default_seat_position = self.all_models[index].is_default_seat_position
	self.sit_pose = self.all_models[index].sit_pose
	self.seat_position = self.all_models[index].seat_position
	self.active_seat = self.all_models[index].active_seat
	self.active_door = self.all_models[index].active_door
	self.engine_obj:SetModel(index)
	self.position_obj:SetModel(index)
end

function AV:IsPlayerIn()
	return self.is_player_in
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
				DAV.Cron.Halt(timer)
			elseif timer.tick >= self.spawn_wait_count + self.down_time_count then
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

function AV:ChangeDoorState(door_number, door_state)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door state")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	local state = vehicle_ps:GetDoorState(door_number - 1).value -- front left door: 0 / front right door: 1
	local door_event = nil
	if state == "Closed" then
		if door_state == Def.DoorOperation.Close then
			return false
		end
		door_event = VehicleDoorOpen.new()
	elseif state == "Open" then
		if door_state == Def.DoorOperation.Open then
			return false
		end
		door_event = VehicleDoorClose.new()
	else
		self.log_obj:Record(LogLevel.Error, "Door state is not valid : " .. state)
		return false
	end
	door_event.slotID = self.active_door[door_number]
	door_event.forceScene = false
	vehicle_ps:QueuePSEvent(vehicle_ps, door_event)
	return true
end

function AV:Mount(seat_number)

	self.log_obj:Record(LogLevel.Debug, "Mount Aerial Vehicle : " .. seat_number)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to mount")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local player = Game.GetPlayer()
	local ent_id = entity:GetEntityID()
	local seat = self.active_seat[seat_number]
	-- local seat = "passenger_seat_e"


	local data = NewObject('handle:gameMountEventData')
	data.isInstant = false
	data.slotName = seat
	data.mountParentEntityId = ent_id
	data.entryAnimName = "forcedTransition"


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
	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game['GetMountedVehicle;GameObject'](Game.GetPlayer())
		if entity ~= nil then
			self.position_obj:SetEntity(entity)
			DAV.Cron.After(0.2, function()
				if not self.is_default_seat_position then
					self:SitCorrectPosition(3)
				end
				self.player_obj:ActivateTPPHead(true)
				self.is_player_in = true
			end)
			DAV.Cron.Halt(timer)
		end
	end)

	return true

end

function AV:Unmount()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to unmount")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local player = Game.GetPlayer()
	local ent_id = entity:GetEntityID()
	local seat = "seat_back_left"

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

	self.player_obj:ActivateTPPHead(false)

	Game.GetMountingFacility():Unmount(mount_event)

	-- set entity id to position object
	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			local angle = player:GetWorldOrientation():ToEulerAngles()
			local position = self.position_obj:GetExitPosition()
			self.position_obj:SetEntity(entity)
			Game.GetTeleportationFacility():Teleport(player, Vector4.new(position.x, position.y, position.z, 1.0), angle)
			self.is_player_in = false
			DAV.Cron.Halt(timer)
		end
	end)

	return true
end

function AV:TakeOn(player_obj)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to take on")
		return false
	end
	self.player_obj = player_obj
	return true
end

function AV:TakeOff()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to take off")
		return false
	end
	self.player_obj = nil
	return true
end

function AV:SitCorrectPosition(seat_number)

	self.player_obj:PlayPose(self.sit_pose)

	local left_seat_cordinate = Vector4.new(self.seat_position[seat_number].x, self.seat_position[seat_number].y, self.seat_position[seat_number].z, 1.0)
	local pos = self.position_obj:GetPosition()
	local foward = self.position_obj:GetFoword()
	local Backward = Vector4.RotateAxis(foward ,Vector4.new(0, 0, 1, 0), 180 / 180.0 * Pi())
	local rot = self.position_obj:GetQuaternion()

	local rotated = Utils:RotateVectorByQuaternion(left_seat_cordinate, rot)

	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
        local dummy_entity = Game.FindEntityByID(self.player_obj.dummy_entity_id)
        if dummy_entity ~= nil then
            Game.GetTeleportationFacility():Teleport(dummy_entity, Vector4.new(pos.x + rotated.x, pos.y + rotated.y, pos.z + rotated.z, 1.0), Vector4.ToRotation(Backward))
			DAV.Cron.Halt(timer)
        end
    end)
	return true
end

function AV:Move(x, y, z, roll, pitch, yaw)

	if not self.position_obj:SetNextPosition(x, y, z, roll, pitch, yaw) then
		return false
	end

	return true
end

function AV:Operate(action_command)

	if action_command ~= Def.ActionList.Nothing then
		self.log_obj:Record(LogLevel.Debug, "Operate Aerial Vehicle : " .. action_command)
	end

	local x, y, z, roll, pitch, yaw = self.engine_obj:GetNextPosition(action_command)

	if x == 0 and y == 0 and z == 0 and roll == 0 and pitch == 0 and yaw == 0 then
		return false
	end

	if not self.position_obj:SetNextPosition(x, y, z, roll, pitch, yaw) then
		self.engine_obj:SetSpeedAfterRebound()
		return false
	end

	return true
end

return AV