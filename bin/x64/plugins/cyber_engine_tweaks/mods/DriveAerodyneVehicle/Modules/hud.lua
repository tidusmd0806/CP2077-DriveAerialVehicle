local Log = require("Tools/log.lua")
local Hud = {}
Hud.__index = Hud

function Hud:New(engine_obj)

    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Hud")

    -- set default parameters
    obj.engine_obj = engine_obj
    obj.interaction_ui_base = nil
    obj.interaction_hub = nil
    obj.choice_title = "AV"
	obj.hud_car_controller = nil

    obj.is_speed_meter_shown = false

    return setmetatable(obj, self)
end

function Hud:Init(choice_title)

    self:SetOverride()
    self:SetObserve()
    self:SetChoiceTitle(choice_title)

end

function Hud:SetOverride()

    -- Overside choice ui (refer to https://www.nexusmods.com/cyberpunk2077/mods/7299)
    Override("InteractionUIBase", "OnDialogsData", function(_, arg_1, wrapped_method)
        local data = FromVariant(arg_1)
        local hubs = data.choiceHubs
        table.insert(hubs, self.interaction_hub)
        data.choiceHubs = hubs
        wrapped_method(ToVariant(data))
    end)

	Override("OpenVendorUI", "CreateInteraction", function(this, arg_1, arg_2, arg_3, wrapped_method)
        if this:GetActionName().value == "vehicle_door_quest_locked" then
            self.log_obj:Record(LogLevel.Debug, "Anti vehicle door quest locked")
            return
        end
        wrapped_method(arg_1, arg_2, arg_3)
    end)

end

function Hud:SetObserve()

    Observe("InteractionUIBase", "OnInitialize", function(this)
        self.interaction_ui_base = this
    end)

    Observe("InteractionUIBase", "OnDialogsData", function(this)
        self.interaction_ui_base = this
    end)

	Observe("hudCarController", "OnInitialize", function(this)
        self.hud_car_controller = this
    end)

end

function Hud:SetChoiceTitle(title)
    self.choice_title = title
end

function Hud:ShowChoice()

    local choice = gameinteractionsvisListChoiceData.new()
    choice.localizedName = GetLocalizedText("LocKey#81569")
    choice.inputActionName = CName.new("click")

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
        DAV.Cron.Every(1, function()
            local coordinate_speed = math.sqrt(self.engine_obj.horizenal_x_speed * self.engine_obj.horizenal_x_speed 
                                                + self.engine_obj.horizenal_y_speed * self.engine_obj.horizenal_y_speed 
                                                + self.engine_obj.vertical_speed * self.engine_obj.vertical_speed)
            local mph = coordinate_speed * (3600 / 1600)
            local power_level = math.floor((self.engine_obj.lift_force - self.engine_obj.min_lift_force) / ((self.engine_obj.max_lift_force - self.engine_obj.min_lift_force) / 10))
            self.hud_car_controller:OnSpeedValueChanged(mph / 3)
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

return Hud