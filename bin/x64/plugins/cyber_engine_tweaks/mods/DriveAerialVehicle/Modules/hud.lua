-- local GameSettings = require('External/GameSettings.lua')
local GameHUD = require('External/GameHUD.lua')
local Utils = require("Tools/utils.lua")
local HUD = {}
HUD.__index = HUD

function HUD:New()
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "HUD")
    obj.av_obj = nil
    -- static --
    -- dynamic --
    -- hud controller
	obj.hud_car_controller = nil
    obj.hud_consumable_controller = nil
    obj.hud_phone_controller = nil
    obj.is_manually_setting_speed = false
    obj.is_manually_setting_rpm = false
    -- input hint
    obj.key_input_show_hint_event = nil
    obj.key_input_hide_hint_event = nil
    -- interaction choice
    obj.selected_choice_index = 1
    obj.interaction_ui_base = nil
    obj.interaction_hub = nil
    -- popups
    obj.popup_manager = nil
    -- HP display
    obj.is_active_hp_display = false
    obj.vehicle_hp = 0
    obj.ink_horizontal_panel = nil
    obj.ink_hp_title = nil
    obj.ink_hp_text = nil

    return setmetatable(obj, self)
end

function HUD:Init(av_obj)

    self.av_obj = av_obj
    self.vehicle_hp = 100

    if not DAV.is_ready then
        self:SetOverride()
        self:SetObserve()
        GameHUD.Initialize()
    end

end

function HUD:SetOverride()

    if not DAV.is_ready then
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

        Override("InteractionUIBase", "OnDialogsSelectIndex", function(_, index, wrapped_method)
            if self.av_obj.position_obj:IsPlayerInEntryArea() then
                wrapped_method(self.selected_choice_index - 1)
            else
                self.selected_choice_index = index + 1
                wrapped_method(index)
            end
        end)

        Override("dialogWidgetGameController", "OnDialogsActivateHub", function(_, id, wrapped_metthod) -- Avoid interaction getting overriden by game
            if self.av_obj.position_obj:IsPlayerInEntryArea() then
                local id_
                if self.interaction_hub == nil then
                    id_ = id
                else
                    id_ = self.interaction_hub.id
                end
                return wrapped_metthod(id_)
            else
                return wrapped_metthod(id)
            end
        end)

        Override("hudCarController", "OnSpeedValueChanged", function(this, speedValue, wrappedMethod)
            local result = true
            if not self.is_manually_setting_speed then
                result = wrappedMethod(speedValue)
            end
            return result
        end)

        Override("hudCarController", "OnRpmValueChanged", function(this, rpmValue, wrappedMethod)
            local result = true
            if not self.is_manually_setting_rpm then
                result = wrappedMethod(rpmValue)
            end
            return result
        end)


    end

end

function HUD:SetObserve()

    if not DAV.is_ready then
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

        Observe('PopupsManager', 'OnPlayerAttach', function(this)
            self.popup_manager = this
        end)

        Observe("VehicleComponent", "EvaluateDamageLevel", function(this, destruction)
            if self.av_obj.entity_id == nil then
                return
            end
            if this:GetEntity():GetEntityID().hash == self.av_obj.entity_id.hash then
                self.vehicle_hp = destruction
            end
        end)

        Observe("HotkeyConsumableWidgetController", "OnInitialize", function(this)
            self.hud_consumable_controller = this
        end)

        Observe("PhoneHotkeyController", "Initialize", function(this)
            self.hud_phone_controller = this
        end)

        local exception_hint_table = Utils:ReadJson("Data/exception_input_hint.json")
        ObserveAfter("UISystem", "QueueEvent", function(this, event)
            if DAV.core_obj.event_obj:IsInVehicle() and event:IsA("gameuiUpdateInputHintEvent") then
                for _, hint in ipairs(exception_hint_table) do
                    if event.data.action == CName.new(hint) then
                        if event.show then
                            event.show = false
                            this:QueueEvent(event)
                        end
                    end
                end
            end
        end)
    end

end

function HUD:ShowLeftBottomHUD()

    self:SetVisibleConsumeItemSlot(false)
    -- self:SetVisiblePhoneSlot(false)
    self:CreateHPDisplay()

    if self.is_active_hp_display then
        self:SetHPDisplay()
        self.ink_horizontal_panel:SetVisible(true)
    end

end

function HUD:HideLeftBottomHUD()

    self:SetVisibleConsumeItemSlot(true)
    -- self:SetVisiblePhoneSlot(true)

    if self.is_active_hp_display then
        self.ink_horizontal_panel:SetVisible(false)
    end

end

function HUD:IsVisibleConsumeItemSlot()
    return self.hud_consumable_controller:GetRootCompoundWidget().visible
end

function HUD:IsVisiblePhoneSlot()
    return self.hud_phone_controller:GetRootCompoundWidget().visible
end

function HUD:SetVisibleConsumeItemSlot(is_visible)
    self.hud_consumable_controller:GetRootCompoundWidget():SetVisible(is_visible)
end

function HUD:SetVisiblePhoneSlot(is_visible)
    self.hud_phone_controller:GetRootCompoundWidget():SetVisible(is_visible)
end

function HUD:CreateHPDisplay()

    if self.hud_car_controller == nil then
        self.log_obj:Record(LogLevel.Error, "hud_car_controller is nil")
        self.is_active_hp_display = false
        return false
    end
    local parent = self.hud_car_controller:GetRootCompoundWidget():GetWidget("maindashcontainer")
    if parent == nil then
        self.log_obj:Record(LogLevel.Error, "maindashcontainer is nil")
        self.is_active_hp_display = false
        return false
    elseif parent:GetWidget("hp") ~= nil then
        self.log_obj:Record(LogLevel.Trace, "hp widget already exists")
        self.is_active_hp_display = true
        return false
    end

    self.ink_horizontal_panel = inkHorizontalPanel.new()
    self.ink_horizontal_panel:SetName(CName.new("hp"))
    self.ink_horizontal_panel:SetAnchor(inkEAnchor.CenterRight)
    self.ink_horizontal_panel:SetMargin(0, 0, -35, 13)
    self.ink_horizontal_panel:SetFitToContent(false)
    self.ink_horizontal_panel:Reparent(parent)

    self.ink_hp_title = inkText.new()
    self.ink_hp_title:SetName(CName.new("title"))
    self.ink_hp_title:SetText(GetLocalizedText("LocKey#91867"))
    self.ink_hp_title:SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily")
    self.ink_hp_title:SetFontStyle("Medium")
    self.ink_hp_title:SetFontSize(15)
    self.ink_hp_title:SetOpacity(0.4)
    self.ink_hp_title:SetMargin(0, 15, 0, 0)
    self.ink_hp_title:SetFitToContent(true)
    self.ink_hp_title:SetJustificationType(textJustificationType.Right)
    self.ink_hp_title:SetHorizontalAlignment(textHorizontalAlignment.Right)
    self.ink_hp_title:SetVerticalAlignment(textVerticalAlignment.Center)
    self.ink_hp_title:SetStyle(ResRef.FromName("base\\gameplay\\gui\\common\\main_colors.inkstyle"))
    self.ink_hp_title:BindProperty("tintColor", "MainColors.Red")
    self.ink_hp_title:Reparent(self.ink_horizontal_panel)

    self.ink_hp_text = inkText.new()
    self.ink_hp_text:SetName(CName.new("text"))
    self.ink_hp_text:SetText("100")
    self.ink_hp_text:SetFontFamily("base\\gameplay\\gui\\fonts\\digital_readout\\digitalreadout.inkfontfamily")
    self.ink_hp_text:SetFontStyle("Regular")
    self.ink_hp_text:SetFontSize(25)
    self.ink_hp_text:SetFitToContent(true)
    self.ink_hp_text:SetJustificationType(textJustificationType.Left)
    self.ink_hp_text:SetHorizontalAlignment(textHorizontalAlignment.Left)
    self.ink_hp_text:SetStyle(ResRef.FromName("base\\gameplay\\gui\\common\\main_colors.inkstyle"))
    self.ink_hp_text:BindProperty("tintColor", "MainColors.Blue")
    self.ink_hp_text:Reparent(self.ink_horizontal_panel)

    self.is_active_hp_display = true
    return true

end

function HUD:SetHPDisplay()

    local hp_value = self.vehicle_hp
    hp_value = math.floor(hp_value)
    local hp_text
    if hp_value < 100 and hp_value >= 10 then
        hp_text = " " .. tostring(hp_value)
    elseif hp_value < 10 then
        hp_text = "  " .. tostring(hp_value)
    else
        hp_text = tostring(hp_value)
    end
    if self.ink_hp_text == nil then
        return
    end
    self.ink_hp_text:SetText(hp_text)

end

function HUD:EnableManualMeter(is_manual_speed, is_manual_rpm)
    self.is_manually_setting_speed = is_manual_speed
    self.is_manually_setting_rpm = is_manual_rpm
end

---@param speed_value number
function HUD:SetSpeedMeterValue(speed_value)
    if self.hud_car_controller == nil or not self.is_manually_setting_speed then
        return
    end
    inkTextRef.SetText(self.hud_car_controller.SpeedValue, speed_value)
end

---@param rpm_value number
function HUD:SetRPMMeterValue(rpm_value)
    if self.hud_car_controller == nil or not self.is_manually_setting_rpm then
        return
    end
    self.hud_car_controller:EvaluateRPMMeterWidget(rpm_value)
end

function HUD:ToggleOriginalMPHDisplay(on)
    if self.hud_car_controller == nil then
        return
    end
    local mph_text = self.hud_car_controller:GetRootCompoundWidget():GetWidget("maindashcontainer"):GetWidget("dynamic"):GetWidget("mph_text")
    if on then
        mph_text:SetText(GetLocalizedText("LocKey#78030"))
    else
        mph_text:SetText(GetLocalizedText("LocKey#95281"))
    end
end

function HUD:GetChoiceTitle()
    local index = DAV.model_index
    return GetLocalizedText("LocKey#" .. tostring(self.av_obj.all_models[index].display_name_lockey))
end

function HUD:SetChoiceList()

    local model_index = DAV.model_index
    local tmp_list = {}

    local hub = gameinteractionsvisListChoiceHubData.new()
    hub.title = self:GetChoiceTitle()
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
    hub.hubPriority = 1
    hub.id = 69420 + math.random(99999)

    local icon = TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceCaptionParts.CourierIcon")
    local caption_part = gameinteractionsChoiceCaption.new()
    local choice_type = gameinteractionsChoiceTypeWrapper.new()
    caption_part:AddPartFromRecord(icon)
    choice_type:SetType(gameinteractionsChoiceType.Selected)

    for index = 1, #self.av_obj.active_seat do
        local choice = gameinteractionsvisListChoiceData.new()

        local lockey_enter = GetLocalizedText("LocKey#81569") or "Enter"
        local localized_seat_name = DAV.core_obj:GetTranslationText("hud_interaction_seat_" .. self.av_obj.all_models[model_index].active_seat[index])
        choice.localizedName = lockey_enter .. "[" .. localized_seat_name .. "]"
        choice.inputActionName = CName.new("None")
        choice.captionParts = caption_part
        choice.type = choice_type
        table.insert(tmp_list, choice)
    end
    hub.choices = tmp_list

    self.interaction_hub = hub
end

function HUD:ShowChoice(selected_index)

    self.selected_choice_index = selected_index

    self:SetChoiceList()

    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)

    interaction_blackboard:SetInt(ui_interaction_define.ActiveChoiceHubID, self.interaction_hub.id)
    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)
    self.dialogIsScrollable = true
    self.interaction_ui_base:OnDialogsSelectIndex(selected_index - 1)
    self.interaction_ui_base:OnDialogsData(data)
    self.interaction_ui_base:OnInteractionsChanged()
    self.interaction_ui_base:UpdateListBlackboard()
    self.interaction_ui_base:OnDialogsActivateHub(self.interaction_hub.id)

end

function HUD:HideChoice()

    self.interaction_hub = nil

    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions;
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)

    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)
    if self.interaction_ui_base == nil then
        return
    end
    self.interaction_ui_base:OnDialogsData(data)

end

function HUD:SetCustomHint()
    local flight_mode = self.av_obj.engine_obj.flight_mode
    local is_keyboard_input = DAV.is_keyboard_input
    local hint_table = {}
    hint_table = Utils:ReadJson("Data/input_hint.json")
    self.key_input_show_hint_event = UpdateInputHintMultipleEvent.new()
    self.key_input_hide_hint_event = UpdateInputHintMultipleEvent.new()
    self.key_input_show_hint_event.targetHintContainer = CName.new("GameplayInputHelper")
    self.key_input_hide_hint_event.targetHintContainer = CName.new("GameplayInputHelper")
    -- delete unnecessary hint
    for index = #hint_table, 1, -1 do
        local hint = hint_table[index]
        if hint.mode ~= flight_mode and hint.mode ~= -1 then
            table.remove(hint_table, index)
        else
            if is_keyboard_input then
                if hint.usage == "gamepad" then
                    table.remove(hint_table, index)
                end
            else
                if hint.usage == "keyboard" then
                    table.remove(hint_table, index)
                end
            end
        end
    end
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

function HUD:ShowCustomHint()
    self:SetCustomHint()
    Game.GetUISystem():QueueEvent(self.key_input_show_hint_event)
end

function HUD:HideCustomHint()
    Game.GetUISystem():QueueEvent(self.key_input_hide_hint_event)
end

function HUD:ShowAutoModeDisplay()
    local text = GetLocalizedText("LocKey#84945")
    GameHUD.ShowMessage(text)
end

function HUD:ShowDriveModeDisplay()
    local text = GetLocalizedText("LocKey#84944")
    GameHUD.ShowMessage(text)
end

function HUD:ShowArrivalDisplay()
    local text = GetLocalizedText("LocKey#77994")
    GameHUD.ShowMessage(text)
end

function HUD:ShowInterruptAutoPilotDisplay()
    local text = GetLocalizedText("LocKey#15321")
    GameHUD.ShowWarning(text, 2)
end

function HUD:ShowRadioPopup()
    if self.popup_manager ~= nil then
        self.popup_manager:SpawnVehicleRadioPopup()
    end
end

function HUD:ShowVehicleManagerPopup()
    if self.popup_manager ~= nil then
        self.popup_manager:SpawnVehiclesManagerPopup()
    end
end

return HUD