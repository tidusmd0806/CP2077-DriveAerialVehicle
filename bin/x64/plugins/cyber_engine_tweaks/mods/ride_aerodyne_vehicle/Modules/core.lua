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
    self.av_obj:spawn(spawn)
end

function Core:changeAerodyneDoor()
    self.av_obj:changeDoorState()
end

function Core:lockAerodyneDoor()
    self.av_obj:lockDoor()
end

function Core:unlockAerodyneDoor()
    self.av_obj:unlockDoor()
    self.av_obj:despawn()
end

function Core:mount()
    self.av_obj:mount()
end

function Core:unmount()
    self.av_obj:unmount()
end

function Core:operateAV()
    if self.event_obj.in_av == true then
        self.av_obj:move()
    end
end

return Core
