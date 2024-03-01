local Aerodyne = require("Modules/aerodyne.lua")
local Camera = require("Modules/camera.lua")
local Queue = require("Modules/queue.lua")
local Utils = require("Modules/utils.lua")
local Key = require("Config/key.lua")

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
    local action_value_type = "ZERO"
    if action_value > 0 then
        action_value_type = "POSITIVE"
    elseif action_value < 0 then
        action_value_type = "NEGATIVE"
    else
        action_value_type = "ZERO"
    end

    local cmd = self:ConvertActionList(action_name, action_type, action_value_type)

    if cmd > 0 then
        self.queue_obj:Enqueue(cmd)
    end
end

function Core:ConvertActionList(action_name, action_type, action_value)
    local action_command = ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value}

    if Utils:IsTablesEqual(action_dist, Key.KEY_SPACE_PRESS_IN_AV) then
        action_command = ActionList.Up
    elseif Utils:IsTablesEqual(action_dist, Key.KEY_SPACE_RELEASE_IN_AV) then
        action_command = ActionList.Down
    elseif Utils:IsTablesEqual(action_dist, Key.KEY_W_PRESS_IN_AV) then
        action_command = ActionList.Forward
    elseif Utils:IsTablesEqual(action_dist, Key.KEY_S_PRESS_IN_AV) then
        action_command = ActionList.Backward
    elseif Utils:IsTablesEqual(action_dist, Key.KEY_D_PRESS_IN_AV) then
        action_command = ActionList.Right
    elseif Utils:IsTablesEqual(action_dist, Key.KEY_A_PRESS_IN_AV) then
        action_command = ActionList.Left
    elseif Utils:IsTablesEqual(action_dist, Key.KEY_E_PRESS_IN_AV) then
        action_command = ActionList.TurnRight
    elseif Utils:IsTablesEqual(action_dist, Key.KEY_Q_PRESS_IN_AV) then
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
            if not self.av_obj:Move(0.0, 0.0, -0.5, 0.0, 0.0, 0.0) then
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
    local audioEvent = SoundPlayEvent.new()

    audioEvent.soundName = StringToName("v_av_rayfield_excalibur_traffic_engine_01_av_dplr_01")
    print("sound")
    Game.GetPlayer():QueueEvent(audioEvent)
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
            self.av_obj:Operate(action_command)
        end
    end
end

return Core
