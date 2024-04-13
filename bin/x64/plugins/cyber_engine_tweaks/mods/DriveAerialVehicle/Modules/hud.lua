local GameSettings = require('External/GameSettings.lua')
local GameHUD = require('External/GameHUD.lua')
local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Hud = {}
Hud.__index = Hud

function Hud:New()

    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Hud")

    -- set default parameters
    obj.av_obj = nil
    obj.interaction_ui_base = nil
    obj.interaction_hub = nil
    obj.choice_title = "AV"
	obj.hud_car_controller = nil

    obj.is_speed_meter_shown = false
    obj.key_input_show_hint_event = nil
    obj.key_input_hide_hint_event = nil
    obj.speed_meter_refresh_rate = 0.2

    return setmetatable(obj, self)
end

function Hud:Init(av_obj)

    self.av_obj = av_obj

    if not DAV.ready then
        self:SetOverride()
        self:SetObserve()
        GameHUD.Initialize()
    end
    self:SetChoiceTitle()
    self:SetCustomHint()

end

function Hud:SetOverride()

    if not DAV.ready then
        -- Overside choice ui (refer to https://www.nexusmods.com/cyberpunk2077/mods/7299)
        Override("InteractionUIBase", "OnDialogsData", function(_, value, wrapped_method)
            if self.av_obj.position_obj:IsPlayerInEntryArea() then
                local data = FromVariant(value)
                local hubs = data.choiceHubs
                table.insert(hubs, self.interaction_hub)
                data.choiceHubs = hubs
                wrapped_method(ToVariant(data))
            else
                wrapped_method(value)
            end
        end)
    end

end

function Hud:SetObserve()

    if not DAV.ready then   
        Observe("InteractionUIBase", "OnInitialize", function(this)
            self.interaction_ui_base = this
        end)

        Observe("InteractionUIBase", "OnDialogsData", function(this)
            self.interaction_ui_base = this
        end)

        Observe("hudCarController", "OnInitialize", function(this)
            self.hud_car_controller = this
        end)

        Observe("hudCarController", "OnMountingEvent", function(this)
            self.hud_car_controller = this
        end)

        -- hide unnecessary input hint
        Observe("UISystem", "QueueEvent", function(this, event)
            if DAV.core_obj.event_obj:IsInEntryArea() or DAV.core_obj.event_obj:IsInVehicle() then
                if event:ToString() == "gameuiUpdateInputHintEvent" then
                    if event.data.source == CName.new("VehicleDriver") then
                        local delete_hint_source_event = DeleteInputHintBySourceEvent.new()
                        delete_hint_source_event.targetHintContainer = CName.new("GameplayInputHelper")
                        delete_hint_source_event.source = CName.new("VehicleDriver")
                        Game.GetUISystem():QueueEvent(delete_hint_source_event)
                    end
                end
            end
        end)
    end

end

function Hud:SetChoiceTitle()
    local index = DAV.model_index
    self.choice_title = GetLocalizedText("LocKey#" .. tostring(self.av_obj.all_models[index].display_name_lockey))
end

function Hud:ShowChoice()

    local choice = gameinteractionsvisListChoiceData.new()
    choice.localizedName = GetLocalizedText("LocKey#81569")
    choice.inputActionName = CName.new("Choice2")

    local hub = gameinteractionsvisListChoiceHubData.new()
    hub.title = self.choice_title
    hub.choices = {choice}
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
    hub.hubPriority = 1
    hub.id = 6083991

    self.interaction_hub = hub

    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions;
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)

    interaction_blackboard:SetInt(ui_interaction_define.ActiveChoiceHubID, self.interaction_hub.id)
    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)
    self.interaction_ui_base:OnDialogsData(data)

end

function Hud:HideChoice()

    self.interaction_hub = nil

    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions;
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)

    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)
    self.interaction_ui_base:OnDialogsData(data)

end

function Hud:ShowMeter()
    self.hud_car_controller:ShowRequest()
    self.hud_car_controller:OnCameraModeChanged(true)

    if self.is_speed_meter_shown then
        return
    else
        self.is_speed_meter_shown = true
        DAV.Cron.Every(self.speed_meter_refresh_rate, function()
            local mph = self.av_obj.engine_obj.current_speed * (3600 / 1600)
            local power_level = math.floor((self.av_obj.engine_obj.lift_force - self.av_obj.engine_obj.min_lift_force) / ((self.av_obj.engine_obj.max_lift_force - self.av_obj.engine_obj.min_lift_force) / 10))
            self.hud_car_controller:OnSpeedValueChanged(mph / 4.58)
            self.hud_car_controller:OnRpmValueChanged(power_level)
            self.hud_car_controller:EvaluateRPMMeterWidget(power_level)
            if not self.is_speed_meter_shown then
                DAV.Cron.Halt()
            end
        end)
    end
end

function Hud:HideMeter()
    self.hud_car_controller:HideRequest()
    self.hud_car_controller:OnCameraModeChanged(false)
    self.is_speed_meter_shown = false
end

function Hud:SetCustomHint()
    local hint_table = Utils:ReadJson("Data/key_hint.json")
    self.key_input_show_hint_event = UpdateInputHintMultipleEvent.new()
    self.key_input_hide_hint_event = UpdateInputHintMultipleEvent.new()
    self.key_input_show_hint_event.targetHintContainer = CName.new("GameplayInputHelper")
    self.key_input_hide_hint_event.targetHintContainer = CName.new("GameplayInputHelper")
    for _, hint in ipairs(hint_table) do
        local input_hint_data = InputHintData.new()
        input_hint_data.source = CName.new(hint.source)
        input_hint_data.action = CName.new(hint.action)
        if hint.holdIndicationType == "FromInputConfig" then
            input_hint_data.holdIndicationType = inkInputHintHoldIndicationType.FromInputConfig
        elseif hint.holdIndicationType == "Hold" then
            input_hint_data.holdIndicationType = inkInputHintHoldIndicationType.Hold
        elseif hint.holdIndicationType == "Press" then
            input_hint_data.holdIndicationType = inkInputHintHoldIndicationType.Press
        else 
            input_hint_data.holdIndicationType = inkInputHintHoldIndicationType.FromInputConfig
        end
        input_hint_data.sortingPriority = hint.sortingPriority
        input_hint_data.enableHoldAnimation = hint.enableHoldAnimation
        local keys = string.gmatch(hint.localizedLabel, "LocKey#(%d+)")
        local localizedLabels = {}
        for key in keys do
            table.insert(localizedLabels, GetLocalizedText("LocKey#" .. key))
        end
        input_hint_data.localizedLabel = table.concat(localizedLabels, "-")
        self.key_input_show_hint_event:AddInputHint(input_hint_data, true)
        self.key_input_hide_hint_event:AddInputHint(input_hint_data, false)
    end
end

function Hud:ShowCustomHint()
    Game.GetUISystem():QueueEvent(self.key_input_show_hint_event)
end

function Hud:HideCustomHint()
    Game.GetUISystem():QueueEvent(self.key_input_hide_hint_event)
end

function Hud:ShowActionButtons()
    GameSettings.Set('/interface/hud/action_buttons', true)
end

function Hud:HideActionButtons()
    -- GameSettings.Set('/interface/hud/action_buttons', false)
end

function Hud:ShowAutoModeDisplay()
    local text = GetLocalizedText("LocKey#84945")
    GameHUD.ShowMessage(text)
end

function Hud:ShowDriveModeDisplay()
    local text = GetLocalizedText("LocKey#84944")
    GameHUD.ShowMessage(text)
end

function Hud:ShowArrivalDisplay()
    local text = GetLocalizedText("LocKey#77994")
    GameHUD.ShowMessage(text)
end

function Hud:ShowInterruptAutoPilotDisplay()
    local text = "Auto Pilot has been interrupted"
    GameHUD.ShowWarning(text, 2)
end

return Hud