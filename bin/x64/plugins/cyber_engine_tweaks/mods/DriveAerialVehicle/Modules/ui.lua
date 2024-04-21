local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local UI = {}
UI.__index = UI

function UI:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "UI")

    obj.dummy_vehicle_record = "Vehicle.av_dav_dummy"
    obj.dummy_vehicle_record_path = "base\\vehicles\\special\\av_dav_dummy_99.ent"
    obj.dummy_logo_record = "UIIcon.av_dav_logo"
	obj.av_obj = nil

    -- set default value
    obj.vehicle_model_list = {}
	obj.selected_vehicle_model_name = ""
    obj.selected_vehicle_model_number = 1
	obj.vehicle_type_list = {}
	obj.selected_vehicle_type_name = ""
	obj.selected_vehicle_type_number = 1
	obj.current_vehicle_model_name = ""
	obj.current_vehicle_type_name = ""
	obj.temp_vehicle_model_name = ""

	obj.dummy_av_record = nil
	obj.av_record_list = {}

	-- garage
	obj.selected_purchased_vehicle_type_list = {}

	-- control setting
	obj.selected_flight_mode = Def.FlightMode.Heli
	obj.max_boost_ratio = 5.0

	-- enviroment setting
	obj.max_spawn_frequency = 5

	-- general setting
	obj.selected_language_name = ""

	-- info
	obj.dummy_check_1 = false
	obj.dummy_check_2 = false
	obj.dummy_check_3 = false
	obj.dummy_check_4 = false
	obj.dummy_check_5 = false

    return setmetatable(obj, self)
end

function UI:Init(av_obj)

	self.av_obj = av_obj

	if DAV.is_ready then
		self:ResetTweekDB()
	end

	self:SetTweekDB()

	-- if not DAV.is_ready then
		self:SetDefaultValue()
	-- end

end

function UI:SetTweekDB()

	local index = DAV.model_index
    local logo_inkatlas_path = self.av_obj.all_models[index].logo_inkatlas_path
    local logo_inkatlas_part_name = self.av_obj.all_models[index].logo_inkatlas_part_name
    local lockey = "Story-base-gameplay-gui-quests-q103-q103_rogue-_localizationString47"

    TweakDB:CloneRecord(self.dummy_logo_record, "UIIcon.quadra_type66__bulleat")
    TweakDB:SetFlat(TweakDBID.new(self.dummy_logo_record .. ".atlasPartName"), logo_inkatlas_part_name)
    TweakDB:SetFlat(TweakDBID.new(self.dummy_logo_record .. ".atlasResourcePath"), logo_inkatlas_path)

    TweakDB:CloneRecord(self.dummy_vehicle_record, "Vehicle.v_sport2_quadra_type66_02_player")
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle_record .. ".entityTemplatePath"), self.dummy_vehicle_record)
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle_record .. ".displayName"), LocKey(lockey))
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle_record .. ".icon"), self.dummy_logo_record)

    local vehicle_list = TweakDB:GetFlat(TweakDBID.new('Vehicle.vehicle_list.list'))
    table.insert(vehicle_list, TweakDBID.new(self.dummy_vehicle_record))
    TweakDB:SetFlat(TweakDBID.new('Vehicle.vehicle_list.list'), vehicle_list)

    self.dummy_av_record = TweakDBID.new(self.dummy_vehicle_record)

	for _, model in ipairs(self.av_obj.all_models) do
		local av_record = TweakDBID.new(model.tweakdb_id)
		table.insert(self.av_record_list, av_record)
	end

end

function UI:ResetTweekDB()

	TweakDB:DeleteRecord(self.dummy_vehicle_record)
	TweakDB:DeleteRecord(self.dummy_logo_record)
	self.av_record_list = {}

end

function UI:SetDefaultValue()

	self.selected_purchased_vehicle_type_list = {}
	-- garage
	for _, garage_info in ipairs(DAV.garage_info_list) do
		table.insert(self.selected_purchased_vehicle_type_list, self.av_obj.all_models[garage_info.model_index].type[garage_info.type_index])
	end

	--free summon mode
	for i, model in ipairs(self.av_obj.all_models) do
        self.vehicle_model_list[i] = model.name
	end
	self.selected_vehicle_model_number = DAV.model_index
	self.selected_vehicle_model_name = self.vehicle_model_list[self.selected_vehicle_model_number]

	for i, type in ipairs(self.av_obj.all_models[self.selected_vehicle_model_number].type) do
		self.vehicle_type_list[i] = type
	end
	self.selected_vehicle_type_number = DAV.model_type_index
	self.selected_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]

	self.current_vehicle_model_name = self.vehicle_model_list[self.selected_vehicle_model_number]
	self.current_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]

	-- control
	self.selected_flight_mode = DAV.flight_mode

	-- general
	self.selected_language_name = DAV.core_obj.language_name_list[DAV.language_index]

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

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_control_setting")) then
			self:ShowControlSetting()
			ImGui.EndTabItem()
		end

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_environment_setting")) then
			self:ShowEnviromentSetting()
			ImGui.EndTabItem()
		end

		if ImGui.BeginTabItem(DAV.core_obj:GetTranslationText("ui_tab_general_setting")) then
			self:ShowGeneralSetting()
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

	for model_index, garage_info in ipairs(DAV.garage_info_list) do
		if model_index == #DAV.garage_info_list then
			-- remove valgus which closed its door
			break
		end
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

	local temp_is_free_summon_mode = DAV.is_free_summon_mode
	local selected = false

	if not DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_1"))
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_2"))
		return
	end

	DAV.is_free_summon_mode = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_free_summon_enable_summon"), DAV.is_free_summon_mode)
	if temp_is_free_summon_mode ~= DAV.is_free_summon_mode then
		DAV.user_setting_table.is_free_summon_mode = DAV.is_free_summon_mode
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end
	if not DAV.is_free_summon_mode then
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

	if DAV.user_setting_table.model_index ~= self.selected_vehicle_model_number or DAV.user_setting_table.model_type_index ~= self.selected_vehicle_type_number then
		self:SetFreeSummonParameters()
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
				DAV.flight_mode = value
				self.selected_flight_mode = value
				DAV.user_setting_table.flight_mode = DAV.flight_mode
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

	-- local is_disable_heli_roll_tilt = DAV.is_disable_heli_roll_tilt
	-- local is_disable_heli_pitch_tilt = DAV.is_disable_heli_pitch_tilt
	local is_disable_spinner_roll_tilt = DAV.is_disable_spinner_roll_tilt
	if DAV.flight_mode == Def.FlightMode.Heli then
		-- DAV.is_disable_heli_roll_tilt = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_control_setting_disable_left_right"), DAV.is_disable_heli_roll_tilt)
		-- if is_disable_heli_roll_tilt ~= DAV.is_disable_heli_roll_tilt then
		-- 	DAV.user_setting_table.is_disable_heli_roll_tilt = DAV.is_disable_heli_roll_tilt
		-- 	Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		-- end
		-- DAV.is_disable_heli_pitch_tilt = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_control_setting_disable_forward_backward"), DAV.is_disable_heli_pitch_tilt)
		-- if is_disable_heli_pitch_tilt ~= DAV.is_disable_heli_pitch_tilt then
		-- 	DAV.user_setting_table.is_disable_heli_pitch_tilt = DAV.is_disable_heli_pitch_tilt
		-- 	Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		-- end
		ImGui.Text(DAV.core_obj:GetTranslationText("ui_control_setting_horizenal_boost"))
		local is_used_slider = false
		DAV.heli_horizenal_boost_ratio, is_used_slider = ImGui.SliderFloat("##Horizenal Boost Ratio", DAV.heli_horizenal_boost_ratio, 1.0, self.max_boost_ratio, "%.1f")
		if not is_used_slider and DAV.user_setting_table.heli_horizenal_boost_ratio ~= DAV.heli_horizenal_boost_ratio then
			DAV.user_setting_table.heli_horizenal_boost_ratio = DAV.heli_horizenal_boost_ratio
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		end
	elseif DAV.flight_mode == Def.FlightMode.Spinner then
		DAV.is_disable_spinner_roll_tilt = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_control_setting_disable_left_right"), DAV.is_disable_spinner_roll_tilt)
		if is_disable_spinner_roll_tilt ~= DAV.is_disable_spinner_roll_tilt then
			DAV.user_setting_table.is_disable_spinner_roll_tilt = DAV.is_disable_spinner_roll_tilt
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		end
	end

end

function UI:ShowEnviromentSetting()

	if not DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_1"))
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_free_summon_warning_message_in_summoning_2"))
		return
	end

	DAV.is_enable_community_spawn = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_environment_enable_community_spawn"), DAV.is_enable_community_spawn)
	if DAV.user_setting_table.is_enable_community_spawn ~= DAV.is_enable_community_spawn then
		DAV.user_setting_table.is_enable_community_spawn = DAV.is_enable_community_spawn
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end

	if DAV.is_enable_community_spawn then
		ImGui.Text(DAV.core_obj:GetTranslationText("ui_environment_spawn_frequency"))
		local is_used_slider = false
		DAV.spawn_frequency, is_used_slider = ImGui.SliderInt("##spawn frequency", DAV.spawn_frequency, 1, self.max_spawn_frequency, "%d")
		if not is_used_slider and DAV.user_setting_table.spawn_frequency ~= DAV.spawn_frequency then
			self.av_obj.max_freeze_count = math.floor(100 / DAV.spawn_frequency)
			DAV.user_setting_table.spawn_frequency = DAV.spawn_frequency
			Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
		end
	end

	ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_environment_warning_message_about_community_spawn"))
		ImGui.TextColored(1, 0, 0, 1, DAV.core_obj:GetTranslationText("ui_environment_warning_message_about_spawn_frequency"))
end

function UI:ShowGeneralSetting()

	local temp_language_index = DAV.language_index
	local selected = false
	self.selected_language_name = DAV.core_obj.language_name_list[DAV.language_index]

	ImGui.Text(DAV.core_obj:GetTranslationText("ui_setting_language"))
	if ImGui.BeginCombo("##Language", self.selected_language_name) then
		for index, value in ipairs(DAV.core_obj.language_name_list) do
			if self.selected_language_name == value then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable(value, selected)) then
				self.selected_language_name = value
				DAV.language_index = index
			end
		end
		ImGui.EndCombo()
	end

	if temp_language_index ~= DAV.language_index then
		DAV.user_setting_table.language_index = DAV.language_index
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end

	ImGui.Separator()

	DAV.is_unit_km_per_hour = ImGui.Checkbox(DAV.core_obj:GetTranslationText("ui_setting_unit_setting"), DAV.is_unit_km_per_hour)
	if DAV.user_setting_table.is_unit_km_per_hour ~= DAV.is_unit_km_per_hour then
		DAV.user_setting_table.is_unit_km_per_hour = DAV.is_unit_km_per_hour
		Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
	end

	ImGui.Separator()

	if DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.Text(DAV.core_obj:GetTranslationText("ui_setting_reset_setting"))
		if ImGui.Button(DAV.core_obj:GetTranslationText("ui_setting_reset_setting_button"), 180, 60) then
			DAV.core_obj:ResetSetting()
		end
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
		ImGui.TextColored(1, 0, 0, 1, "CodeWare Version: " .. Codeware.Version() .. "(Not Recommended Version)")
	else
		ImGui.Text("CodeWare Version: " .. Codeware.Version())
	end

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

	if not self.dummy_check_1 and self.dummy_check_2 and not self.dummy_check_3 and not self.dummy_check_4 and self.dummy_check_5 then
		DAV.is_debug_mode = true
	else
		DAV.is_debug_mode = false
	end
end

function UI:SetFreeSummonParameters()

	DAV.model_index = self.selected_vehicle_model_number
	DAV.model_type_index = self.selected_vehicle_type_number
	DAV.core_obj:Reset()

	self.current_vehicle_model_name = self.vehicle_model_list[self.selected_vehicle_model_number]
	self.current_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]

	DAV.user_setting_table.model_index = DAV.model_index
	DAV.user_setting_table.model_type_index = DAV.model_type_index
	Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)

end

return UI