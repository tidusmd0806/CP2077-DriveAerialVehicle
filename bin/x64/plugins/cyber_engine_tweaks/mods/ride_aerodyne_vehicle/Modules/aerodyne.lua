local Position = require("Modules/position.lua")
local Log = require("Modules/log.lua")
local Aerodyne = {}
Aerodyne.__index = Aerodyne

VehicleModel = {
	Excalibur = "Vehicle.av_rayfield_excalibur",
}

function Aerodyne:New(vehicle_model)
	local obj = {}
	obj.position_obj = Position:New()
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "Aerodyne")
	obj.vehicle_model = vehicle_model or VehicleModel.Excalibur

	-- set default parameters
	obj.entity_id = nil
	return setmetatable(obj, self)
end

function Aerodyne:Spawn(high)
	if self.entity_id ~= nil then
		self.log_obj:Record(LogLevel.Info, "Entity already spawned")
		return false, nil
	end

	local entity_system = Game.GetDynamicEntitySystem()
	local entity_spec = DynamicEntitySpec.new()

	entity_spec.persistState = false
	entity_spec.persistSpawn = false
	entity_spec.alwaysSpawned = false
	entity_spec.spawnInView = true

	entity_spec.recordID = self.vehicle_model
	-- entity_spec.tags = { "RAV_excalibur" }
	entity_spec.position = self.position_obj:GetSpawnPosition(5.5, 0.0, high)
	entity_spec.orientation = self.position_obj:GetSpawnOrientation(90.0)
	self.entity_id = entity_system:CreateEntity(entity_spec)

	return true, entity_spec.position
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

function Aerodyne:ChangeDoorState()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door state")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	local state = vehicle_ps:GetDoorState(1).value
	if state == "Closed" then
		vehicle_ps:OpenAllRegularVehDoors(false)
	elseif state == "Open" then
		vehicle_ps:CloseAllVehDoors(false)
	else
		self.log_obj:Record(LogLevel.Error, "Door state is not valid : " .. state)
		return false
	end
	return true
end

function Aerodyne:Mount()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to mount")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local player = Game.GetPlayer()
	local ent_id = entity:GetEntityID()
	local seat = "seat_back_left"

	local data = NewObject('handle:gameMountEventData')
	data.isInstant = false
	data.setEntityVisibleWhenMountFinish = false
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
	return true
end

function Aerodyne:Move(x, y, z, roll, pitch, yaw)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to move")
		return false
	end
	if self.position_obj:GetUnmountVehicle() == nil then
		self.position_obj:SetUnmountVehicle(Game.FindEntityByID(self.entity_id))
	end
	if not self.position_obj:SetNextVehiclePosition(x, y, z, roll, pitch, yaw) then
		return false
	end
	self.position_obj:ChangeVehiclePosition()
	return true
end

return Aerodyne