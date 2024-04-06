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
    obj.relative_resolution = 0.1

    -- set default parameters
    obj.input_table = {}
    obj.current_custom_mappin_position = {x = 0, y = 0, z = 0}

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

    self:SetInputListener()
    self:SetCustomMappinPosition()

end

function Core:Reset()

    self.player_obj = Player:New(Game.GetPlayer())
    self.player_obj:Init()

    self.av_obj = AV:New(self.all_models)
    self.av_obj:Init()

    self.event_obj:Init(self.av_obj)

end

function Core:SetInputListener()

    local player = Game.GetPlayer()

    player:RegisterInputListener(player, "dav_rotate_move")

    local exception_list = Utils:ReadJson("Data/exception_input.json")

    Observe("PlayerPuppet", "OnAction", function(this, action, consumer)
        local action_name = action:GetName(action).value
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
            for _, exception in pairs(exception_list) do
                if string.find(action_name, exception) then
                    consumer:Consume()
                    return
                end
            end
        end

        if DAV.is_debug_mode then
            DAV.debug_obj:PrintActionCommand(action_name, action_type, action_value)
        end

        self:StorePlayerAction(action_name, action_type, action_value)

    end)

end

function Core:SetCustomMappinPosition()

    Observe('BaseWorldMapMappinController', 'SelectMappin', function(this)
		local mappin = this.mappin
        if mappin:GetVariant() == gamedataMappinVariant.CustomPositionVariant then
            local pos = mappin:GetWorldPosition()
            self.current_custom_mappin_position = {x = pos.x, y = pos.y, z = pos.z}
        end

	end)

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

    local cmd, loop_count = self:ConvertActionList(action_name, action_type, action_value_type, action_value)

    for _ = 1, loop_count do
        if cmd ~= Def.ActionList.Nothing then
            self.queue_obj:Enqueue(cmd)
        end
    end

end

function Core:ConvertActionList(action_name, action_type, action_value_type, action_value)

    local action_command = Def.ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value_type}
    local loop_count = 1

    if Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_ACCELERTOR) then
        action_command = Def.ActionList.Up
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_DOWN) then
        action_command = Def.ActionList.Down
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_FORWARD_MOVE) then
        action_command = Def.ActionList.Forward
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_BACK_MOVE) then
        action_command = Def.ActionList.Backward
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_RIGHT_MOVE) then
        action_command = Def.ActionList.Right
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_LEFT_MOVE) then
        action_command = Def.ActionList.Left
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_RIGHT_ROTATE) then
        action_command = Def.ActionList.TurnRight
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_LEFT_ROTATE) then
        action_command = Def.ActionList.TurnLeft
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_HOVER) then
        action_command = Def.ActionList.Hover
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_HOLD) then
        action_command = Def.ActionList.Hold
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_WORLD_ENTER_AV) then
        action_command = Def.ActionList.Enter
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_EXIT_AV) then
        action_command = Def.ActionList.Exit
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_CAMERA) then
        action_command = Def.ActionList.ChangeCamera
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_TOGGLE_DOOR_1) then
        action_command = Def.ActionList.ChangeDoor1
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_UP_CAMERA_MOUSE) then
        action_command = Def.ActionList.CamUp
        loop_count = math.floor(math.abs(action_value) * self.relative_resolution) + 1
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_UP_CAMERA_JOYSTICK) then
        action_command = Def.ActionList.CamUp
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_DOWN_CAMERA_MOUSE) then
        action_command = Def.ActionList.CamDown
        loop_count = math.floor(math.abs(action_value) * self.relative_resolution) + 1
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_DOWN_CAMERA_JOYSTICK) then
        action_command = Def.ActionList.CamDown
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_RIGHT_CAMERA_MOUSE) then
        action_command = Def.ActionList.CamRight
        loop_count = math.floor(math.abs(action_value) * self.relative_resolution) + 1
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_RIGHT_CAMERA_JOYSTICK) then
        action_command = Def.ActionList.CamRight
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_LEFT_CAMERA_MOUSE) then
        action_command = Def.ActionList.CamLeft
        loop_count = math.floor(math.abs(action_value) * self.relative_resolution) + 1
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_LEFT_CAMERA_JOYSTICK) then
        action_command = Def.ActionList.CamLeft
    else
        action_command = Def.ActionList.Nothing
    end

    return action_command, loop_count

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
        -- if res == Def.CameraDistanceLevel.Fpp then
        --     self.player_obj:ActivateTPPHead(false)
        -- elseif res == Def.CameraDistanceLevel.TppClose then
        --     self.player_obj:ActivateTPPHead(true)
        -- end
    end

end

return Core
