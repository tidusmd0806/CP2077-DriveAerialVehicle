local AV = require("Modules/av.lua")
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
    obj.event_obj = nil

    obj.all_models = nil
    obj.input_table = nil

    obj.av_model_path = "Data/default_model.json"
    obj.input_path = "Data/input.json"
    obj.axis_dead_zone = 0.5
    obj.relative_dead_zone = 0.01
    obj.relative_table = {}
    obj.relative_resolution = 0.1
    obj.hold_progress = 0.9

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

    self.av_obj = AV:New(self.all_models)
    self.av_obj:Init()

    self.event_obj:Init(self.av_obj)

end

function Core:SetInputListener()

    local player = Game.GetPlayer()

    player:UnregisterInputListener(player, "dav_accelerate")
    player:UnregisterInputListener(player, "dav_y_move")
    player:UnregisterInputListener(player, "dav_x_move")
    player:UnregisterInputListener(player, "dav_rotate_move")
    player:UnregisterInputListener(player, "dav_hover")
    player:UnregisterInputListener(player, "dav_get_on")
    player:UnregisterInputListener(player, "dav_get_off")
    player:UnregisterInputListener(player, "dav_change_view")
    player:UnregisterInputListener(player, "dav_toggle_door_1")
    player:UnregisterInputListener(player, "dav_toggle_auto_pilot")

    player:RegisterInputListener(player, "dav_accelerate")
    player:RegisterInputListener(player, "dav_y_move")
    player:RegisterInputListener(player, "dav_x_move")
    player:RegisterInputListener(player, "dav_rotate_move")
    player:RegisterInputListener(player, "dav_hover")
    player:RegisterInputListener(player, "dav_get_on")
    player:RegisterInputListener(player, "dav_get_off")
    player:RegisterInputListener(player, "dav_change_view")
    player:RegisterInputListener(player, "dav_toggle_door_1")
    player:RegisterInputListener(player, "dav_toggle_auto_pilot")

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
            self.av_obj:SetDestination(pos)
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
    elseif action_type == "BUTTON_HOLD_PROGRESS" then
        if action_value > self.hold_progress then
            action_value_type = "POSITIVE"
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
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_AV_TOGGLE_AUTO_PILOT) then
        action_command = Def.ActionList.AutoPilot
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_WORLD_SELECT_UPPER_CHOICE) then
        action_command = Def.ActionList.SelectUp
    elseif Utils:IsTablesNearlyEqual(action_dist, self.input_table.KEY_WORLD_SELECT_LOWER_CHOICE) then
        action_command = Def.ActionList.SelectDown
    else
        action_command = Def.ActionList.Nothing
    end

    return action_command, loop_count

end

function Core:GetActions()

    local move_actions = {}

    if self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.queue_obj:Clear()
        return
    end

    while not self.queue_obj:IsEmpty() do
        local action = self.queue_obj:Dequeue()
        if action >= Def.ActionList.Enter then
            self:SetEvent(action)
        else
            table.insert(move_actions, action)
        end
    end

    if #move_actions == 0 then
        table.insert(move_actions, Def.ActionList.Nothing)
    end

    self:OperateAerialVehicle(move_actions)

end

function Core:OperateAerialVehicle(actions)

    if not self.is_locked_operation then
        if self.event_obj:IsInVehicle() then
            self.av_obj:Operate(actions)
        elseif self.event_obj:IsWaiting() then
            self.av_obj:Operate({Def.ActionList.Nothing})
        end
    end

end

function Core:SetEvent(action)

    if action == Def.ActionList.Enter then
        self.event_obj:EnterVehicle()
    elseif action == Def.ActionList.Exit then
        self.event_obj:ExitVehicle()
    elseif action == Def.ActionList.ChangeCamera then
        self:ToggleCamera()
    elseif action == Def.ActionList.ChangeDoor1 then
        self.event_obj:ChangeDoor()
    elseif action == Def.ActionList.AutoPilot then
        self.event_obj:ToggleAutoMode()
    elseif action == Def.ActionList.SelectUp then
        self.event_obj:SelectChoice(Def.ActionList.SelectUp)
    elseif action == Def.ActionList.SelectDown then
        self.event_obj:SelectChoice(Def.ActionList.SelectDown)
    end

end

function Core:ToggleCamera()

    if self.event_obj:IsInVehicle() then
        self.av_obj.camera_obj:Toggle()
    end

end

return Core
