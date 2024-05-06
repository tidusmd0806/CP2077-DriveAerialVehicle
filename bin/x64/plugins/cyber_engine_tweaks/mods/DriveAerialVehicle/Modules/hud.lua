local GameSettings = require('External/GameSettings.lua')
local GameHUD = require('External/GameHUD.lua')
local Utils = require("Tools/utils.lua")
local HUD = {}
HUD.__index = HUD

function HUD:New()
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "HUD")
    --static --
    obj.speed_meter_refresh_rate = 0.05
    -- dynamic --
    obj.av_obj = nil
    obj.interaction_ui_base = nil
    obj.interaction_hub = nil
    obj.choice_title = "AV"
	obj.hud_car_controller = nil

    obj.is_speed_meter_shown = false
    obj.key_input_show_hint_event = nil
    obj.key_input_hide_hint_event = nil

    obj.selected_choice_index = 1

    obj.is_forced_autopilot_panel = false

    obj.popup_manager = nil

    return setmetatable(obj, self)
end

function HUD:Init(av_obj)

    self.av_obj = av_obj

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
        choice.localizedName = lockey_enter .. "[" .. self.av_obj.all_models[model_index].active_seat[index] .. "]"
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

function HUD:ShowMeter()

    self.hud_car_controller:ShowRequest()
    self.hud_car_controller:OnCameraModeChanged(true)

    if self.is_speed_meter_shown then
        return
    else
        self.is_speed_meter_shown = true
        Cron.Every(self.speed_meter_refresh_rate, {tick = 0}, function(timer)
            local meter_value = 0    
            if self.av_obj.is_auto_pilot then
                inkTextRef.SetText(self.hud_car_controller.SpeedUnits, DAV.core_obj:GetTranslationText("hud_meter_auto_pilot_display"))
                meter_value = math.floor(Vector4.Distance(self.av_obj.auto_pilot_info.dist_pos, Game.GetPlayer():GetWorldPosition()))
            else
                if DAV.user_setting_table.is_unit_km_per_hour then
                    inkTextRef.SetText(self.hud_car_controller.SpeedUnits, DAV.core_obj:GetTranslationText("hud_meter_kph"))
                    meter_value = math.floor(self.av_obj.engine_obj.current_speed * (3600 / 1000))
                else
                    inkTextRef.SetText(self.hud_car_controller.SpeedUnits,  DAV.core_obj:GetTranslationText("hud_meter_mph"))
                    meter_value = math.floor(self.av_obj.engine_obj.current_speed * (3600 / 1609))
                end
            end
            inkTextRef.SetText(self.hud_car_controller.SpeedValue, meter_value)

            local power_level = 0
            if self.av_obj.is_auto_pilot then
                local distance = Vector4.Distance(self.av_obj.auto_pilot_info.dist_pos, self.av_obj.auto_pilot_info.start_pos)
                power_level = math.floor((1.01 - (meter_value / distance)) * 10)
            else
                if DAV.user_setting_table.flight_mode == Def.FlightMode.Heli then
                    power_level = math.floor((self.av_obj.engine_obj.lift_force - self.av_obj.engine_obj.min_lift_force) / ((self.av_obj.engine_obj.max_lift_force - self.av_obj.engine_obj.min_lift_force) / 10))
                elseif DAV.user_setting_table.flight_mode == Def.FlightMode.Spinner then 
                    power_level = math.floor(self.av_obj.engine_obj.spinner_horizenal_force / (self.av_obj.engine_obj.max_spinner_horizenal_force / 10))
                end
            end
            self.hud_car_controller:OnRpmValueChanged(power_level)
            self.hud_car_controller:EvaluateRPMMeterWidget(power_level)
            if not self.is_speed_meter_shown then
                Cron.Halt(timer)
            end
        end)
    end

end

function HUD:HideMeter()
    self.hud_car_controller:HideRequest()
    self.hud_car_controller:OnCameraModeChanged(false)
    self.is_speed_meter_shown = false
end

function HUD:SetCustomHint()
    local hint_table = {}
    if DAV.user_setting_table.flight_mode == Def.FlightMode.Heli then
        hint_table = Utils:ReadJson("Data/heli_key_hint.json")
    elseif DAV.user_setting_table.flight_mode == Def.FlightMode.Spinner then
        hint_table = Utils:ReadJson("Data/spinner_key_hint.json")
    end
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

function HUD:ShowCustomHint()
    self:SetCustomHint()
    Game.GetUISystem():QueueEvent(self.key_input_show_hint_event)
end

function HUD:HideCustomHint()
    Game.GetUISystem():QueueEvent(self.key_input_hide_hint_event)
end

function HUD:ShowActionButtons()
    GameSettings.Set('/interface/hud/action_buttons', true)
end

function HUD:HideActionButtons()
    GameSettings.Set('/interface/hud/action_buttons', false)
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
    local text = GetLocalizedText("LocKey#52322")
    GameHUD.ShowWarning(text, 2)
end

function HUD:ShowAutoPilotInfo()
    if (DAV.user_setting_table.is_autopilot_info_panel and not DAV.core_obj.event_obj:IsInMenuOrPopupOrPhoto() and DAV.core_obj.event_obj:IsInVehicle()) or self.is_forced_autopilot_panel then

		local screen_w, screen_h = GetDisplayResolution()
        local window_w = screen_w * 0.25
        local window_w_margin = screen_w * 0.01
        local window_h_margin = screen_h * 0.1

		ImGui.SetNextWindowPos(window_w_margin, screen_h - window_h_margin)
        ImGui.SetNextWindowSize(window_w, 0)

		ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 8)
		ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 8, 7)
		ImGui.PushStyleColor(ImGuiCol.WindowBg, 0xaa000000)
		ImGui.PushStyleColor(ImGuiCol.Border, 0x8ffefd01)

		ImGui.Begin('AutoPilotInfo', ImGuiWindowFlags.NoDecoration)

        local switch = ""
        local location = ""
        local type = ""
        if self.av_obj.is_auto_pilot then
            switch = DAV.core_obj:GetTranslationText("hud_auto_pilot_panel_on")
            location = DAV.core_obj.av_obj.auto_pilot_info.location
            type = DAV.core_obj.av_obj.auto_pilot_info.type
        else
            switch = DAV.core_obj:GetTranslationText("hud_auto_pilot_panel_off")
            if DAV.core_obj:IsCustomMappin() then
                local dist_near_ft_index = DAV.core_obj:GetFTIndexNearbyMappin()
                local dist_district_list = DAV.core_obj:GetNearbyDistrictList(dist_near_ft_index)
                if dist_district_list ~= nil then
                    for index, district in ipairs(dist_district_list) do
                        location = location .. district
                        if index ~= #dist_district_list then
                            location = location .. "/"
                        end
                    end
                end
                local nearby_location = DAV.core_obj:GetNearbyLocation(dist_near_ft_index)
                if nearby_location ~= nil then
                    location = location .. "/" .. nearby_location
                    local custom_ft_distance = DAV.core_obj:GetFT2MappinDistance()
                    if custom_ft_distance ~= DAV.core_obj.huge_distance then
                        location = location .. "[" .. tostring(math.floor(custom_ft_distance)) .. "m]"
                    end
                end
                type = DAV.core_obj:GetTranslationText("hud_auto_pilot_panel_selection_custom_mappin")
            else
                location = DAV.user_setting_table.favorite_location_list[DAV.core_obj.event_obj.ui_obj.selected_auto_pilot_favorite_index].name
                type = DAV.core_obj:GetTranslationText("hud_auto_pilot_panel_selection_favorite")
            end
        end
        ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("hud_auto_pilot_panel_title"))
        ImGui.SameLine()
        ImGui.TextColored(0.058, 1, 0.937, 1, switch)
        ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("hud_auto_pilot_panel_distination"))
        ImGui.SameLine()
        ImGui.TextColored(0.058, 1, 0.937, 1, location)
        ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("hud_auto_pilot_panel_selection"))
        ImGui.SameLine()
        ImGui.TextColored(0.058, 1, 0.937, 1, type)

		ImGui.End()

		ImGui.PopStyleColor(2)
		ImGui.PopStyleVar(2)
	end
end

function HUD:ShowRadioPopup()
    if self.popup_manager ~= nil then
        self.popup_manager:SpawnVehicleRadioPopup()
    end
end

return HUD