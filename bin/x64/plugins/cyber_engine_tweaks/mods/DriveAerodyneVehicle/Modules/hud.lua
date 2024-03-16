local Log = require("Tools/log.lua")
local Hud = {}
Hud.__index = Hud

function Hud:New()

    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Hud")

    -- set default parameters
    obj.interaction_ui_base = nil
    obj.interaction_hub = nil
    obj.choice_title = "AV"
	obj.hud_car_controller = nil

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


return Hud