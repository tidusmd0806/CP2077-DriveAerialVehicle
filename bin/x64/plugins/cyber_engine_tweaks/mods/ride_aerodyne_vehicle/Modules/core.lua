local Aerodyne = require("Modules/aerodyne.lua")
local Event = require("Modules/event.lua")
local Key = require("Data/key.lua")
local Log = require("Tools/log.lua")
local Queue = require("Tools/queue.lua")
local Utils = require("Tools/utils.lua")

local Core = {}
Core.__index = Core

function Core:New()
    local obj = {}
    obj.av_obj = Aerodyne:New(VehicleModel.Excalibur)
    obj.event_obj = Event:New(obj.av_obj)
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Core")
    obj.queue_obj = Queue:New()

    return setmetatable(obj, self)
end

function Core:Init()

    RAV.Cron.Every(RAV.time_resolution, function()
        self.event_obj:CheckAllEvents()
        self:ExcutePriodicalTask()
    end)
end

function Core:StorePlayerAction(action_name, action_type, action_value)
    local action_value_type = "ZERO"
    if action_value > 0.1 then
        action_value_type = "POSITIVE"
    elseif action_value < -0.1 then
        action_value_type = "NEGATIVE"
    else
        action_value_type = "ZERO"
    end

    local cmd = self:ConvertActionList(action_name, action_type, action_value_type)

    if cmd ~= ActionList.Nothing then
        self.queue_obj:Enqueue(cmd)
    end

end

function Core:ConvertActionList(action_name, action_type, action_value)
    local action_command = ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value}

    if Utils:IsTablesEqual(action_dist, Key.KEY_CLICK_HOLD_IN_AV) then
        action_command = ActionList.Up
    elseif Utils:IsTablesEqual(action_dist, Key.KEY_CLICK_RELEASE_IN_AV) then
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
    local actions = {}
    if self.queue_obj:IsEmpty() then
        local action = ActionList.Nothing
        table.insert(actions, action)
    else
        while not self.queue_obj:IsEmpty() do
            local action = self.queue_obj:Dequeue()
            table.insert(actions, action)
        end
    end
    self:OperateAerodyneVehicle(actions)
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
    self.av_obj:Despawn()
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
end

function Core:Unmount()
    self.av_obj:Unmount()
end

function Core:OperateAerodyneVehicle(actions)
    if self.event_obj:IsInAV() then
        for _, action_command in ipairs(actions) do
            self.av_obj:Operate(action_command)
        end
    end
end

return Core
