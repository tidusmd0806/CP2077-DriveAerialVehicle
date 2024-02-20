local Aerodyne = require("Modules/aerodyne.lua")
local Core = {}
Core.__index = Core

function Core:new(event_obj)
    local obj = {}
    obj.event_obj= event_obj
    obj.av_obj = Aerodyne:new()

    return setmetatable(obj, self)
end

function Core:callAerodyneVehicle()
    local spawn = {}
    spawn.path = "Vehicle.av_rayfield_excalibur"
	spawn.parameter = 0
	spawn.entitySpec = DynamicEntitySpec.new()
    self.av_obj:spawnAerodyneVehicle(spawn)
end

function Core:changeAerodyneDoor()
    self.av_obj:changeDoorState()
end

function Core:lockAerodyneDoor()
    self.av_obj:lockAVDoor()
end

function Core:unlockAerodyneDoor()
    self.av_obj:unlockAVDoor()
end

function Core:mount()
    self.av_obj:mountAV()
end

function Core:unmount()
    self.av_obj:unmountAV()
end

return Core
