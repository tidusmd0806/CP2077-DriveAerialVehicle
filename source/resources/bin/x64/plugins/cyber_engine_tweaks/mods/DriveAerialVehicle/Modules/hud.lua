-- local GameSettings = require('External/GameSettings.lua')
local GameHUD = require('External/GameHUD.lua')
local Utils = require("Etc/utils.lua")
local HUD = {}
HUD.__index = HUD

--- Constractor
---@return table
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
    obj.is_keyboard_input = true
    obj.input_hint_mapping_table = {}
    obj.input_hint_controller = nil
    obj.key_input_show_hint_event = nil
    obj.key_input_hide_hint_event = nil
    obj.current_input_hint_count = 0
    obj.icon_texture_atlas = ResRef.FromName("base\\gameplay\\gui\\common\\input\\icons_keyboard.inkatlas")
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

--- Initialize
---@param av_obj any AV instance
function HUD:Init(av_obj)
    self.av_obj = av_obj
    self.vehicle_hp = 100

    if not DAV.is_ready then
        self:SetOverride()
        self:SetObserve()
        GameHUD.Initialize()
    end

    self.input_hint_mapping_table = Utils:ReadJson("Data/input_hint_mapping.json")
end

--- Set Override Functions
function HUD:SetOverride()
    if not DAV.is_ready then
        -- Overside choice ui (refer to https://www.nexusmods.com/cyberpunk2077/mods/7299)
        Override("InteractionUIBase", "OnDialogsData", function(_, value, wrapped_method)
            if self.av_obj:IsPlayerInEntryArea() then
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
            if self.av_obj:IsPlayerInEntryArea() then
                wrapped_method(self.selected_choice_index - 1)
            else
                self.selected_choice_index = index + 1
                wrapped_method(index)
            end
        end)

        Override("dialogWidgetGameController", "OnDialogsActivateHub", function(_, id, wrapped_metthod) -- Avoid interaction getting overriden by game
            if self.av_obj:IsPlayerInEntryArea() then
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

--- Set Observe Functions
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
                if not DAV.user_setting_table.is_enable_destruction then
                    self.vehicle_hp = 100
                else
                    self.vehicle_hp = destruction
                end
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

        ObserveAfter("gameuiPhotoModeMenuController", "OnPhotoModeLastInputDeviceEvent", function(this, wasKeyboardMouse)
            if wasKeyboardMouse then
                self.is_keyboard_input = true
            else
                self.is_keyboard_input = false
            end
            local compound_widget = this:GetRootCompoundWidget()
            if compound_widget == nil then
                self.log_obj:Record(LogLevel.Error, "compound_widget is nil")
                return
            end
            local input_panel = compound_widget:GetWidget("input_panel")
            if input_panel == nil then
                self.log_obj:Record(LogLevel.Error, "input_panel is nil")
                return
            end
            local input_light_pad = input_panel:GetWidget("inputLightPad")
            if input_light_pad == nil then
                self.log_obj:Record(LogLevel.Error, "inputLightPad is nil")
                return
            end
            local camera_control_pad = input_light_pad:GetWidget("cameraControlPad")
            if camera_control_pad == nil then
                self.log_obj:Record(LogLevel.Error, "cameraControlPad is nil")
                return
            end
            local move = camera_control_pad:GetWidget("move")
            if move == nil then
                self.log_obj:Record(LogLevel.Error, "move is nil")
                return
            end
            local input_root = move:GetWidget("inputRoot")
            if input_root == nil then
                self.log_obj:Record(LogLevel.Error, "inputRoot is nil")
                return
            end
            local input_icon = input_root:GetWidget("inputIcon")
            if input_icon == nil then
                self.log_obj:Record(LogLevel.Error, "inputIcon is nil")
                return
            end
            self.icon_texture_atlas = input_icon.textureAtlas
        end)
    end
end

--- Show Left Bottom HUD
function HUD:ShowLeftBottomHUD()
    self:SetVisibleConsumeItemSlot(false)
    self:CreateHPDisplay()

    if self.is_active_hp_display then
        self:SetHPDisplay()
        self.ink_horizontal_panel:SetVisible(true)
    end
end

--- Hide Left Bottom HUD
function HUD:HideLeftBottomHUD()
    self:SetVisibleConsumeItemSlot(true)

    if self.is_active_hp_display then
        self.ink_horizontal_panel:SetVisible(false)
    end
end

--- Check Consume Item Slot HUD
---@return boolean
function HUD:IsVisibleConsumeItemSlot()
    return self.hud_consumable_controller:GetRootCompoundWidget().visible
end

--- (Unused) Check Phone Slot HUD
---@return boolean
function HUD:IsVisiblePhoneSlot()
    return self.hud_phone_controller:GetRootCompoundWidget().visible
end

--- Set Visible Consume Item Slot
---@param is_visible boolean
function HUD:SetVisibleConsumeItemSlot(is_visible)
    self.hud_consumable_controller:GetRootCompoundWidget():SetVisible(is_visible)
end

--- (Unused) Set Visible Phone Slot
---@param is_visible boolean
function HUD:SetVisiblePhoneSlot(is_visible)
    self.hud_phone_controller:GetRootCompoundWidget():SetVisible(is_visible)
end

--- Show Meter HUD
---@return boolean
function HUD:ForceShowMeter()
    if self.hud_car_controller == nil then
        self.log_obj:Record(LogLevel.Error, "hud_car_controller is nil")
        self.is_active_hp_display = false
        return false
    end

    self.hud_car_controller:ShowRequest()
    self.hud_car_controller:OnCameraModeChanged(true)

    return true
end

--- Create HP Display
---@return boolean
function HUD:CreateHPDisplay()
    if DAV.is_valid_vehicle_durability_display then
        return false
    end

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

--- Set HP Display
function HUD:SetHPDisplay()
    if DAV.is_valid_vehicle_durability_display then
        return
    end
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

--- Enable Manual Meter
---@param is_manual_speed boolean
---@param is_manual_rpm boolean
function HUD:EnableManualMeter(is_manual_speed, is_manual_rpm)
    self.is_manually_setting_speed = is_manual_speed
    self.is_manually_setting_rpm = is_manual_rpm
end

--- Set Speed Meter Value
---@param speed_value number
function HUD:SetSpeedMeterValue(speed_value)
    if self.hud_car_controller == nil or not self.is_manually_setting_speed then
        return
    end
    inkTextRef.SetText(self.hud_car_controller.SpeedValue, speed_value)
end

--- Set RPM Meter Value
---@param rpm_value number
function HUD:SetRPMMeterValue(rpm_value)
    if self.hud_car_controller == nil or not self.is_manually_setting_rpm then
        return
    end
    self.hud_car_controller:EvaluateRPMMeterWidget(rpm_value)
end

--- Toggle Original MPH Display On/Off
---@param on boolean
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

--- Get Choice Title
--- @return string
function HUD:GetChoiceTitle()
    local index = DAV.model_index
    return GetLocalizedText("LocKey#" .. tostring(self.av_obj.all_models[index].display_name_lockey))
end

--- Set Choice List
function HUD:SetChoiceList()
    local model_index = DAV.model_index
    local tmp_list = {}

    local hub = gameinteractionsvisListChoiceHubData.new()
    hub.title = self:GetChoiceTitle()
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
    hub.hubPriority = 1
    hub.id = 77777 + math.random(99999)

    local choice_type = gameinteractionsChoiceTypeWrapper.new()
    choice_type:SetType(gameinteractionsChoiceType.Selected)

    for index, seat in pairs(self.av_obj.active_seat) do
        local caption_part = gameinteractionsChoiceCaption.new()
        local choice = gameinteractionsvisListChoiceData.new()

        local lockey_enter = GetLocalizedText("LocKey#36505") or "Enter"
        local localized_seat_name = DAV.core_obj:GetTranslationText("hud_interaction_seat_" .. self.av_obj.all_models[model_index].active_seat[index])
        choice.localizedName = lockey_enter .. " [" .. localized_seat_name .. "]"
        if self.av_obj.is_armed and seat == "seat_front_left" then
            local icon_weapon = TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceCaptionParts.GunIcon")
            caption_part:AddPartFromRecord(icon_weapon)
        else
            local icon_normal = TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceCaptionParts.SitIcon")
            caption_part:AddPartFromRecord(icon_normal)
        end
        choice.inputActionName = CName.new("None")
        choice.captionParts = caption_part
        choice.type = choice_type
        table.insert(tmp_list, choice)
    end
    hub.choices = tmp_list

    self.interaction_hub = hub
end

--- Show Choice
--- @param selected_index number
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

--- Hide Choice
function HUD:HideChoice()
    if self.interaction_hub == nil then
        return
    end

    self.interaction_hub = nil

    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions;
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)

    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)
    if self.interaction_ui_base == nil then
        return
    end
    self.interaction_ui_base:OnDialogsData(data)
end

--- Set Input Hint Controller
---@return boolean
function HUD:SetInputHintController()
    local ink_system = Game.GetInkSystem()
    if not ink_system then
        self.log_obj:Record(LogLevel.Error, "ink_system is nil")
        return false
    end

    local hud_layer = ink_system:GetLayer(CName.new("inkHUDLayer"))
    if not hud_layer then
        self.log_obj:Record(LogLevel.Error, "hud_layer is nil")
        return false
    end

    local game_controllers = hud_layer:GetGameControllers()
    if not game_controllers then
        self.log_obj:Record(LogLevel.Error, "game_controllers is nil")
        return false
    end

    for _, controller in ipairs(game_controllers) do
        if controller and controller:ToString() == "gameuiInputHintManagerGameController" then
            self.input_hint_controller = controller
            return true
        end
    end
    self.log_obj:Record(LogLevel.Error, "input_hint_controller is nil")
    return false
end

function HUD:ReconstructInputHint()
    if self.input_hint_controller == nil then
        self.log_obj:Record(LogLevel.Error, "input_hint_controller is nil")
        return
    end

    local input_hint_widget = self.input_hint_controller:GetRootCompoundWidget():GetWidget("mainContainer"):GetWidget("hints")
    if not input_hint_widget then
        self.log_obj:Record(LogLevel.Error, "input_hint_widget is nil")
        return
    end

    -- Load input hint override configuration
    local input_hint_override = Utils:ReadJson("Data/input_hint_override.json")
    if not input_hint_override then
        self.log_obj:Record(LogLevel.Error, "Failed to load input_hint_override.json")
        return
    end

    -- Determine flight mode and input method
    local flight_mode = self.av_obj.engine_obj.flight_mode
    local is_keyboard_input = self.is_keyboard_input
    local mode_name = (flight_mode == Def.FlightMode.AV) and "AV" or "Helicopter"
    
    -- Get the appropriate hint configuration for current mode
    local hint_configs = input_hint_override[mode_name]
    if not hint_configs then
        self.log_obj:Record(LogLevel.Error, "No hint configuration found for mode: " .. mode_name)
        return
    end

    -- Get appropriate keybind tables based on flight mode
    local keybind_table = DAV.user_setting_table.keybind_table
    local heli_keybind_table = DAV.user_setting_table.heli_keybind_table
    local common_keybind_table = DAV.user_setting_table.common_keybind_table

    -- Create hint widgets for each configuration
    for _, config in ipairs(hint_configs) do
        local hint_num = config.no
        local title = DAV.core_obj:GetTranslationText(config.title) or config.title
        local actions = config.actions

        -- Get texture parts for each action
        local texture_parts = {}
        local used_texture_parts = {}
        for i, action in ipairs(actions) do
            local key_binding = self:FindKeyBinding(action, keybind_table, heli_keybind_table, common_keybind_table, flight_mode)
            if key_binding then
                local key_code = is_keyboard_input and key_binding.key or key_binding.pad
                local is_hold = key_binding.is_hold or false
                local texture_part = self:GetTexturePartFromKeyCode(key_code, is_hold)
                
                -- Skip if this texture part has already been used (avoid duplicates)
                if texture_part ~= "" and used_texture_parts[texture_part] then
                    texture_parts[i] = ""
                    self.log_obj:Record(LogLevel.Info, "Action: " .. action .. ", Texture: " .. texture_part .. " (skipped - duplicate)")
                else
                    texture_parts[i] = texture_part
                    if texture_part ~= "" then
                        used_texture_parts[texture_part] = true
                    end
                    self.log_obj:Record(LogLevel.Info, "Action: " .. action .. ", Key: " .. (key_code or "nil") .. ", Hold: " .. tostring(is_hold) .. ", Texture: " .. texture_part)
                end
            else
                -- Use empty string instead of nil to indicate no texture
                texture_parts[i] = ""
                self.log_obj:Record(LogLevel.Warning, "No key binding found for action: " .. action)
            end
        end

        -- Ensure we have exactly 4 texture parts (pad with empty string if needed)
        while #texture_parts < 4 do
            texture_parts[#texture_parts + 1] = ""
        end

        -- Create and add the hint widget
        local hint_widget = self:CreateOrUpdateHintWidget(hint_num, title, texture_parts, true)
        if hint_widget then
            hint_widget:Reparent(input_hint_widget)
            self.log_obj:Record(LogLevel.Info, "Created hint widget: " .. title)
        end

    end
end

--- Find key binding for a specific action
---@param action string
---@param keybind_table table
---@param heli_keybind_table table
---@param common_keybind_table table
---@param flight_mode number
---@return table|nil
function HUD:FindKeyBinding(action, keybind_table, heli_keybind_table, common_keybind_table, flight_mode)
    -- First check common keybinds (always available)
    for _, binding in ipairs(common_keybind_table) do
        if binding.name == action then
            return binding
        end
    end

    -- Check helicopter-specific keybinds if in helicopter mode
    if flight_mode == Def.FlightMode.Helicopter then
        for _, binding in ipairs(heli_keybind_table) do
            if binding.name == action then
                return binding
            end
        end
    end

    -- Check general keybinds
    for _, binding in ipairs(keybind_table) do
        if binding.name == action then
            return binding
        end
    end

    return nil
end

--- Get texture part from key code using mapping table
---@param key_code string
---@param is_hold boolean
---@return string
function HUD:GetTexturePartFromKeyCode(key_code, is_hold)
    local base_texture_part = ""
    
    if not key_code or key_code == "IK_None" then
        base_texture_part = ""
        self.log_obj:Record(LogLevel.Debug, "Key code is nil or IK_None, using default: " .. base_texture_part)
    else
        -- Use mapping table if available
        if self.input_hint_mapping_table then
            local input_type = self.is_keyboard_input and "keyboard" or "gamepad"
            local mapping_section = self.input_hint_mapping_table[input_type]
            
            if mapping_section and mapping_section[key_code] then
                base_texture_part = mapping_section[key_code]
                self.log_obj:Record(LogLevel.Debug, "Found " .. input_type .. " mapping for " .. key_code .. ": " .. base_texture_part)
            else
                base_texture_part = ""
                self.log_obj:Record(LogLevel.Debug, "No " .. input_type .. " mapping found for " .. key_code .. ", using default: " .. base_texture_part)
            end
        else
            base_texture_part = ""
            self.log_obj:Record(LogLevel.Debug, "No mapping table available, using default: " .. base_texture_part)
        end
    end
    
    -- Add "_hold" suffix if is_hold is true, but not for axis controls or thumb controls
    if is_hold and base_texture_part ~= "" and not string.find(base_texture_part, "axis") and not string.find(base_texture_part, "thumb") then
        return base_texture_part .. "_hold"
    else
        return base_texture_part
    end
end

--- Create main hint widget container
---@param num number
---@param enable boolean
---@return inkFlex
function HUD:CreateMainHintWidget(num, enable)
    local main_widget = inkFlex.new()
    main_widget:SetName(StringToName("hint_" .. num))
    main_widget:SetSize(100.0, 100.0)
    main_widget:SetVisible(enable or true)
    return main_widget
end

--- Create hint panel container
function HUD:CreateHintPanel()
    local hint_panel = inkHorizontalPanel.new()
    hint_panel:SetName(StringToName("hint"))
    hint_panel:SetStyle(ResRef.FromName("base\\gameplay\\gui\\common\\main_colors.inkstyle"))
    hint_panel:SetHAlign(inkEHorizontalAlign.Left)
    hint_panel:SetVAlign(inkEVerticalAlign.Top)
    return hint_panel
end

--- Create wrapper panel for text label
function HUD:CreateWrapperPanel()
    local wrapper_panel = inkHorizontalPanel.new()
    wrapper_panel:SetName(StringToName("wrapper"))
    wrapper_panel:SetHAlign(inkEHorizontalAlign.Right)
    wrapper_panel:SetVAlign(inkEVerticalAlign.Center)
    wrapper_panel:SetMargin(20, 0, 0, 0)
    return wrapper_panel
end

--- Create text label widget
---@param text string
function HUD:CreateTextLabel(text)
    local text_label = inkText.new()
    text_label:SetName(StringToName("label"))
    text_label:SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily")
    text_label:SetFontStyle("Medium")
    text_label:SetFontSize(44)
    text_label:SetJustificationType(textJustificationType.Right)
    text_label:SetHorizontalAlignment(textHorizontalAlignment.Right)
    text_label:SetVerticalAlignment(textVerticalAlignment.Center)
    text_label:SetFitToContent(false)
    text_label:SetSize(700.0, 48.0)
    text_label:SetStyle(ResRef.FromName("base\\gameplay\\gui\\common\\main_colors.inkstyle"))
    text_label:BindProperty("tintColor", "MainColors.Red")
    text_label:BindProperty("fontStyle", "MainColors.BodyFontWeight")
    text_label:SetHAlign(inkEHorizontalAlign.Right)
    text_label:SetVAlign(inkEVerticalAlign.Center)
    text_label:SetScrollTextSpeed(0.3)
    text_label:SetText(text or "")
    return text_label
end

--- Create keys container panel
function HUD:CreateKeysPanel()
    local keys_panel = inkHorizontalPanel.new()
    keys_panel:SetName(StringToName("keys"))
    keys_panel:SetHAlign(inkEHorizontalAlign.Right)
    keys_panel:SetVAlign(inkEVerticalAlign.Center)
    keys_panel:SetMargin(20, 0, 0, 0)
    keys_panel:SetSizeRule(inkESizeRule.Stretch)
    return keys_panel
end

--- Create flex widget container for key icons
---@param num number
---@return inkFlex
function HUD:CreateKeyFlexWidget(num)
    local flex_widget = inkFlex.new()
    flex_widget:SetName(StringToName("KeyFlexWidget_" .. num))
    flex_widget:SetStyle(ResRef.FromName("base\\gameplay\\gui\\common\\main_colors.inkstyle"))
    flex_widget:SetSize(100.0, 100.0)
    return flex_widget
end

--- Create key panel container
---@return inkHorizontalPanel
function HUD:CreateKeyPanel()
    local key_panel = inkHorizontalPanel.new()
    key_panel:SetName(StringToName("inkHorizontalPanelWidget22"))
    key_panel:SetHAlign(inkEHorizontalAlign.Left)
    key_panel:SetVAlign(inkEVerticalAlign.Top)
    key_panel:SetSize(75.0, 75.0)
    key_panel:SetInteractive(true)
    return key_panel
end

--- Create hold container for key animation
---@return inkCanvas
function HUD:CreateHoldContainer()
    local hold_container = inkCanvas.new()
    hold_container:SetName(StringToName("holdContainer"))
    hold_container:SetHAlign(inkEHorizontalAlign.Left)
    hold_container:SetVAlign(inkEVerticalAlign.Top)
    hold_container:SetSize(64.0, 75.0)
    hold_container:SetChildOrder(inkEChildOrder.Backward)
    return hold_container
end

--- Create horizontal panel for key icon
---@return inkHorizontalPanel
function HUD:CreateKeyIconPanel()
    local icon_panel = inkHorizontalPanel.new()
    icon_panel:SetName(StringToName("keyIconPanel"))
    icon_panel:SetHAlign(inkEHorizontalAlign.Left)
    icon_panel:SetVAlign(inkEVerticalAlign.Center)
    icon_panel:SetMargin(-64, 0, 0, 0)
    return icon_panel
end

--- Create input icon image
---@param texture_part string
function HUD:CreateInputIcon(texture_part)
    local input_icon = inkImage.new()
    input_icon:SetName(StringToName("inputIcon"))
    
    -- Use appropriate texture atlas based on current input method
    local texture_atlas = self.icon_texture_atlas
    if texture_atlas then
        input_icon:SetAtlasResource(texture_atlas)
    end
    
    if texture_part and texture_part ~= "" then
        input_icon:SetVisible(true)
        input_icon:SetTexturePart(texture_part)
    else
        input_icon:SetVisible(false)
    end
    input_icon:SetAnchor(inkEAnchor.Centered)
    input_icon:SetHAlign(inkEHorizontalAlign.Center)
    input_icon:SetVAlign(inkEVerticalAlign.Center)
    input_icon:SetSize(64.0, 64.0)
    input_icon:SetStyle(ResRef.FromName("base\\gameplay\\gui\\common\\main_colors.inkstyle"))
    input_icon:BindProperty("tintColor", "MainColors.Blue")
    return input_icon
end

--- Create input AND text widget
function HUD:CreateInputANDText()
    local input_and = inkText.new()
    input_and:SetName(CName.new("InputAND"))
    input_and:SetVisible(false)
    return input_and
end

--- Create complete hint widget
---@param num number
---@param text string
---@param texture_parts table
---@return inkFlex | nil
function HUD:CreateOrUpdateHintWidget(num, text, texture_parts, enable)
    -- Check if input_hint_controller is available
    if not self.input_hint_controller then
        self.log_obj:Record(LogLevel.Warning, "input_hint_controller not available, creating widget without duplicate check")
    else
        -- Check if widget with the same name already exists
        local input_hint_widget = self.input_hint_controller:GetRootCompoundWidget():GetWidget("mainContainer"):GetWidget("hints")
        if input_hint_widget then
            local widget_name = "hint_" .. num
            local existing_widget = input_hint_widget:GetWidget(StringToName(widget_name))
            if existing_widget then
                self.log_obj:Record(LogLevel.Info, "Widget " .. widget_name .. " already exists, updating existing widget")
                existing_widget:SetVisible(enable or true)
                existing_widget:GetWidget("hint"):GetWidget("wrapper"):GetWidget("label"):SetText(text or "")
                for i = 1, 4 do
                    local key_flex_widget = existing_widget:GetWidget("hint"):GetWidget("keys"):GetWidget(StringToName("KeyFlexWidget_" .. i))
                    if key_flex_widget then
                        local key_panel = key_flex_widget:GetWidget("inkHorizontalPanelWidget22")
                        if key_panel then
                            local key_icon_panel = key_panel:GetWidget("keyIconPanel")
                            if key_icon_panel then
                                local icon_widget = key_icon_panel:GetWidget("inputIcon")
                                if icon_widget then
                                    if texture_parts[i] and texture_parts[i] ~= "" then
                                        icon_widget:SetVisible(true)
                                        icon_widget:SetTexturePart(texture_parts[i])
                                        -- Use appropriate texture atlas based on current input method
                                        local texture_atlas = self.icon_texture_atlas
                                        if texture_atlas then
                                            icon_widget:SetAtlasResource(texture_atlas)
                                        end
                                    else
                                        icon_widget:SetVisible(false)  -- Hide icon if no texture part provided
                                    end
                                end
                            end
                        end
                    end
                end
                return nil
            end
        end
    end

    -- Create all widgets
    local main_widget = self:CreateMainHintWidget(num, enable)
    if not main_widget then
        self.log_obj:Record(LogLevel.Error, "Failed to create main_widget")
        return nil
    end

    local hint_panel = self:CreateHintPanel()
    local wrapper_panel = self:CreateWrapperPanel()
    local text_label = self:CreateTextLabel(text)
    local keys_panel = self:CreateKeysPanel()
    local key_flex_widget_list = {}
    local key_panel_list = {}
    local hold_container_list = {}
    local key_icon_panel_list = {}
    local input_icon_list = {}
    local input_and_list = {}
    for i = 1, 4 do
        key_flex_widget_list[i] = self:CreateKeyFlexWidget(i)
        key_panel_list[i] = self:CreateKeyPanel()
        hold_container_list[i] = self:CreateHoldContainer()
        key_icon_panel_list[i] = self:CreateKeyIconPanel()
        input_icon_list[i] = self:CreateInputIcon(texture_parts[i])  -- Use different texture for each icon
        input_and_list[i] = self:CreateInputANDText()
    end

    for i = 1, 4 do
        input_icon_list[i]:Reparent(key_icon_panel_list[i])
        input_and_list[i]:Reparent(key_icon_panel_list[i])
        hold_container_list[i]:Reparent(key_panel_list[i])
        key_icon_panel_list[i]:Reparent(key_panel_list[i])
        key_panel_list[i]:Reparent(key_flex_widget_list[i])
        key_flex_widget_list[i]:Reparent(keys_panel)
    end
    text_label:Reparent(wrapper_panel)
    wrapper_panel:Reparent(hint_panel)
    keys_panel:Reparent(hint_panel)
    hint_panel:Reparent(main_widget)

    return main_widget
end

--- Set Custom Hint
function HUD:SetCustomHint()
    local flight_mode = self.av_obj.engine_obj.flight_mode
    local is_keyboard_input = self.is_keyboard_input
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
            if not self.av_obj:IsMountedCombatSeat() and hint.source == "DrawWeapon" then
                table.remove(hint_table, index)
            end
        end
    end
    self.current_input_hint_count = #hint_table
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

--- Show Custom Hint
function HUD:ShowCustomHint()
    if not self.av_obj:IsMountedCombatSeat() then
        self:DeleteInputHint("DrawWeapon")
    end
    self:SetCustomHint()
    Game.GetUISystem():QueueEvent(self.key_input_show_hint_event)
    Cron.Every(0.1, {tick=1}, function(timer)
        timer.tick = timer.tick + 1
        if timer.tick > 100 then
            self.log_obj:Record(LogLevel.Error, "ReconstructInputHint not called after 1 second, stopping")
            Cron.Halt(timer)
            return
        end
        self:SetInputHintController()
        if self:CheckVisibleSomeInputHint() then
            self:ReconstructInputHint()
            self.log_obj:Record(LogLevel.Info, "ReconstructInputHint called")
            Cron.After(1.5, function()
                self:ReconstructInputHint()
            end)
            Cron.Halt(timer)
            return
        end
    end)
end

--- Hide Custom Hint
function HUD:HideCustomHint()
    Game.GetUISystem():QueueEvent(self.key_input_hide_hint_event)
end

--- Delete Custom Hint
function HUD:DeleteInputHint(name)
    local delete_hint_event = DeleteInputHintBySourceEvent.new()
    delete_hint_event.targetHintContainer = CName.new("GameplayInputHelper")
    delete_hint_event.source = CName.new(name)
    Game.GetUISystem():QueueEvent(delete_hint_event)
end

function HUD:CheckVisibleSomeInputHint()
    if self.input_hint_controller == nil then
        self.log_obj:Record(LogLevel.Error, "input_hint_controller is nil")
        return false
    end

    local main_container = self.input_hint_controller:GetRootCompoundWidget():GetWidget("mainContainer")
    if main_container == nil then
        self.log_obj:Record(LogLevel.Warning, "main_container is nil")
        return false
    end

    local hints_widget = main_container:GetWidget("hints")
    if hints_widget == nil then
        self.log_obj:Record(LogLevel.Warning, "hints_widget is nil")
        return false
    end

    for i = 0, 50 do
        local hint_widget = hints_widget:GetWidget(i)
        if hint_widget ~= nil then
            if hint_widget:IsVisible() then
                self.log_obj:Record(LogLevel.Trace, "Visible input hint found: " .. hint_widget:GetName().value)
                return true
            end
        else
            break
        end
    end
    return false
end

--- Show Message when auto pilot is on.
function HUD:ShowAutoModeDisplay()
    local text = GetLocalizedText("LocKey#84945")
    GameHUD.ShowMessage(text)
end

--- Show Message when drive mode is on.
function HUD:ShowDriveModeDisplay()
    local text = GetLocalizedText("LocKey#84944")
    GameHUD.ShowMessage(text)
end

--- Show Message when vehicle is arrived.
function HUD:ShowArrivalDisplay()
    local text = GetLocalizedText("LocKey#77994")
    GameHUD.ShowMessage(text)
end

--- Show Message when autopilot is interrupted.
function HUD:ShowInterruptAutoPilotDisplay()
    local text = GetLocalizedText("LocKey#15321")
    GameHUD.ShowWarning(text, 2)
end

--- Show Radio Popup
function HUD:ShowRadioPopup()
    if self.popup_manager ~= nil then
        self.popup_manager:SpawnVehicleRadioPopup()
    end
end

--- Show Vehicle Manager Popup
function HUD:ShowVehicleManagerPopup()
    if self.popup_manager ~= nil then
        self.popup_manager:SpawnVehiclesManagerPopup()
    end
end

return HUD