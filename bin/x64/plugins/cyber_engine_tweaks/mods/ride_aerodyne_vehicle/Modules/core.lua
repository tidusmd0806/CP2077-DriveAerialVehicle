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

function Core:New(event_obj)
    local obj = {}
    obj.event_obj= event_obj
    obj.av_obj = Aerodyne:New()
    obj.camera_obj = Camera:New()

    -- set default parameters
    obj.action_command = ActionCommandList.Nothing
    obj.dummy_av_spawn_high = 50
    return setmetatable(obj, self)
end

function Core:SetAction(action)
    self.action_command = action
end

function Core:CheckAction()
    if self.action_command == ActionCommandList.Nothing then
        return
    else
        self:OperateAerodyneVehicle()
        return
    end
end

function Core:CallAerodyneVehicle()
    local dummy_av_obj = Aerodyne:New()
    local res, pos = dummy_av_obj:Spawn(self.dummy_av_spawn_high)
    RAV.Cron.Every(0.01, { tick = 1 }, function(timer)
        timer.tick = timer.tick + 1
        if timer.tick > 50 then
            if not dummy_av_obj:Move(0.0, 0.0, -0.2, 0.0, 0.0, 0.0) then
                self.av_obj:Spawn(dummy_av_obj.position_obj.next_vehicle_vector.z - (pos.z - self.dummy_av_spawn_high))
                RAV.Cron.After(0.5, function()
                    self.av_obj:LockDoor()
                    dummy_av_obj:Despawn()
                end)
                RAV.Cron.Halt(timer)
            end
        end
    end)
end

function Core:ChangeAerodyneDoor()
    self.av_obj:ChangeDoorState()
end

function Core:LockAerodyneDoor()
    self.av_obj:LockDoor()
    self.av_obj:Despawn()
end

function Core:UnlockAerodyneDoor()
    self.av_obj:UnlockDoor()
end

function Core:Mount()
    self.av_obj:Mount()
    self.camera_obj:SetVehiclePosition()
end

function Core:Unmount()
    self.av_obj:Unmount()
    self.camera_obj:SetDefaultPosition()
end

function Core:OperateAerodyneVehicle()
    if self.event_obj.in_av == true then
        if self.action_command == ActionCommandList.Foword then
            self.av_obj:Move(0.1, 0.0, 0.0, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Backward then
            self.av_obj:Move(-0.1, 0.0, 0.0, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Left then
            self.av_obj:Move(0.0, 0.1, 0.0, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Right then
            self.av_obj:Move(0.0, -0.1, 0.0, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Up then
            self.av_obj:Move(0.0, 0.0, 0.1, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Down then
            self.av_obj:Move(0.0, 0.0, -0.1, 0.0, 0.0, 0.0)
        elseif self.action_command == ActionCommandList.Stop then
            self.av_obj:Move(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        end
    end
end

return Core
