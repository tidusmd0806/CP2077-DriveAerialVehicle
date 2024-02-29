local Aerodyne = require("Modules/aerodyne.lua")
local Camera = require("Modules/camera.lua")
local Queue = require("Modules/queue.lua")

ActionList = {
    Nothing = 0,
    Up = 1,
    Forward = 2,
    Backward = 3,
    Right = 4,
    Left = 5,
    TurnRight = 6,
    TurnLeft = 7,
    Hover = 8,
}

local Core = {}
Core.__index = Core

function Core:New(event_obj)
    local obj = {}
    obj.event_obj= event_obj
    obj.av_obj = Aerodyne:New(VehicleModel.Excalibur)
    obj.camera_obj = Camera:New()
    obj.queue_obj = Queue:New()

    return setmetatable(obj, self)
end

function Core:StorePlayerAction(action_name, action_type, action_value)
    local cmd = self:ConvertActionList(action_name, action_type, action_value)
    if cmd > 0 then
        self.queue_obj:Enqueue(cmd)
    end
end

function Core:ConvertActionList(action_name, action_type, action_value)
    local action_command = ActionList.Nothing
    if action_name == "UI_Skip" and action_type == "BUTTON_PRESSED" and action_value == 1 then
        action_command = ActionList.Up
    elseif action_name == "LeftY_Axis" and action_type == "AXIS_CHANGE" and action_value > 0 then
        action_command = ActionList.Forward
    elseif action_name == "LeftY_Axis" and action_type == "AXIS_CHANGE" and action_value < 0 then
        action_command = ActionList.Backward
    elseif action_name == "LeftX_Axis" and action_type == "AXIS_CHANGE" and action_value > 0 then
        action_command = ActionList.Right
    elseif action_name == "LeftX_Axis" and action_type == "AXIS_CHANGE" and action_value < 0 then
        action_command = ActionList.Left
    elseif action_name == "character_preview_rotate" and action_type == "AXIS_CHANGE" and action_value > 0 then
        action_command = ActionList.TurnRight
    elseif action_name == "character_preview_rotate" and action_type == "AXIS_CHANGE" and action_value < 0 then
        action_command = ActionList.TurnLeft
    else
        action_command = ActionList.Nothing
    end
    return action_command
end

function Core:ExcutePriodicalTask()
    if self.queue_obj:IsEmpty() then
        return
    else
        local actions = {}
        while not self.queue_obj:IsEmpty() do
            local action = self.queue_obj:Dequeue()
            table.insert(actions, action)
        end
            self:OperateAerodyneVehicle(actions)
            return
    end
end

function Core:CallAerodyneVehicle()
    self.av_obj:SpawnToSky()
    local times = 150
    RAV.Cron.Every(0.01, { tick = 1 }, function(timer)
        timer.tick = timer.tick + 1
        if timer.tick == times then
            self.av_obj:LockDoor()
        elseif timer.tick > times then
            if not self.av_obj:Move(0.0, 0.0, -1.0, 0.0, 0.0, 0.0) then
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
    -- self.av_obj:Despawn()
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

function Core:OperateAerodyneVehicle(actions)
    if self.event_obj.in_av == true then
        for _, action_command in ipairs(actions) do
            if action_command == ActionList.Up then
                self.av_obj:Move(0.0, 0.0, 0.3, 0.0, 0.0, 0.0)
            elseif action_command == ActionList.Forward then
                self.av_obj:Move(0.0, 0.0, 0.0, 1.0, 0.0, 0.0)
            elseif action_command == ActionList.Backward then
                self.av_obj:Move(0.0, 0.0, 0.0, -1.0, 0.0, 0.0)
            elseif action_command == ActionList.Right then
                self.av_obj:Move(0.0, 0.0, 0.0, 0.0, 1.0, 0.0)
            elseif action_command == ActionList.Left then
                self.av_obj:Move(0.0, 0.0, 0.1, 0.0, -1.0, 0.0)
            elseif action_command == ActionList.TurnRight then
                self.av_obj:Move(0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
            elseif action_command == ActionList.TurnLeft then
                self.av_obj:Move(0.0, 0.0, 0.0, 0.0, 0.0, -1.0)
            end
        end
    end
end

return Core
