local AV = require("Modules/av.lua")
local Player = require("Modules/player.lua")
local Def = require("Tools/def.lua")
local Event = require("Modules/event.lua")
local Log = require("Tools/log.lua")
local Queue = require("Tools/queue.lua")
local Utils = require("Tools/utils.lua")

local Core = {}
Core.__index = Core

function Core:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Core")
    obj.queue_obj = Queue:New()
    obj.av_obj = nil
    obj.player_obj = nil
    obj.event_obj = nil
    
    obj.all_models = nil
    obj.input_table = nil

    obj.av_model_path = "Data/default_model.json"
    obj.input_path = "Data/input.json"
    obj.axis_dead_zone = 0.5
    obj.relative_dead_zone = 0.01
    obj.relative_table = {}

    -- set default parameters
    obj.input_table = {}

    return setmetatable(obj, self)
end

function Core:Init()

    self.all_models = self:GetAllModel()
    self.input_table = self:GetInputTable(self.input_path)

    if self.all_models == nil then
        self.log_obj:Record(LogLevel.Error, "Model is nil")
        return
    end

    self.player_obj = Player:New(Game.GetPlayer())
    self.player_obj:Init()

    self.av_obj = AV:New(self.all_models)
    self.av_obj:Init()

    self.event_obj = Event:New()
    self.event_obj:Init(self.av_obj)

    DAV.Cron.Every(DAV.time_resolution, function()
        self.event_obj:CheckAllEvents()
        self:GetActions()
    end)
    
end

function Core:Reset()
    self.player_obj = Player:New(Game.GetPlayer())
    self.player_obj:Init()

    self.av_obj = AV:New(self.all_models)
    self.av_obj:Init()

    self.event_obj:Init(self.av_obj)
end

function Core:GetAllModel()
    local model = Utils:ReadJson(self.av_model_path)
    if model == nil then
        self.log_obj:Record(LogLevel.Error, "Default Model is nil")
        return nil
    end
    return model
end

function Core:GetInputTable(input_path)
    local input = Utils:ReadJson(input_path)
    if input == nil then
        self.log_obj:Record(LogLevel.Error, "Input is nil")
        return nil
    end
    return input
end

function Core:StorePlayerAction(action_name, action_type, action_value)
    local action_value_type = "ZERO"
    if action_type == "RELATIVE_CHANGE" then
        if action_value > self.relative_dead_zone then
            action_value_type = "POSITIVE"
        elseif action_value < -self.relative_dead_zone then
            action_value_type = "NEGATIVE"
        else
            action_value_type = "ZERO"
        end
    else
        if action_value > self.axis_dead_zone then
            action_value_type = "POSITIVE"
        elseif action_value < -self.axis_dead_zone then
            action_value_type = "NEGATIVE"
        else
            action_value_type = "ZERO"
        end
    end

    local cmd = self:ConvertActionList(action_name, action_type, action_value_type)

    if cmd ~= Def.ActionList.Nothing then
        self.queue_obj:Enqueue(cmd)
    end

end

function Core:ConvertActionList(action_name, action_type, action_value)
    local action_command = Def.ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value}

    if Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_ACCELERTOR) then
        action_command = Def.ActionList.Up
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_DOWN) then
        action_command = Def.ActionList.Down
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_FORWARD_MOVE) then
        action_command = Def.ActionList.Forward
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_BACK_MOVE) then
        action_command = Def.ActionList.Backward
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_RIGHT_MOVE) then
        action_command = Def.ActionList.Right
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_LEFT_MOVE) then
        action_command = Def.ActionList.Left
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_RIGHT_ROTATE) then
        action_command = Def.ActionList.TurnRight
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_LEFT_ROTATE) then
        action_command = Def.ActionList.TurnLeft
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_HOVER) then
        action_command = Def.ActionList.Hover
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_HOLD) then
        action_command = Def.ActionList.Hold
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_WORLD_ENTER_AV) then
        action_command = Def.ActionList.Enter
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_EXIT_AV) then
        action_command = Def.ActionList.Exit
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_CAMERA) then
        action_command = Def.ActionList.ChangeCamera
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_TOGGLE_DOOR_1) then
        action_command = Def.ActionList.ChangeDoor1
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_UP_CAMERA_MOUSE) or Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_UP_CAMERA_JOYSTICK) then
        action_command = Def.ActionList.CamUp
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_DOWN_CAMERA_MOUSE) or Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_DOWN_CAMERA_JOYSTICK) then
        action_command = Def.ActionList.CamDown
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_RIGHT_CAMERA_MOUSE) or Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_RIGHT_CAMERA_JOYSTICK) then
        action_command = Def.ActionList.CamRight
    elseif Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_LEFT_CAMERA_MOUSE) or Utils:IsTablesEqual(action_dist, self.input_table.KEY_AV_LEFT_CAMERA_JOYSTICK) then
        action_command = Def.ActionList.CamLeft
    else
        action_command = Def.ActionList.Nothing
    end

    return action_command
end

function Core:GetActions()

    local move_actions = {}
    local cam_actions = {}

    if self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.queue_obj:Clear()
        return
    end

    while not self.queue_obj:IsEmpty() do
        local action = self.queue_obj:Dequeue()
        if action >= Def.ActionList.Enter and action < Def.ActionList.CamReset then
            self:SetEvent(action)
        elseif action >= Def.ActionList.CamReset then
            table.insert(cam_actions, action)
        else
            table.insert(move_actions, action)
        end
    end

    if #move_actions == 0 then
        table.insert(move_actions, Def.ActionList.Nothing)
    end

    self:OperateAerialVehicle(move_actions)
    self:OperateCamera(cam_actions)

end

function Core:OperateAerialVehicle(actions)
    if self.event_obj:IsInVehicle() then
        self.av_obj:Operate(actions)
    elseif self.event_obj:IsWaiting() then
        self.av_obj:Operate({Def.ActionList.Nothing})
    end
end

function Core:OperateCamera(actions)
    for _, action in pairs(actions) do
        self.av_obj.camera_obj:SetLocalPosition(action)
    end
end


function Core:SetEvent(action)
    if action == Def.ActionList.Enter or action == Def.ActionList.Exit then
        self.event_obj:EnterOrExitVehicle(self.player_obj)
    elseif action == Def.ActionList.ChangeCamera then
        self:ToggleCamera()
    elseif action == Def.ActionList.ChangeDoor1 then
        self.event_obj:ChangeDoor()
    end
end

function Core:ToggleCamera()
    if self.event_obj:IsInVehicle() then
        local res = self.av_obj.camera_obj:Toggle()
        if res == Def.CameraDistanceLevel.Fpp then
            self.player_obj:ActivateTPPHead(false)
        elseif res == Def.CameraDistanceLevel.TppClose then
            self.player_obj:ActivateTPPHead(true)
        end
    end
end

return Core
