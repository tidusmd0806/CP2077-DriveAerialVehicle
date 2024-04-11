local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Ui = {}
Ui.__index = Ui

function Ui:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Ui")

    obj.dummy_vehicle_record = "Vehicle.av_dav_dummy"
    obj.dummy_vehicle_record_path = "base\\vehicles\\special\\av_dav_dummy_99.ent"
    obj.dummy_logo_record = "UIIcon.av_davr_logo"
	obj.av_obj = nil

    -- set default value
    obj.dummy_vehicle_record_hash = nil
    obj.is_vehicle_call = false
    obj.vehicle_model_list = {}
	obj.selected_vehicle_model_name = ""
    obj.selected_vehicle_model_number = 1
	obj.vehicle_type_list = {}
	obj.selected_vehicle_type_name = ""
	obj.selected_vehicle_type_number = 1
	obj.vehicle_seat_list = {}
	obj.selected_vehicle_seat_name = ""
	obj.selected_vehicle_seat_number = 1
	obj.current_vehicle_model_name = ""
	obj.current_vehicle_type_name = ""
	obj.current_vehicle_seat_name = ""

	obj.temp_vehicle_model_name = ""

	obj.max_boost_ratio = 5.0

    return setmetatable(obj, self)
end

function Ui:Init(av_obj)
	self.av_obj = av_obj

    self:SetTweekDB()
	if not DAV.ready then
    	self:SetOverride()
		self:SetInitialParameters()
		self:InitVehicleModelList()
	end
end

function Ui:SetInitialParameters()
	DAV.model_index = DAV.user_setting_table.model_index
	DAV.model_type_index = DAV.user_setting_table.model_type_index
	DAV.seat_index = DAV.user_setting_table.seat_index
	DAV.horizenal_boost_ratio = DAV.user_setting_table.horizenal_boost_ratio
end

function Ui:SetTweekDB()
	local index = DAV.model_index
	local display_name_lockey = self.av_obj.all_models[index].display_name_lockey
    local logo_inkatlas_path = self.av_obj.all_models[index].logo_inkatlas_path
    local logo_inkatlas_part_name = self.av_obj.all_models[index].logo_inkatlas_part_name
    local lockey = display_name_lockey or "Story-base-gameplay-gui-quests-q103-q103_rogue-_localizationString47"

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

    self.dummy_vehicle_record_hash = TweakDBID.new(self.dummy_vehicle_record).hash
end

function Ui:ResetTweekDB()
	TweakDB:DeleteRecord(self.dummy_vehicle_record)
	TweakDB:DeleteRecord(self.dummy_logo_record)
end

function Ui:SetOverride()
	if not DAV.ready then
		Override("VehicleSystem", "SpawnPlayerVehicle", function(this, vehicle_type, wrapped_method)

			local record_hash = this:GetActivePlayerVehicle(vehicle_type).recordID.hash

			if record_hash == self.dummy_vehicle_record_hash then
				self.log_obj:Record(LogLevel.Trace, "Vehicle call detected")
				self.is_vehicle_call = true
				return false
			else
				local res = wrapped_method(vehicle_type)
				self.is_vehicle_call = false
				return res
			end
		end)
	end
end

function Ui:ActivateAVSummon(is_avtive)
    Game.GetVehicleSystem():EnablePlayerVehicle(self.dummy_vehicle_record, is_avtive, true)
end

function Ui:GetCallStatus()
    local call_status = self.is_vehicle_call
    self.is_vehicle_call = false
    return call_status
end

function Ui:InitVehicleModelList()

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

	for i, seat in ipairs(self.av_obj.all_models[self.selected_vehicle_model_number].active_seat) do
		self.vehicle_seat_list[i] = seat
	end
	self.selected_vehicle_seat_number = DAV.seat_index
	self.selected_vehicle_seat_name = self.vehicle_seat_list[self.selected_vehicle_seat_number]

	self.current_vehicle_model_name = self.vehicle_model_list[self.selected_vehicle_model_number]
	self.current_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]
	self.current_vehicle_seat_name = self.vehicle_seat_list[self.selected_vehicle_seat_number]

end

function Ui:ShowSettingMenu()
    ImGui.SetNextWindowSize(800, 1000, ImGuiCond.Appearing)
    ImGui.Begin("Drive an AV Setting Menu")

	if ImGui.BeginTabBar("DAV Setting Menu") then

		if ImGui.BeginTabItem("Select Vehicle") then
			self:ShowVehicleSetting()
			ImGui.EndTabItem()
		end

		if ImGui.BeginTabItem("Info") then
			self:ShowInfo()
			ImGui.EndTabItem()
		end

		ImGui.EndTabBar()

	end

    ImGui.End()

end

function Ui:ShowVehicleSetting()

	local selected = false

	ImGui.Text("Model: ")
	ImGui.SameLine()
	ImGui.TextColored(0, 1, 0, 1, self.current_vehicle_model_name)
	ImGui.Text("Type : ")
	ImGui.SameLine()
	ImGui.TextColored(0, 1, 0, 1, self.current_vehicle_type_name)
	ImGui.Text("Seat : ")
	ImGui.SameLine()
	ImGui.TextColored(0, 1, 0, 1, self.current_vehicle_seat_name)
	ImGui.Text("Horizenal Boost Ratio : ")
	ImGui.SameLine()
	ImGui.TextColored(0, 1, 0, 1, string.format("%.1f", DAV.horizenal_boost_ratio))

	ImGui.Spacing()

	if not DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.TextColored(1, 0, 0, 1, "The settings menu is currently unavailable")
		ImGui.TextColored(1, 0, 0, 1, "Please despawn your AV by pushing vehicle button")
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

	ImGui.Text("Select the AV you want to drive")
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
		self.selected_vehicle_seat_number = 1
	end

	self.vehicle_type_list = {}
	self.vehicle_seat_list = {}

	for i, type in ipairs(self.av_obj.all_models[self.selected_vehicle_model_number].type) do
		self.vehicle_type_list[i] = type
	end

	for i, seat in ipairs(self.av_obj.all_models[self.selected_vehicle_model_number].active_seat) do
		self.vehicle_seat_list[i] = seat
	end

	self.selected_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]
	self.selected_vehicle_seat_name = self.vehicle_seat_list[self.selected_vehicle_seat_number]

	if self.selected_vehicle_type_name == nil then
		self.selected_vehicle_type_name = self.vehicle_type_list[1]
		return
	end
	if self.selected_vehicle_type_number == nil then
		self.selected_vehicle_type_number = 1
		return
	end

	if self.selected_vehicle_seat_name == nil then
		self.selected_vehicle_seat_name = self.vehicle_seat_list[1]
		return
	end
	if self.selected_vehicle_seat_number == nil then
		self.selected_vehicle_seat_number = 1
		return
	end

	ImGui.Text("Select the type of AV")
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

	ImGui.Text("Select the seat of AV")
	if ImGui.BeginCombo("##AV Seat", self.selected_vehicle_seat_name) then
		for index, value in ipairs(self.vehicle_seat_list) do
			if self.selected_vehicle_seat_name == value then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable(value, selected)) then
				self.selected_vehicle_seat_name = value
				self.selected_vehicle_seat_number = index
			end
		end
		ImGui.EndCombo()
	end

	ImGui.Text("Horizenal Boost Ratio")
	local is_used_slider = false
	DAV.horizenal_boost_ratio, is_used_slider = ImGui.SliderFloat("##Horizenal Boost Ratio", DAV.horizenal_boost_ratio, 1.0, self.max_boost_ratio, "%.1f")

	if not is_used_slider then
		if ImGui.Button("Update", 180, 60) then
			self:SetParameters()
		end
	end

end

function Ui:ShowInfo()
	ImGui.Text("Drive an Aerial Vehicle v" .. DAV.version)
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
	DAV.is_debug_mode = ImGui.Checkbox("Debug Window (Developer Mode)", DAV.is_debug_mode)
end

function Ui:SetParameters()

	DAV.model_index = self.selected_vehicle_model_number
	DAV.model_type_index = self.selected_vehicle_type_number
	DAV.seat_index = self.selected_vehicle_seat_number
	self:ResetTweekDB()
	DAV.core_obj:Reset()
	self:ActivateAVSummon(true)

	self.current_vehicle_model_name = self.vehicle_model_list[self.selected_vehicle_model_number]
	self.current_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]
	self.current_vehicle_seat_name = self.vehicle_seat_list[self.selected_vehicle_seat_number]

	DAV.user_setting_table.model_index = DAV.model_index
	DAV.user_setting_table.model_type_index = DAV.model_type_index
	DAV.user_setting_table.seat_index = DAV.seat_index
	DAV.user_setting_table.horizenal_boost_ratio = DAV.horizenal_boost_ratio
	Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)

end

return Ui