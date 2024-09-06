local Utils = require("Tools/utils.lua")
local UI = {}
UI.__index = UI

function UI:New()
	-- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "UI")
	-- static --
	-- record name
    obj.dummy_vehicle_record = "Vehicle.av_dav_dummy"
	obj.delay_updating_native_settings = 0.1
	-- dynamic --
	-- common
	obj.av_obj = nil
	obj.dummy_av_record = nil
	obj.av_record_list = {}
	-- auto pilot setting
	obj.selected_auto_pilot_history_index = 1
	obj.selected_auto_pilot_history_name = ""
	obj.history_list = {}
	-- autopilot setting popup
	obj.ui_game_menu_controller = nil
	obj.autopilot_popup_obj = nil
	obj.current_position_name = ""
	-- native settings page
	obj.option_table_list = {}
	obj.is_activate_vehicle_switch = false
	obj.selected_flight_mode_index = 1
    return setmetatable(obj, self)
end

function UI:Init(av_obj)
	self.av_obj = av_obj
	self:SetObserver()
	self:SetTweekDB()
	self:CreateNativeSettingsBasePage()
end

function UI:SetTweekDB()

	for _, model in ipairs(self.av_obj.all_models) do
		local av_record = TweakDBID.new(model.tweakdb_id)
		table.insert(self.av_record_list, av_record)
	end

end

function UI:SetObserver()

	if not DAV.is_ready then
		Observe('gameuiInGameMenuGameController', 'RegisterInputListenersForPlayer', function(this, player)
			if player:IsControlledByLocalPeer() then
				self.ui_game_menu_controller = this
			end
		end)
	end

end

function UI:OpenAutopilotPopup()

	if self.ui_game_menu_controller == nil then
		self.log_obj:Record(LogLevel.Error, "Do not exist game menu controller.")
		return
	end

	if self.autopilot_popup_obj == nil then
		self.autopilot_popup_obj = DAV_AerialVehiclePopupWrapper.new()
		self.autopilot_popup_obj:Create()
		self:SetPopupTranslation()
		self.autopilot_popup_obj:Show(self.ui_game_menu_controller)
		Cron.After(0.1, function()
			-- Set Destination
			local mappin_location = ""
			if DAV.core_obj:IsCustomMappin() then
                local dist_near_ft_index = DAV.core_obj:GetFTIndexNearbyMappin()
                local dist_district_list = DAV.core_obj:GetNearbyDistrictList(dist_near_ft_index)
                if dist_district_list ~= nil then
                    for index, district in ipairs(dist_district_list) do
                        mappin_location = mappin_location .. district
                        if index ~= #dist_district_list then
                            mappin_location = mappin_location .. "/"
                        end
                    end
                end
                local nearby_location = DAV.core_obj:GetNearbyLocation(dist_near_ft_index)
                if nearby_location ~= nil then
                    mappin_location = mappin_location .. "/" .. nearby_location
                    local custom_ft_distance = DAV.core_obj:GetFT2MappinDistance()
                    if custom_ft_distance ~= DAV.core_obj.huge_distance then
                        mappin_location = mappin_location .. "[" .. tostring(math.floor(custom_ft_distance)) .. "m]"
                    end
                end
            else
				mappin_location = DAV.core_obj:GetTranslationText("ui_popup_not_selected")
            end
			-- Set Favorite List
			local favorite_name_list = {}
			for _, favorite_info in ipairs(DAV.user_setting_table.favorite_location_list) do
				if favorite_info.name == "Not Registered" then
					favorite_info.name = DAV.core_obj:GetTranslationText("ui_popup_not_registered")
				end
				table.insert(favorite_name_list, favorite_info.name)
			end
			-- Set Current Position
			local current_position_name = ""
			local current_district_list = DAV.core_obj:GetCurrentDistrict()
			local entity = Game.FindEntityByID(self.av_obj.entity_id)
			if entity ~= nil then
				local current_nearby_ft_index, current_nearby_ft_distance = DAV.core_obj:FindNearestFastTravelPosition(entity:GetWorldPosition())
				local current_nearby_ft_name = DAV.core_obj:GetNearbyLocation(current_nearby_ft_index)
				if current_district_list ~= nil then
					for _, district in ipairs(current_district_list) do
						current_position_name = current_position_name .. district .. "/"
					end
				end
				if current_nearby_ft_name ~= nil then
					current_position_name = current_position_name .. current_nearby_ft_name
				end
				if current_nearby_ft_distance ~= DAV.core_obj.huge_distance then
					current_position_name = current_position_name .. "[" .. tostring(math.floor(current_nearby_ft_distance)) .. "m]"
				end

			else
				current_position_name = ""
			end
			self.autopilot_popup_obj:Initialize(favorite_name_list, mappin_location, current_position_name, DAV.user_setting_table.autopilot_selected_index)
			Cron.Every(0.1, {tick = 1}, function(timer)
				if self.autopilot_popup_obj:IsClosed() then
					DAV.user_setting_table.autopilot_selected_index = self.autopilot_popup_obj:GetSelectedNumber()
					local favorite_list = self.autopilot_popup_obj:GetFavoriteList()
					self:UpdateFavoriteLocationList(favorite_list, DAV.user_setting_table.autopilot_selected_index)
					self.autopilot_popup_obj = nil
					Cron.Halt(timer)
				end
			end)
		end)
	end

end

function UI:SetPopupTranslation()

	if self.autopilot_popup_obj ~= nil then
		self.autopilot_popup_obj:SetTranslation("ui_popup_title", DAV.core_obj:GetTranslationText("ui_popup_title"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_header", GetLocalizedText("LocKey#" .. tostring(self.av_obj.all_models[DAV.model_index].display_name_lockey)))
		self.autopilot_popup_obj:SetTranslation("ui_popup_footer", DAV.core_obj:GetTranslationText("ui_popup_footer"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_destination_title", DAV.core_obj:GetTranslationText("ui_popup_destination_title"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_destination_button", DAV.core_obj:GetTranslationText("ui_popup_destination_button"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_destination_input_hint", DAV.core_obj:GetTranslationText("ui_popup_destination_input_hint"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_favorite_title", DAV.core_obj:GetTranslationText("ui_popup_favorite_title"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_favorite_input_hint", DAV.core_obj:GetTranslationText("ui_popup_favorite_input_hint"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_register_title", DAV.core_obj:GetTranslationText("ui_popup_register_title"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_register_input_hint", DAV.core_obj:GetTranslationText("ui_popup_register_input_hint"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_register_confirm_title", DAV.core_obj:GetTranslationText("ui_popup_register_confirm_title"))
		self.autopilot_popup_obj:SetTranslation("ui_popup_register_confirm_text", DAV.core_obj:GetTranslationText("ui_popup_register_confirm_text"))
	end

end

function UI:UpdateFavoriteLocationList(favorite_list, selected_index)
	for index, favorite_info in ipairs(DAV.user_setting_table.favorite_location_list) do
		if favorite_info.name ~= favorite_list[index] then
			favorite_info.name = favorite_list[index]
			local current_pos = self.av_obj.position_obj:GetPosition()
			favorite_info.pos = {x=current_pos.x, y=current_pos.y, z=current_pos.z}
		end
		if index == selected_index then
			favorite_info.is_selected = true
			DAV.core_obj:SetFavoriteMappin(DAV.user_setting_table.favorite_location_list[index].pos)
		else
			favorite_info.is_selected = false
		end
	end
	Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
end

function UI:CreateStringHistory()
	self.history_list = {}
	for index, history in ipairs(DAV.user_setting_table.mappin_history) do
		local history_string = tostring(index) .. ": "
		for _, district in ipairs(history.district) do
			history_string = history_string .. district .. "/"
		end
		history_string = history_string .. history.location
		history_string = history_string .. " [" .. tostring(math.floor(history.distance)) .. "m]"
		table.insert(self.history_list, history_string)
	end
end

function UI:CreateNativeSettingsBasePage()
	DAV.NativeSettings.addTab("/DAV", DAV.core_obj:GetTranslationText("native_settings_top_title"))
	DAV.NativeSettings.registerRestoreDefaultsCallback("/DAV", true, function()
		print('[DAV][Info] Restore All Settings')
		self:ResetParameters()
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	self:CreateNativeSettingsSubCategory()
	self:CreateNativeSettingsPage()
end

function UI:CreateNativeSettingsSubCategory()
	DAV.NativeSettings.addSubcategory("/DAV/general", DAV.core_obj:GetTranslationText("native_settings_general_subtitle"))
	if self.is_activate_vehicle_switch then
		DAV.NativeSettings.addSubcategory("/DAV/activation", DAV.core_obj:GetTranslationText("native_settings_activation_subtitle"))
	end
	DAV.NativeSettings.addSubcategory("/DAV/keybinds", DAV.core_obj:GetTranslationText("native_settings_keybinds_subtitle"))
	DAV.NativeSettings.addSubcategory("/DAV/controller", DAV.core_obj:GetTranslationText("native_settings_controller_subtitle"))
	DAV.NativeSettings.addSubcategory("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_subtitle"))
end

function UI:ClearAllNativeSettingsSubCategory()

	DAV.NativeSettings.removeSubcategory("/DAV/general")
	DAV.NativeSettings.removeSubcategory("/DAV/activation")
	DAV.NativeSettings.removeSubcategory("/DAV/keybinds")
	DAV.NativeSettings.removeSubcategory("/DAV/controller")
	DAV.NativeSettings.removeSubcategory("/DAV/advance")

end

function UI:CreateNativeSettingsPage()

	if not DAV.is_valid_native_settings then
		return
	end
	self.option_table_list = {}
	local option_table

	-- general
    option_table = DAV.NativeSettings.addSelectorString("/DAV/general", DAV.core_obj:GetTranslationText("native_settings_general_language"), DAV.core_obj:GetTranslationText("native_settings_general_language_description"), DAV.core_obj.language_name_list, DAV.user_setting_table.language_index, 1, function(index)
		DAV.user_setting_table.language_index = index
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)

	local autopilot_speed_level_list = {DAV.core_obj:GetTranslationText("native_settings_general_speed_slow"), DAV.core_obj:GetTranslationText("native_settings_general_speed_normal"), DAV.core_obj:GetTranslationText("native_settings_general_speed_fast")}
	local selected_index
	if DAV.user_setting_table.autopilot_speed_level == Def.AutopilotSpeedLevel.Slow then
		selected_index = 1
	elseif DAV.user_setting_table.autopilot_speed_level == Def.AutopilotSpeedLevel.Normal then
		selected_index = 2
	elseif DAV.user_setting_table.autopilot_speed_level == Def.AutopilotSpeedLevel.Fast then
		selected_index = 3
	end
	option_table = DAV.NativeSettings.addSelectorString("/DAV/general", DAV.core_obj:GetTranslationText("native_settings_general_autopilot_speed"), DAV.core_obj:GetTranslationText("native_settings_general_autopilot_speed_description"), autopilot_speed_level_list, selected_index, 2, function(index)
		if index == 1 then
			DAV.user_setting_table.autopilot_speed_level = Def.AutopilotSpeedLevel.Slow
		elseif index == 2 then
			DAV.user_setting_table.autopilot_speed_level = Def.AutopilotSpeedLevel.Normal
		elseif index == 3 then
			DAV.user_setting_table.autopilot_speed_level = Def.AutopilotSpeedLevel.Fast
		end
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)

	option_table = DAV.NativeSettings.addSwitch("/DAV/general", DAV.core_obj:GetTranslationText("native_settings_general_activation"), DAV.core_obj:GetTranslationText("native_settings_general_activation_description"), self.is_activate_vehicle_switch, false, function(state)
		self.is_activate_vehicle_switch = state
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)

	-- activation
	if self.is_activate_vehicle_switch then
		local excalibur_dummy_record = DAV.excalibur_record .. "_dummy"
		local manticore_dummy_record = DAV.manticore_record .. "_dummy"
		local atlus_dummy_record = DAV.atlus_record .. "_dummy"
		local surveyor_dummy_record = DAV.surveyor_record .. "_dummy"
		local valgus_dummy_record = DAV.valgus_record .. "_dummy"
		local mayhem_dummy_record = DAV.mayhem_record .. "_dummy"
		local is_activated_excalibur = Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(excalibur_dummy_record))
		local is_activated_manticore = Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(manticore_dummy_record))
		local is_activated_atlus = Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(atlus_dummy_record))
		local is_activated_surveyor = Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(surveyor_dummy_record))
		local is_activated_valgus = Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(valgus_dummy_record))
		local is_activated_mayhem = Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(mayhem_dummy_record))
		option_table = DAV.NativeSettings.addSwitch("/DAV/activation", DAV.core_obj:GetTranslationText("native_settings_activation_excalibur"), DAV.core_obj:GetTranslationText("native_settings_activation_excalibur_description"), is_activated_excalibur, is_activated_excalibur, function(state)
			Game.GetVehicleSystem():EnablePlayerVehicle(excalibur_dummy_record, state, true)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addSwitch("/DAV/activation", DAV.core_obj:GetTranslationText("native_settings_activation_manticore"), DAV.core_obj:GetTranslationText("native_settings_activation_manticore_description"), is_activated_manticore, is_activated_manticore, function(state)
			Game.GetVehicleSystem():EnablePlayerVehicle(manticore_dummy_record, state, true)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addSwitch("/DAV/activation", DAV.core_obj:GetTranslationText("native_settings_activation_atlus"), DAV.core_obj:GetTranslationText("native_settings_activation_atlus_description"), is_activated_atlus, is_activated_atlus, function(state)
			Game.GetVehicleSystem():EnablePlayerVehicle(atlus_dummy_record, state, true)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addSwitch("/DAV/activation", DAV.core_obj:GetTranslationText("native_settings_activation_surveyor"), DAV.core_obj:GetTranslationText("native_settings_activation_surveyor_description"), is_activated_surveyor, is_activated_surveyor, function(state)
			Game.GetVehicleSystem():EnablePlayerVehicle(surveyor_dummy_record, state, true)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addSwitch("/DAV/activation", DAV.core_obj:GetTranslationText("native_settings_activation_valgus"), DAV.core_obj:GetTranslationText("native_settings_activation_valgus_description"), is_activated_valgus, is_activated_valgus, function(state)
			Game.GetVehicleSystem():EnablePlayerVehicle(valgus_dummy_record, state, true)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addSwitch("/DAV/activation", DAV.core_obj:GetTranslationText("native_settings_activation_mayhem"), DAV.core_obj:GetTranslationText("native_settings_activation_mayhem_description"), is_activated_mayhem, is_activated_mayhem, function(state)
			Game.GetVehicleSystem():EnablePlayerVehicle(mayhem_dummy_record, state, true)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

	end

	-- keybinds
	local flight_mode_list = {DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_av"), DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_heli")}
	option_table = DAV.NativeSettings.addSelectorString("/DAV/keybinds", DAV.core_obj:GetTranslationText("native_settings_common_flight_mode"), DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_description"), flight_mode_list, self.selected_flight_mode_index, 1, function(index)
		self.selected_flight_mode_index = index
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)

	local keybind_table
	local default_table
	if self.selected_flight_mode_index == 1 then
		keybind_table = DAV.user_setting_table.keybind_table
		default_table = DAV.default_keybind_table
	elseif self.selected_flight_mode_index == 2 then
		keybind_table = DAV.user_setting_table.heli_keybind_table
		default_table = DAV.default_heli_keybind_table
	end
	for index, keybind_list in ipairs(keybind_table) do
		if keybind_list.key ~= nil then
			option_table = DAV.NativeSettings.addKeyBinding("/DAV/keybinds", DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name), DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name .. "_description"), keybind_list.key, default_table[index].key, keybind_table[index].is_hold, function(key)
				if string.find(key, "IK_Pad") then
					self.log_obj:Record(LogLevel.Warning, "Invalid keybind (no keyboard): " .. key)
				else
					keybind_table[index].key = key
					Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
				end
				Cron.After(self.delay_updating_native_settings, function()
					self:UpdateNativeSettingsPage()
				end)
			end)
			table.insert(self.option_table_list, option_table)
		end
	end

	for index, keybind_list in ipairs(DAV.user_setting_table.common_keybind_table) do
		if keybind_list.key ~= nil then
			option_table = DAV.NativeSettings.addKeyBinding("/DAV/keybinds", DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name), DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name .. "_description"), keybind_list.key, DAV.default_common_keybind_table[index].key, DAV.default_common_keybind_table[index].is_hold, function(key)
				if string.find(key, "IK_Pad") then
					self.log_obj:Record(LogLevel.Warning, "Invalid keybind (no keyboard): " .. key)
				else
					DAV.user_setting_table.common_keybind_table[index].key = key
					Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
				end
				Cron.After(self.delay_updating_native_settings, function()
					self:UpdateNativeSettingsPage()
				end)
			end)
			table.insert(self.option_table_list, option_table)
		end
	end

	local flight_mode_list = {DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_av"), DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_heli")}
	option_table = DAV.NativeSettings.addSelectorString("/DAV/controller", DAV.core_obj:GetTranslationText("native_settings_common_flight_mode"), DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_description"), flight_mode_list, self.selected_flight_mode_index, 1, function(index)
		self.selected_flight_mode_index = index
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)

	for index, keybind_list in ipairs(keybind_table) do
		if keybind_list.pad ~= nil then
			option_table = DAV.NativeSettings.addKeyBinding("/DAV/controller", DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name), DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name .. "_description"), keybind_list.pad, keybind_table[index].pad, keybind_table[index].is_hold, function(pad)
				if not string.find(pad, "IK_Pad") then
					self.log_obj:Record(LogLevel.Warning, "Invalid keybind (no controller): " .. pad)
				else
					keybind_table[index].pad = pad
					Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
				end
				Cron.After(self.delay_updating_native_settings, function()
					self:UpdateNativeSettingsPage()
				end)
			end)
			table.insert(self.option_table_list, option_table)
		end
	end

	for index, keybind_list in ipairs(DAV.user_setting_table.common_keybind_table) do
		if keybind_list.pad ~= nil then
			option_table = DAV.NativeSettings.addKeyBinding("/DAV/controller", DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name), DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name .. "_description"), keybind_list.pad, DAV.default_common_keybind_table[index].pad, DAV.default_common_keybind_table[index].is_hold, function(pad)
				if not string.find(pad, "IK_Pad") then
					self.log_obj:Record(LogLevel.Warning, "Invalid keybind (no controller): " .. pad)
				else
					DAV.user_setting_table.common_keybind_table[index].pad = pad
					Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
				end
				Cron.After(self.delay_updating_native_settings, function()
					self:UpdateNativeSettingsPage()
				end)
			end)
			table.insert(self.option_table_list, option_table)
		end
	end

	-- advance
	local flight_mode_list = {DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_av"), DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_heli")}
	option_table = DAV.NativeSettings.addSelectorString("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_common_flight_mode"), DAV.core_obj:GetTranslationText("native_settings_common_flight_mode_description"), flight_mode_list, self.selected_flight_mode_index, 1, function(index)
		self.selected_flight_mode_index = index
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)

	option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_horizontal_air_resistance_const"), DAV.core_obj:GetTranslationText("native_settings_advance_horizontal_air_resistance_const_description"), 0.000, 0.1, 0.005, "%.3f", DAV.user_setting_table.horizontal_air_resistance_const, 0.01, function(value)
		DAV.user_setting_table.horizontal_air_resistance_const = value
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)

	option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_vertical_air_resistance_const"), DAV.core_obj:GetTranslationText("native_settings_advance_vertical_air_resistance_const_description"), 0.000, 0.1, 0.005, "%.3f", DAV.user_setting_table.vertical_air_resistance_const, 0.025, function(value)
		DAV.user_setting_table.vertical_air_resistance_const = value
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)

	if self.selected_flight_mode_index == 1 then
		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_acceleration"), DAV.core_obj:GetTranslationText("native_settings_advance_acceleration_description"), 0.1, 5.0, 0.1, "%.1f", DAV.user_setting_table.acceleration, 1.0, function(value)
			DAV.user_setting_table.acceleration = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_vertical_acceleration"), DAV.core_obj:GetTranslationText("native_settings_advance_vertical_acceleration_description"), 0.1, 5.0, 0.1, "%.1f", DAV.user_setting_table.vertical_acceleration, 0.8, function(value)
			DAV.user_setting_table.vertical_acceleration = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_left_right_acceleration"), DAV.core_obj:GetTranslationText("native_settings_advance_left_right_acceleration_description"), 0.1, 5.0, 0.1, "%.1f", DAV.user_setting_table.left_right_acceleration, 0.5, function(value)
			DAV.user_setting_table.left_right_acceleration = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_roll_change_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_roll_change_amount_description"), 0.1, 5.0, 0.1, "%.1f", DAV.user_setting_table.roll_change_amount, 0.5, function(value)
			DAV.user_setting_table.roll_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_roll_restore_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_roll_restore_amount_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.roll_restore_amount, 0.2, function(value)
			DAV.user_setting_table.roll_restore_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_pitch_change_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_pitch_change_amount_description"), 0.1, 5.0, 0.1, "%.1f", DAV.user_setting_table.pitch_change_amount, 0.5, function(value)
			DAV.user_setting_table.pitch_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_pitch_restore_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_pitch_restore_amount_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.pitch_restore_amount, 0.2, function(value)
			DAV.user_setting_table.pitch_restore_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_yaw_change_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_yaw_change_amount_description"), 0.1, 8.0, 0.1, "%.1f", DAV.user_setting_table.yaw_change_amount, 1.0, function(value)
			DAV.user_setting_table.yaw_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_rotate_roll_change_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_rotate_roll_change_amount_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.rotate_roll_change_amount, 0.5, function(value)
			DAV.user_setting_table.rotate_roll_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)
	elseif self.selected_flight_mode_index == 2 then
		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_roll_change_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_h_roll_change_amount_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_roll_change_amount, 0.8, function(value)
			DAV.user_setting_table.h_roll_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_roll_restore_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_h_roll_restore_amount_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_roll_restore_amount, 0.2, function(value)
			DAV.user_setting_table.h_pitch_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_pitch_change_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_h_pitch_change_amount_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_pitch_change_amount, 0.8, function(value)
			DAV.user_setting_table.h_pitch_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_pitch_restore_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_h_pitch_restore_amount_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_pitch_restore_amount, 0.2, function(value)
			DAV.user_setting_table.h_yaw_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_yaw_change_amount"), DAV.core_obj:GetTranslationText("native_settings_advance_h_yaw_change_amount_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_yaw_change_amount, 1.0, function(value)
			DAV.user_setting_table.h_yaw_change_amount = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_acceleration"), DAV.core_obj:GetTranslationText("native_settings_advance_h_acceleration_description"), 0.1, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_acceleration, 0.5, function(value)
			DAV.user_setting_table.h_acceleration = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_lift_idle_acceleration"), DAV.core_obj:GetTranslationText("native_settings_advance_h_lift_idle_acceleration_description"), 0.0, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_lift_idle_acceleration, 0.6, function(value)
			DAV.user_setting_table.h_lift_idle_acceleration = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_ascend_acceleration"), DAV.core_obj:GetTranslationText("native_settings_advance_h_ascend_acceleration_description"), 0.0, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_ascend_acceleration, 0.5, function(value)
			DAV.user_setting_table.h_ascend_acceleration = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

		option_table = DAV.NativeSettings.addRangeFloat("/DAV/advance", DAV.core_obj:GetTranslationText("native_settings_advance_h_descend_acceleration"), DAV.core_obj:GetTranslationText("native_settings_advance_h_descend_acceleration_description"), 0.0, 3.0, 0.1, "%.1f", DAV.user_setting_table.h_descend_acceleration, 0.5, function(value)
			DAV.user_setting_table.h_descend_acceleration = value
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)

	end

end

function UI:ClearNativeSettingsPage()

	if not DAV.is_valid_native_settings then
		return
	end
	for _, option_table in ipairs(self.option_table_list) do
		DAV.NativeSettings.removeOption(option_table)
	end
	self.option_table_list = {}

	self:ClearAllNativeSettingsSubCategory()

end

function UI:UpdateNativeSettingsPage()

	if DAV.core_obj.event_obj.current_situation == -1 then
		self.is_activate_vehicle_switch = false
	end
	self:ClearNativeSettingsPage()
	self:CreateNativeSettingsSubCategory()
	self:CreateNativeSettingsPage()
end

function UI:ResetParameters()

	if not DAV.is_valid_native_settings then
		return
	end
	DAV.user_setting_table = Utils:DeepCopy(DAV.core_obj.initial_user_setting_table)
    Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)

end

return UI