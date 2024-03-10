local Position = require("Modules/position.lua")
local Engine = require("Modules/engine.lua")
local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Aerodyne = {}
Aerodyne.__index = Aerodyne

VehicleModel = {
	Excalibur = "Vehicle.av_rayfield_excalibur",
	Manticore = "Vehicle.av_militech_manticore",
	Atlus = "Vehicle.av_zetatech_atlus"
}

ActionList = {
    Nothing = 0,
    Up = 1,
    Down = 2,
    Forward = 3,
    Backward = 4,
    Right = 5,
    Left = 6,
    TurnRight = 7,
    TurnLeft = 8,
    Hover = 9
}

function Aerodyne:New(vehicle_model)
	local obj = {}
	obj.position_obj = Position:New(vehicle_model)
	obj.engine_obj = Engine:New(obj.position_obj, vehicle_model)
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "Aerodyne")
	obj.player_obj = nil

	for key, value in pairs(Movement) do
		if ActionList[key] ~= value then
			obj.log_obj:Record(LogLevel.Critical, "ActionList is not equal to Movement /" .. key .. " : " .. value)
		end
	end

	-- set default parameters
	obj.entity_id = nil
	obj.vehicle_model_name = vehicle_model.name
	obj.vehicle_model_type = vehicle_model.type
	obj.is_player_in = false
	obj.is_default_mount = vehicle_model.is_default_mount
	obj.is_default_seat_position = vehicle_model.is_default_seat_position
	obj.sit_pose = vehicle_model.sit_pose
	obj.seat_position = vehicle_model.seat_position
	obj.active_seat = vehicle_model.active_seat
	obj.active_door = vehicle_model.active_door
	return setmetatable(obj, self)
end

function Aerodyne:Spawn(position, angle, type_number)
	if self.entity_id ~= nil then
		self.log_obj:Record(LogLevel.Info, "Entity already spawned")
		return false
	end

	local entity_system = Game.GetDynamicEntitySystem()
	local entity_spec = DynamicEntitySpec.new()

	entity_spec.recordID = self.vehicle_model_name
	entity_spec.position = position
	entity_spec.orientation = angle
	entity_spec.persistState = false
	self.entity_id = entity_system:CreateEntity(entity_spec)

	-- set entity id to position object
	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			self.position_obj:SetEntity(entity)
			entity:PrefetchAppearanceChange(self.vehicle_model_type[type_number])
			entity:ScheduleAppearanceChange(self.vehicle_model_type[type_number])
			self.engine_obj:Init()
			DAV.Cron.Halt(timer)
		end
	end)

	return true
end

function Aerodyne:SpawnToSky()
	local position = self.position_obj:GetSpawnPosition(5.5, 0.0)
	position.z = position.z + 50.0
	local angle = self.position_obj:GetSpawnOrientation(90.0)
	self:Spawn(position, angle, 1)
end

function Aerodyne:Despawn()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to despawn")
		return false
	end
	local entity_system = Game.GetDynamicEntitySystem()
	entity_system:DeleteEntity(self.entity_id)
	self.entity_id = nil
	return true
end

function Aerodyne:UnlockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:UnlockAllVehDoors()
	return true
end

function Aerodyne:LockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:QuestLockAllVehDoors()
	return true
end

function Aerodyne:ChangeDoorState(door_number)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door state")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	local state = vehicle_ps:GetDoorState(0).value -- front left door: 0 / front right door: 1
	local door_event = nil
	if state == "Closed" then
		door_event = VehicleDoorOpen.new()
		-- vehicle_ps:OpenAllRegularVehDoors(false)
	elseif state == "Open" then
		door_event = VehicleDoorClose.new()
		-- vehicle_ps:CloseAllVehDoors(false)
	else
		self.log_obj:Record(LogLevel.Error, "Door state is not valid : " .. state)
		return false
	end
	door_event.slotID = self.active_door[door_number]
	door_event.forceScene = false
	vehicle_ps:QueuePSEvent(vehicle_ps, door_event)
	return true
end

function Aerodyne:Mount(seat_number)
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
			if not self.is_default_seat_position then
				self:SitCorrectPosition(3)
			end
			self.is_player_in = true
			self.player_obj:ActivateTPPHead(true)
			DAV.Cron.Halt(timer)
		end
	end)

	return true
end

function Aerodyne:Unmount()
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

	Game.GetMountingFacility():Unmount(mount_event)

		-- set entity id to position object
	DAV.Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			self.position_obj:SetEntity(entity)
			self.is_player_in = false
			self.player_obj:ActivateTPPHead(false)
			DAV.Cron.Halt(timer)
		end
	end)

	return true
end

function Aerodyne:TakeOn(player_obj)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to take on")
		return false
	end
	self.player_obj = player_obj
	return true
end

function Aerodyne:SitCorrectPosition(seat_number)
	if self.player_obj.gender == "famale" then
		self.player_obj:PlayPose(self.sit_pose.famele)
	else
		self.player_obj:PlayPose(self.sit_pose.male)
	end
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

function Aerodyne:Move(x, y, z, roll, pitch, yaw)

	if not self.position_obj:SetNextPosition(x, y, z, roll, pitch, yaw) then
		return false
	end

	return true
end

function Aerodyne:Operate(action_command)

	if action_command ~= ActionList.Nothing then
		self.log_obj:Record(LogLevel.Debug, "Operate Aerodyne Vehicle : " .. action_command)
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

return Aerodyne