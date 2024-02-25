local Aerodyne = require("Modules/aerodyne.lua")
local Camera = require("Modules/camera.lua")

ActionCommandList = {
    Nothing = 0,
    Foword = 1,
    Backward = 2,
    Left = 3,
    Right = 4,
    Up = 5,
    Down = 6,
    Stop = 7,
}

local Core = {}
Core.__index = Core

function Core:new(event_obj)
    local obj = {}
    obj.event_obj= event_obj
    obj.av_obj = Aerodyne:new()
    obj.camera_obj = Camera:new()

    -- set default parameters
    obj.action_command = ActionCommandList.Nothing

    return setmetatable(obj, self)
end

function Core:setAction(action)
    self.action_command = action
end

function Core:checkAction()
    if self.action_command == ActionCommandList.Nothing then
        return
    else
        self:operateAerodyneVehicle()
        return
    end
end

function Core:callAerodyneVehicle()
    self.av_obj:spawn()
    RAV.Cron.After(2.0, function()
        self.av_obj:lockDoor()
        self:land()
    end)
end

function Core:changeAerodyneDoor()
    self.av_obj:changeDoorState()
end

function Core:lockAerodyneDoor()
    self.av_obj:lockDoor()
    self.av_obj:despawn()
end

function Core:unlockAerodyneDoor()
    self.av_obj:unlockDoor()
end

function Core:mount()
    self.av_obj:mount()
    self.camera_obj:setVehiclePosition()
end

function Core:unmount()
    self.av_obj:unmount()
    self.camera_obj:setDefaultPosition()
end

function Core:operateAerodyneVehicle()
    if self.event_obj.in_av == true then
        if self.action_command == ActionCommandList.Foword then
            self.av_obj:move(0.1, 0.0, 0.0, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Backward then
            self.av_obj:move(-0.1, 0.0, 0.0, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Left then
            self.av_obj:move(0.0, 0.1, 0.0, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Right then
            self.av_obj:move(0.0, -0.1, 0.0, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Up then
            self.av_obj:move(0.0, 0.0, 0.1, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Down then
            self.av_obj:move(0.0, 0.0, -0.1, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Stop then
            self.av_obj:move(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        end
    end
end

function Core:land()
    RAV.Cron.Every(0.01, { tick = 1 }, function(timer)
        timer.tick = timer.tick + 1
        print("timer")
        if self.av_obj:move(0.0, 0.0, -0.2, 0.0, 0.0, 0.0) == false then
            timer:Halt()
        end
    end)
end

return Core
