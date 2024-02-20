local Position = require("Modules/position.lua")
local Log = require("Modules/log.lua")
local Aerodyne = {}
Aerodyne.__index = Aerodyne

function Aerodyne:new()
	local obj = {}
	obj.position_obj = Position:new()
	obj.log_obj = Log:new()
	obj.log_obj:setLevel(LogLevel.INFO, "Aerodyne")

	obj.entityID = nil
	return setmetatable(obj, self)
end


function Aerodyne:spawnAerodyneVehicle(spawn)

	local entitySystem = Game.GetDynamicEntitySystem()

	spawn.entitySpec.recordID = spawn.path
	spawn.entitySpec.tags = { "RAV" }
	spawn.entitySpec.position = self.position_obj:getPosition(5.5, 0.0)
	spawn.entitySpec.orientation = self.position_obj:getOrientation(90.0)
	self.entityID = entitySystem:CreateEntity(spawn.entitySpec)

end

function Aerodyne:unlockAVDoor()
	if self.entityID == nil then
		self.log_obj:record(LogLevel.WARN, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entityID)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:UnlockAllVehDoors()
	return true
end

function Aerodyne:lockAVDoor()
	if self.entityID == nil then
		self.log_obj:record(LogLevel.WARN, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entityID)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:LockAllVehDoors()
	return true
end

function Aerodyne:changeDoorState()
	if self.entityID == nil then
		self.log_obj:record(LogLevel.WARN, "No entity to change door state")
		return false
	end
	local entity = Game.FindEntityByID(self.entityID)
	local vehicle_ps = entity:GetVehiclePS()
	local state = vehicle_ps:GetDoorState(1).value
	if state == "Closed" then
		vehicle_ps:OpenAllRegularVehDoors(false)
	elseif state == "Open" then
		vehicle_ps:CloseAllVehDoors(false)
	else
		self.log_obj:record(LogLevel.ERROR, "Door state is not valid : " .. state)
		return false
	end
	return true
end

function Aerodyne:mountAV()
	if self.entityID == nil then
		self.log_obj:record(LogLevel.WARN, "No entity to mount")
		return false
	end
	local entity = Game.FindEntityByID(self.entityID)
	local player = Game.GetPlayer()
	local entID = entity:GetEntityID()
	local seat = "seat_back_left"

	local data = NewObject('handle:gameMountEventData')
	data.isInstant = false
	data.setEntityVisibleWhenMountFinish = false
	data.slotName = seat
	data.mountParentEntityId = entID
	data.entryAnimName = "forcedTransition"

	local slotID = NewObject('gamemountingMountingSlotId')
	slotID.id = seat

	local mountingInfo = NewObject('gamemountingMountingInfo')
	mountingInfo.childId = player:GetEntityID()
	mountingInfo.parentId = entID
	mountingInfo.slotId = slotID

	local mountEvent = NewObject('handle:gamemountingMountingRequest')
	mountEvent.lowLevelMountingInfo = mountingInfo
	mountEvent.mountData = data

	Game.GetMountingFacility():Mount(mountEvent)
	return true
end

function Aerodyne:unmountAV()
	if self.entityID == nil then
		self.log_obj:record(LogLevel.WARN, "No entity to unmount")
		return false
	end
	local entity = Game.FindEntityByID(self.entityID)
	local player = Game.GetPlayer()
	local entID = entity:GetEntityID()
	local seat = "seat_back_left"
							
	local data = NewObject('handle:gameMountEventData')
	data.isInstant = true
	data.slotName = seat
	data.mountParentEntityId = entID
	data.entryAnimName = "forcedTransition"
	
	local slotID = NewObject('gamemountingMountingSlotId')
	slotID.id = seat
	
	local mountingInfo = NewObject('gamemountingMountingInfo')
	mountingInfo.childId = player:GetEntityID()
	mountingInfo.parentId = entID
	mountingInfo.slotId = slotID
	
	local mountEvent = NewObject('handle:gamemountingUnmountingRequest')
	mountEvent.lowLevelMountingInfo = mountingInfo
	mountEvent.mountData = data
	
	Game.GetMountingFacility():Unmount(mountEvent)
	return true
end

return Aerodyne