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
	-- garage
	obj.selected_purchased_vehicle_type_list = {}
    -- free summon
    obj.vehicle_model_list = {}
	obj.selected_vehicle_model_name = ""
    obj.selected_vehicle_model_number = 1
	obj.vehicle_type_list = {}
	obj.selected_vehicle_type_name = ""
	obj.selected_vehicle_type_number = 1
	obj.current_vehicle_model_name = ""
	obj.current_vehicle_type_name = ""
	obj.temp_vehicle_model_name = ""
	-- auto pilot setting
	obj.selected_auto_pilot_history_index = 1
	obj.selected_auto_pilot_history_name = ""
	obj.history_list = {}
	obj.current_position_name = ""
	-- control setting
	obj.selected_flight_mode = Def.FlightMode.Heli
	obj.max_boost_ratio = 15.0
	-- enviroment setting
	obj.max_spawn_frequency_max = 100
	obj.max_spawn_frequency_min = 20
	obj.min_spawn_frequency_max = 15
	obj.min_spawn_frequency_min = 5
	-- general setting
	obj.selected_language_name = ""
	-- info
	obj.dummy_check_1 = false
	obj.dummy_check_2 = false
	obj.dummy_check_3 = false
	obj.dummy_check_4 = false
	obj.dummy_check_5 = false

	-- custom popup
	obj.ui_game_menu_controller = nil

	-- native settings page
	obj.option_table_list = {}
    return setmetatable(obj, self)
end

function UI:Init(av_obj)
	self.av_obj = av_obj
	self:SetObserver()
	self:SetTweekDB()
	self:SetDefaultValue()
	self:CreateNativeSettingsBasePage()
end

function UI:SetTweekDB()

    self.dummy_av_record = TweakDBID.new(self.dummy_vehicle_record)

	for _, model in ipairs(self.av_obj.all_models) do
		local av_record = TweakDBID.new(model.tweakdb_id)
		table.insert(self.av_record_list, av_record)
	end

end

function UI:SetObserver()

	if not DAV.is_ready then
		Observe('gameuiInGameMenuGameController', 'RegisterInputListenersForPlayer', function(this, player)
			print("RegisterInputListenersForPlayer")
			if player:IsControlledByLocalPeer() then
				self.ui_game_menu_controller = this
				-- player:RegisterInputListener(this, "Choice2_Hold")
			end
		end)

		Observe('gameuiInGameMenuGameController', 'OnAction', function(this, action, consume)
			local action_name = action:GetName(action).value
			local action_type = action:GetType(action).value

			print("Action Name : " .. action_name .. ", Action Type : " .. action_type)
			if action_name == "Choice2_Hold" and action_type == "BUTTON_HOLD_COMPLETE" then
				local popup = InkPlaygroundPopup.new()
				popup.Show(this)
				-- local popup = setmetatable({}, InkPlaygroundPopup)
				-- popup:Show(this)
			end
		end)
	end

end

function UI:SetDefaultValue()

	self.selected_purchased_vehicle_type_list = {}
	-- garage
	for _, garage_info in ipairs(DAV.user_setting_table.garage_info_list) do
		table.insert(self.selected_purchased_vehicle_type_list, self.av_obj.all_models[garage_info.model_index].type[garage_info.type_index])
	end

	--free summon mode
	for i, model in ipairs(self.av_obj.all_models) do
        self.vehicle_model_list[i] = model.name
	end
	self.selected_vehicle_model_number = DAV.user_setting_table.model_index_in_free
	self.selected_vehicle_model_name = self.vehicle_model_list[self.selected_vehicle_model_number]

	for i, type in ipairs(self.av_obj.all_models[self.selected_vehicle_model_number].type) do
		self.vehicle_type_list[i] = type
	end
	self.selected_vehicle_type_number = DAV.user_setting_table.model_type_index_in_free
	self.selected_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]

	self.current_vehicle_model_name = self.vehicle_model_list[self.selected_vehicle_model_number]
	self.current_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]

	-- auto pilot setting
	self:CreateStringHistory()
	self.selected_auto_pilot_history_index = 1
	self.selected_auto_pilot_history_name = self.history_list[self.selected_auto_pilot_history_index]
	for index, favorite_info in ipairs(DAV.user_setting_table.favorite_location_list) do
		if favorite_info.is_selected then
			self.selected_auto_pilot_favorite_index = index
			break
		end
	end
	DAV.core_obj:SetFavoriteMappin(DAV.user_setting_table.favorite_location_list[self.selected_auto_pilot_favorite_index].pos)

	-- control
	self.selected_flight_mode = DAV.user_setting_table.flight_mode

	-- general
	self.selected_language_name = DAV.core_obj.language_name_list[DAV.user_setting_table.language_index]

	-- info
	self.dummy_check_1 = false
	self.dummy_check_2 = false
	self.dummy_check_3 = false
	self.dummy_check_4 = false
	self.dummy_check_5 = false

end

function UI:SetMenuColor()
	ImGui.PushStyleColor(ImGuiCol.TitleBg, 0, 0.5, 0, 0.5)
	ImGui.PushStyleColor(ImGuiCol.TitleBgCollapsed, 0, 0.5, 0, 0.5)
	ImGui.PushStyleColor(ImGuiCol.TitleBgActive, 0, 0.5, 0, 0.5)
	ImGui.PushStyleColor(ImGuiCol.WindowBg, 0, 0, 0, 0.7)
	ImGui.PushStyleColor(ImGuiCol.Tab, 0, 0.5, 0, 0.7)
	ImGui.PushStyleColor(ImGuiCol.TabHovered, 0.5, 0.5, 0.5, 0.5)
	ImGui.PushStyleColor(ImGuiCol.TabActive, 0, 0, 0.8, 0.7)
	ImGui.PushStyleColor(ImGuiCol.Button, 0, 0.7, 0, 0.7)
	ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.5, 0.5, 0.5, 0.5)
	ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0.7, 0, 0.7)
	ImGui.PushStyleColor(ImGuiCol.FrameBg, 0.5, 0.5, 0.5, 0.7)
	ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0.5, 0.5, 0.5, 0.5)
	ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0.5, 0.5, 0.5, 0.7)
	ImGui.PushStyleColor(ImGuiCol.CheckMark, 0, 0.7, 0, 0.8)
end

function UI:ShowSettingMenu()

	self:SetMenuColor()
    -- ImGui.SetNextWindowSize(1200, 800, ImGuiCond.Appearing)
    ImGui.Begin(DAV.core_obj:GetTranslationText("ui_main_window_title"))

	if ImGui.BeginTabBar("DAV Menu") then

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_garage")) then
			self:ShowGarage()
			ImGui.EndTabItem()
		end

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_free_summon")) then
			self:ShowFreeSummon()
			ImGui.EndTabItem()
		end

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_auto_pilot_setting")) then
			self:ShowAutoPilotSetting()
			ImGui.EndTabItem()
		end

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_control_setting")) then
			self:ShowControlSetting()
			ImGui.EndTabItem()
		end

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_environment_setting")) then
			self:ShowEnviromentSetting()
			ImGui.EndTabItem()
		end

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_info")) then
			self:ShowInfo()
			ImGui.EndTabItem()
		end

		ImGui.EndTabBar()

	end

    ImGui.End()

end

function UI:ShowGarage()

	local selected = false

	ImGui.Text(DAV.core_obj:GetTranslationText("ui_garage_title"))

	ImGui.Separator()

	for model_index, garage_info in ipairs(DAV.user_setting_table.garage_info_list) do
		ImGui.Text(self.av_obj.all_models[garage_info.model_index].name)
		ImGui.SameLine()
		ImGui.Text(" : ")
		ImGui.SameLine()
		if garage_info.is_purchased then
			ImGui.TextColored(0, 1, 0, 1, DAV.core_obj:GetTranslationText("ui_garage_purchased"))
		else
			ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_garage_not_purchased"))
		end

		if ImGui.BeginCombo("##" .. self.av_obj.all_models[garage_info.model_index].name, self.selected_purchased_vehicle_type_list[model_index]) then
			for index, value in ipairs(self.av_obj.all_models[garage_info.model_index].type) do
				if self.selected_purchased_vehicle_type_list[model_index] == value.name then
					selected = true
				else
					selected = false
				end
				if(ImGui.Selectable(value, selected)) then
					self.selected_purchased_vehicle_type_list[model_index] = value
					DAV.core_obj:ChangeGarageAVType(garage_info.name, index)
				end
			end
			ImGui.EndCombo()
		end

		ImGui.Separator()
	end

end

function UI:ShowFreeSummon()

	local temp_is_free_summon_mode = DAV.user_setting_table.is_free_summon_mode
	local selected = false

	DAV.user_setting_table.is_free_summon_mode = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_free_summon_enable_summon"), DAV.user_setting_table.is_free_summon_mode)
	if temp_is_free_summon_mode ~= DAV.user_setting_table.is_free_summon_mode then
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end

	ImGui.Separator()
	ImGui.Spacing()

	if not DAV.user_setting_table.is_free_summon_mode then
		ImGui.TextColored(1, 1, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_1"))
		ImGui.TextColored(1, 1, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_3"))
		return
	end

	ImGui.Text(DAV.core_obj:GetTranslationText("ui_free_summon_select_model"))
	ImGui.SameLine()
	ImGui.TextColored(0, 1, 0, 1, self.current_vehicle_model_name)
	ImGui.Text(DAV.core_obj:GetTranslationText("ui_free_summon_select_type"))
	ImGui.SameLine()
	ImGui.TextColored(0, 1, 0, 1, self.current_vehicle_type_name)

	ImGui.Separator()
	ImGui.Spacing()

	if not DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_1"))
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_2"))
		return
	end

	if self.selected_vehicle_model_name == nil then
		self.selected_vehicle_model_name = self.vehicle_model_list[1]
		return
	end
	if self.selected_vehicle_model_number == nil then
		self.selected_vehicle_model_number = 1
		return
	end

	ImGui.Text(DAV.core_obj:GetTranslationText("ui_free_summon_select_model_explain"))
	if ImGui.BeginCombo("##AV Model", self.selected_vehicle_model_name) then
		for index, value in ipairs(self.vehicle_model_list) do
			if self.selected_vehicle_model_name == value.name then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable(value, selected)) then
				self.selected_vehicle_model_name = value
				self.selected_vehicle_model_number = index
			end
		end
		ImGui.EndCombo()
	end

	if self.current_vehicle_model_name ~= self.selected_vehicle_model_name and self.selected_vehicle_model_name ~= self.temp_vehicle_model_name then
		self.temp_vehicle_model_name = self.selected_vehicle_model_name
		self.selected_vehicle_type_number = 1
	end

	self.vehicle_type_list = {}

	for i, type in ipairs(self.av_obj.all_models[self.selected_vehicle_model_number].type) do
		self.vehicle_type_list[i] = type
	end

	self.selected_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]

	if self.selected_vehicle_type_name == nil then
		self.selected_vehicle_type_name = self.vehicle_type_list[1]
		return
	end
	if self.selected_vehicle_type_number == nil then
		self.selected_vehicle_type_number = 1
		return
	end

	ImGui.Text(DAV.core_obj:GetTranslationText("ui_free_summon_select_model_explain"))
	if ImGui.BeginCombo("##AV Type", self.selected_vehicle_type_name) then
		for index, value in ipairs(self.vehicle_type_list) do
			if self.selected_vehicle_type_name == value then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable(value, selected)) then
				self.selected_vehicle_type_name = value
				self.selected_vehicle_type_number = index
			end
		end
		ImGui.EndCombo()
	end

	if DAV.user_setting_table.model_index_in_free ~= self.selected_vehicle_model_number or DAV.user_setting_table.model_type_index_in_free ~= self.selected_vehicle_type_number then
		self:SetFreeSummonParameters()
	end

end

function UI:ShowAutoPilotSetting()

	ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_main"))
	local is_autopilot_info_panel = DAV.user_setting_table.is_autopilot_info_panel
	DAV.user_setting_table.is_autopilot_info_panel = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_enable_panel"), DAV.user_setting_table.is_autopilot_info_panel)
	if is_autopilot_info_panel ~= DAV.user_setting_table.is_autopilot_info_panel then
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end

	if not DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_1"))
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_2"))
	else
		local is_used_slider = false
		ImGui.Text(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_speed_level"))
		if DAV.user_setting_table.autopilot_speed_level == Def.AutopilotSpeedLevel.Slow then
			ImGui.SameLine()
			ImGui.TextColored(0, 1, 0, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_speed_slow"))
		elseif DAV.user_setting_table.autopilot_speed_level == Def.AutopilotSpeedLevel.Normal then
			ImGui.SameLine()
			ImGui.TextColored(0, 1, 0, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_speed_normal"))
		elseif DAV.user_setting_table.autopilot_speed_level == Def.AutopilotSpeedLevel.Fast then
			ImGui.SameLine()
			ImGui.TextColored(0, 1, 0, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_speed_fast"))
		end
		DAV.user_setting_table.autopilot_speed_level, is_used_slider = ImGui.SliderInt("##Autopilot Speed Level", DAV.user_setting_table.autopilot_speed_level, 1, 3, "%d")
		if is_used_slider then
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		end
	end

	ImGui.Spacing()
	ImGui.Separator()

	ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_mappin"))
	if DAV.core_obj:IsCustomMappin() then
		ImGui.Text(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_district_info"))
		local dist_near_ft_index = DAV.core_obj:GetFTIndexNearbyMappin()
		local dist_district_list = DAV.core_obj:GetNearbyDistrictList(dist_near_ft_index)
		if dist_district_list ~= nil then
			for _, district in ipairs(dist_district_list) do
				ImGui.SameLine()
				ImGui.TextColored(0, 1, 0, 1, district)
			end
		end
		ImGui.Text(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_location_info"))
		local nearby_location = DAV.core_obj:GetNearbyLocation(dist_near_ft_index)
		if nearby_location ~= nil then
			ImGui.SameLine()
			ImGui.TextColored(0, 1, 0, 1, nearby_location)
			ImGui.SameLine()
			local custom_ft_distance = DAV.core_obj:GetFT2MappinDistance()
			if custom_ft_distance ~= DAV.core_obj.huge_distance then
				ImGui.TextColored(0, 1, 0, 1, "[" .. tostring(math.floor(custom_ft_distance)) .. "m]")
			end
		end
	else
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_not_put_mappin"))
	end

	ImGui.Spacing()
	ImGui.Separator()

	local selected_auto_pilot_favorite_index = self.selected_auto_pilot_favorite_index
	local selected = false
	ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_favorite_list"))
	if ImGui.BeginCombo("##Favorite List", DAV.user_setting_table.favorite_location_list[self.selected_auto_pilot_favorite_index].name) then
		for index, favorite_info in ipairs(DAV.user_setting_table.favorite_location_list) do
			if favorite_info.is_selected then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable("[" .. tostring(index - 1) .. "]" .. favorite_info.name, selected)) then
				self.selected_auto_pilot_favorite_index = index
				if selected_auto_pilot_favorite_index ~= self.selected_auto_pilot_favorite_index then
					for fav_index, _ in ipairs(DAV.user_setting_table.favorite_location_list) do
						DAV.user_setting_table.favorite_location_list[fav_index].is_selected = false
						if fav_index == index then
							DAV.user_setting_table.favorite_location_list[fav_index].is_selected = true
							DAV.core_obj:SetFavoriteMappin(DAV.user_setting_table.favorite_location_list[fav_index].pos)
							Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
						end
					end
				end
				local location_name = DAV.user_setting_table.favorite_location_list[index].name
				DAV.user_setting_table.favorite_location_list[index].name = ImGui.InputText("##Rename", DAV.user_setting_table.favorite_location_list[index].name, 100)
				if location_name ~= DAV.user_setting_table.favorite_location_list[index].name then
					Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
				end
			end
		end
		ImGui.EndCombo()
	end

	ImGui.Spacing()
	ImGui.Separator()

	local is_enable_history = DAV.user_setting_table.is_enable_history
	DAV.user_setting_table.is_enable_history = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_enable_history"), DAV.user_setting_table.is_enable_history)
	if is_enable_history ~= DAV.user_setting_table.is_enable_history then
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end
	local is_not_enable_history = not DAV.user_setting_table.is_enable_history
	local is_not_enable_history_pre = not DAV.user_setting_table.is_enable_history
	is_not_enable_history = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_enable_current_pos"), is_not_enable_history)
	if is_not_enable_history_pre ~= is_not_enable_history then
		DAV.user_setting_table.is_enable_history = not is_not_enable_history
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end

	ImGui.Text(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_register_fav"))

	ImGui.SameLine()

	for index, _ in ipairs(DAV.user_setting_table.favorite_location_list) do
		if index ~= 1 then
			if ImGui.Button(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_register_favorite_" .. tostring(index - 1))) then
				if DAV.user_setting_table.is_enable_history then
					if #self.history_list ~= 0 then
						local history_string = self.selected_auto_pilot_history_name
						history_string = string.sub(history_string, 4)
						DAV.user_setting_table.favorite_location_list[index].name = history_string
						DAV.user_setting_table.favorite_location_list[index].pos = DAV.user_setting_table.mappin_history[self.selected_auto_pilot_history_index].position
						Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
					end
				else
					if not DAV.core_obj.event_obj:IsNotSpawned() then
						DAV.user_setting_table.favorite_location_list[index].name = self.current_position_name
						local current_pos = self.av_obj.position_obj:GetPosition()
						DAV.user_setting_table.favorite_location_list[index].pos = {x=current_pos.x, y=current_pos.y, z=current_pos.z}
						Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
					end
				end
			end
			if index ~= #DAV.user_setting_table.favorite_location_list then
				ImGui.SameLine()
			end
		end
	end

	ImGui.Spacing()
	ImGui.Separator()

	if DAV.user_setting_table.is_enable_history then
		self:CreateStringHistory()
		ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_history"))
		local selected = false
		if ImGui.BeginListBox("##History") then
			for index = #self.history_list, 1, -1 do
				local history_string = self.history_list[index]
				if self.selected_auto_pilot_history_name == history_string then
					selected = true
				else
					selected = false
				end
				if(ImGui.Selectable(history_string, selected)) then
					self.selected_auto_pilot_history_name = history_string
					self.selected_auto_pilot_history_index = index
				end
			end
			ImGui.EndListBox()
		end
	else
		ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_current_position"))
		if DAV.core_obj.event_obj:IsNotSpawned() then
			ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_not_spawned"))
		else
			local current_district_list = DAV.core_obj:GetCurrentDistrict()
			local entity = Game.FindEntityByID(self.av_obj.entity_id)
			if entity ~= nil then
				local current_nearby_ft_index, _ = DAV.core_obj:FindNearestFastTravelPosition(entity:GetWorldPosition())
				local current_nearby_ft_name = DAV.core_obj:GetNearbyLocation(current_nearby_ft_index)
				ImGui.Text(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_district_info"))
				self.current_position_name = ""
				if current_district_list ~= nil then
					for _, district in ipairs(current_district_list) do
						ImGui.SameLine()
						ImGui.TextColored(0, 1, 0, 1, district)
						self.current_position_name = self.current_position_name .. district .. "/"
					end
				end
				ImGui.Text(DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_location_info"))
				if current_nearby_ft_name ~= nil then
					ImGui.SameLine()
					ImGui.TextColored(0, 1, 0, 1, current_nearby_ft_name)
					self.current_position_name = self.current_position_name .. current_nearby_ft_name
				end
			else
				ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_auto_pilot_setting_not_spawned"))
			end
		end
	end

end

function UI:ShowControlSetting()

	if not DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_1"))
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_2"))
		return
	end

	local selected = false
	ImGui.Text(DAV.core_obj:GetTranslationText("ui_control_setting_select_flight_mode"))
	if ImGui.BeginCombo("##Flight Mode", self.selected_flight_mode) then
		for _, value in pairs(Def.FlightMode) do
			if self.selected_flight_mode == value then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable(value, selected)) then
				self.selected_flight_mode = value
				DAV.user_setting_table.flight_mode = value
				Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			end
		end
		ImGui.EndCombo()
	end

	ImGui.Spacing()

	ImGui.Text(DAV.core_obj:GetTranslationText("ui_control_setting_explain_spinner"))
	ImGui.Text(DAV.core_obj:GetTranslationText("ui_control_setting_explain_Heli"))

	ImGui.Separator()
	ImGui.Spacing()

	local is_disable_spinner_roll_tilt = DAV.user_setting_table.is_disable_spinner_roll_tilt
	if DAV.user_setting_table.flight_mode == Def.FlightMode.Heli then
		ImGui.Text(DAV.core_obj:GetTranslationText("ui_control_setting_horizenal_boost"))
		local is_used_slider = false
		local heli_horizenal_boost_ratio = DAV.user_setting_table.heli_horizenal_boost_ratio
		DAV.user_setting_table.heli_horizenal_boost_ratio, is_used_slider = ImGui.SliderFloat("##Horizenal Boost Ratio", DAV.user_setting_table.heli_horizenal_boost_ratio, 1.0, self.max_boost_ratio, "%.1f")
		if not is_used_slider and DAV.user_setting_table.heli_horizenal_boost_ratio ~= heli_horizenal_boost_ratio then
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		end
	elseif DAV.user_setting_table.flight_mode == Def.FlightMode.Spinner then
		DAV.user_setting_table.is_disable_spinner_roll_tilt = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_control_setting_disable_left_right"), DAV.user_setting_table.is_disable_spinner_roll_tilt)
		if is_disable_spinner_roll_tilt ~= DAV.user_setting_table.is_disable_spinner_roll_tilt then
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		end
	end

end

function UI:ShowEnviromentSetting()

	ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("ui_environment_setting_community_spawn"))

	if not DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_1"))
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_2"))
	else
		local is_enable_community_spawn = DAV.user_setting_table.is_enable_community_spawn
		DAV.user_setting_table.is_enable_community_spawn = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_environment_enable_community_spawn"), DAV.user_setting_table.is_enable_community_spawn)
		if DAV.user_setting_table.is_enable_community_spawn ~= is_enable_community_spawn then
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		end
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_environment_warning_message_about_community_spawn"))
		if DAV.user_setting_table.is_enable_community_spawn then
			ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("ui_environment_advanced_setting"))
			ImGui.Text(DAV.core_obj:GetTranslationText("ui_environment_limit_spawn_speed"))
			local is_used_slider = false
			local max_speed_for_freezing = DAV.user_setting_table.max_speed_for_freezing
			DAV.user_setting_table.max_speed_for_freezing, is_used_slider = ImGui.SliderInt("##max spawn speed", DAV.user_setting_table.max_speed_for_freezing, 0, 400, "%d")
			if not is_used_slider and DAV.user_setting_table.max_speed_for_freezing ~= max_speed_for_freezing then
				self.av_obj.max_speed_for_freezing = DAV.user_setting_table.max_speed_for_freezing
				Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			end
			ImGui.Text(DAV.core_obj:GetTranslationText("ui_environment_maximum_update_interval"))
			local max_spawn_frequency = DAV.user_setting_table.max_spawn_frequency
			local min_spawn_frequency = DAV.user_setting_table.min_spawn_frequency
			DAV.user_setting_table.max_spawn_frequency, is_used_slider = ImGui.SliderInt("##max spawn frequency", DAV.user_setting_table.max_spawn_frequency, min_spawn_frequency + 1, self.max_spawn_frequency_max, "%d")
			if not is_used_slider and DAV.user_setting_table.max_spawn_frequency ~= max_spawn_frequency then
				self.av_obj.max_freeze_count = DAV.user_setting_table.max_spawn_frequency
				Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			end
			ImGui.Text(DAV.core_obj:GetTranslationText("ui_environment_minimum_update_interval"))
			DAV.user_setting_table.min_spawn_frequency, is_used_slider = ImGui.SliderInt("##min spawn frequency", DAV.user_setting_table.min_spawn_frequency, self.min_spawn_frequency_min, max_spawn_frequency - 1, "%d")
			if not is_used_slider and DAV.user_setting_table.min_spawn_frequency ~= min_spawn_frequency then
				self.av_obj.min_freeze_count = DAV.user_setting_table.min_spawn_frequency
				Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			end
		end

	end

	ImGui.Spacing()
	ImGui.Separator()

	ImGui.TextColored(0.8, 0.8, 0.5, 1, DAV.core_obj:GetTranslationText("ui_environment_setting_Sound_title"))
	local is_mute_all = DAV.user_setting_table.is_mute_all
	DAV.user_setting_table.is_mute_all = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_environment_setting_mute_all"), DAV.user_setting_table.is_mute_all)
	if DAV.user_setting_table.is_mute_all ~= is_mute_all then
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end
	local is_mute_flight = DAV.user_setting_table.is_mute_flight
	DAV.user_setting_table.is_mute_flight = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_environment_setting_mute_flight"), DAV.user_setting_table.is_mute_flight)
	if DAV.user_setting_table.is_mute_flight ~= is_mute_flight then
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end

end

function UI:ShowInfo()
	ImGui.Text("Drive an Aerial Vehicle Version: " .. DAV.version)
	if DAV.cet_version_num < DAV.cet_recommended_version then
		ImGui.TextColored(1, 0, 0, 1, "CET Version: " .. GetVersion() .. "(Not Recommended Version)")
	else
		ImGui.Text("CET Version: " .. GetVersion())
	end
	if DAV.codeware_version_num < DAV.codeware_recommended_version then
		ImGui.TextColored(1, 0, 0, 1, "Codeware Version: " .. Codeware.Version() .. "(Not Recommended Version)")
	else
		ImGui.Text("CodeWare Version: " .. Codeware.Version())
	end
	if DAV.native_settings_version_num < DAV.native_settings_required_version then
		ImGui.TextColored(1, 0, 0, 1, "Native Settings may not be installed or may be outdated.")
	else
		ImGui.Text("Native Settings Version: " .. DAV.native_settings_version_num)
	end

	ImGui.Spacing()
	ImGui.Separator()

	ImGui.Text(DAV.core_obj:GetTranslationText("ui_setting_reset_setting"))
	if ImGui.Button(DAV.core_obj:GetTranslationText("ui_setting_reset_setting_button")) then
		DAV.core_obj:ResetSetting()
	end

	ImGui.Spacing()
	ImGui.Separator()

	ImGui.Text("Debug Checkbox (Developer Mode)")
	self.dummy_check_1 = ImGui.Checkbox("1", self.dummy_check_1)
	ImGui.SameLine()
	self.dummy_check_2 = ImGui.Checkbox("2", self.dummy_check_2)
	ImGui.SameLine()
	self.dummy_check_3 = ImGui.Checkbox("3", self.dummy_check_3)
	ImGui.SameLine()
	self.dummy_check_4 = ImGui.Checkbox("4", self.dummy_check_4)
	ImGui.SameLine()
	self.dummy_check_5 = ImGui.Checkbox("5", self.dummy_check_5)

	-- if not self.dummy_check_1 and self.dummy_check_2 and not self.dummy_check_3 and not self.dummy_check_4 and self.dummy_check_5 then
	-- 	DAV.is_debug_mode = true
	-- else
	-- 	DAV.is_debug_mode = false
	-- end
end

function UI:SetFreeSummonParameters()

	DAV.user_setting_table.model_index_in_free = self.selected_vehicle_model_number
	DAV.user_setting_table.model_type_index_in_free = self.selected_vehicle_type_number
	DAV.core_obj:Reset()

	self.current_vehicle_model_name = self.vehicle_model_list[self.selected_vehicle_model_number]
	self.current_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]

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
	DAV.NativeSettings.addTab("/DAV", DAV.core_obj:GetTranslationText("native_settings_keybinds_title"))
	DAV.NativeSettings.addSubcategory("/DAV/general", DAV.core_obj:GetTranslationText("native_settings_general_subtitle"))
	DAV.NativeSettings.addSubcategory("/DAV/keybinds", DAV.core_obj:GetTranslationText("native_settings_keybinds_subtitle"))
	DAV.NativeSettings.addSubcategory("/DAV/controller", DAV.core_obj:GetTranslationText("native_settings_controller_subtitle"))
	self:CreateNativeSettingsPage()
end

function UI:CreateNativeSettingsPage()

	if not DAV.is_valid_native_settings then
		return
	end
	self.option_table_list = {}
	local option_table

    option_table = DAV.NativeSettings.addSelectorString("/DAV/general", DAV.core_obj:GetTranslationText("native_settings_general_language"), DAV.core_obj:GetTranslationText("native_settings_general_language_description"), DAV.core_obj.language_name_list, DAV.user_setting_table.language_index, 1, function(index)
		DAV.user_setting_table.language_index = index
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)
	option_table = DAV.NativeSettings.addSwitch("/DAV/general", DAV.core_obj:GetTranslationText("native_settings_general_unit"), DAV.core_obj:GetTranslationText("native_settings_general_unit_description"), DAV.user_setting_table.is_unit_km_per_hour, false, function(state)
		DAV.user_setting_table.is_unit_km_per_hour = state
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		Cron.After(self.delay_updating_native_settings, function()
			self:UpdateNativeSettingsPage()
		end)
	end)
	table.insert(self.option_table_list, option_table)
	for index, keybind_list in ipairs(DAV.user_setting_table.keybind_table) do
		option_table = DAV.NativeSettings.addKeyBinding("/DAV/keybinds", DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name), DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name .. "_description"), keybind_list.key, DAV.default_keybind_table[index].key, false, function(key)
			if string.find(key, "IK_Pad") then
				self.log_obj:Record(LogLevel.Warning, "Invalid keybind (no keyboard): " .. key)
			else
				DAV.user_setting_table.keybind_table[index].key = key
				Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			end
			Cron.After(self.delay_updating_native_settings, function()
				self:UpdateNativeSettingsPage()
			end)
		end)
		table.insert(self.option_table_list, option_table)
	end
	for index, keybind_list in ipairs(DAV.user_setting_table.keybind_table) do
		option_table = DAV.NativeSettings.addKeyBinding("/DAV/controller", DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name), DAV.core_obj:GetTranslationText("native_settings_keybinds_" .. keybind_list.name .. "_description"), keybind_list.pad, DAV.default_keybind_table[index].pad, false, function(pad)
			if not string.find(pad, "IK_Pad") then
				self.log_obj:Record(LogLevel.Warning, "Invalid keybind (no controller): " .. pad)
			else
				DAV.user_setting_table.keybind_table[index].pad = pad
				Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
			end
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

end

function UI:UpdateNativeSettingsPage()
	self:ClearNativeSettingsPage()
	self:CreateNativeSettingsPage()
end

return UI