local Position = require("Modules/position.lua")
local Engine = require("Modules/engine.lua")
local Log = require("Modules/log.lua")
local Aerodyne = {}
Aerodyne.__index = Aerodyne

VehicleModel = {
	Excalibur = "Vehicle.av_rayfield_excalibur",
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
	obj.position_obj = Position:New()
	obj.engine_obj = Engine:New()
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "Aerodyne")

	-- set default parameters
	obj.entity_id = nil
	obj.vehicle_model = vehicle_model or VehicleModel.Excalibur
	return setmetatable(obj, self)
end

function Aerodyne:Spawn(position, angle)
	if self.entity_id ~= nil then
		self.log_obj:Record(LogLevel.Info, "Entity already spawned")
		return false
	end

	local entity_system = Game.GetDynamicEntitySystem()
	local entity_spec = DynamicEntitySpec.new()

	entity_spec.recordID = self.vehicle_model
	entity_spec.position = position
	entity_spec.orientation = angle
	entity_spec.persistState = false
	self.entity_id = entity_system:CreateEntity(entity_spec)

	-- set entity id to position object
	RAV.Cron.After(0.1, function()
		self.position_obj:SetEntityId(self.entity_id)
	end)

	return true
end

function Aerodyne:SpawnToSky()
	local position = self.position_obj:GetSpawnPosition(5.5, 0.0, 50.0)
	local angle = self.position_obj:GetSpawnOrientation(90.0)
	self:Spawn(position, angle)
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

	local pos = self.position_obj:GetPosition()
	local rot = self.position_obj:GetEulerAngles()
	self.position_obj:SetNextVehiclePosition(pos.x, pos.y, pos.z, rot.roll, rot.pitch, rot.yaw)

	Game.GetMountingFacility():Mount(mounting_request)
	self.position_obj:ChangeVehiclePosition()

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
	if not self.position_obj:SetNextVehiclePosition(x, y, z, roll, pitch, yaw) then
		return false
	end
	self.position_obj:ChangeVehiclePosition()
	return true
end

function Aerodyne:Operate(action_command)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to move")
		return false
	end

	local indicate = self.engine_obj:CalcurateIndication(action_command)

	local x = 0
	local y = 0
	local z = 0

	if not self.position_obj:SetNextVehiclePosition(x, y, z, indicate["roll"], indicate["pitch"], indicate["yaw"]) then
		return false
	end
	self.position_obj:ChangeVehiclePosition()
	return true
end

return Aerodyne