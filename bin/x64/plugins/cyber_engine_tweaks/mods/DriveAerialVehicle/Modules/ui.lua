local Log = require("Tools/log.lua")
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
    obj.all_av_models = nil

    -- set default value
    obj.dummy_vehicle_record_hash = nil
    obj.is_vehicle_call = false
    obj.vehicle_model_list = {}
	obj.selected_vehicle_model_name = ""
    obj.selected_vehicle_model_number = 1
	obj.vehicle_type_list = {}
	obj.selected_vehicle_type_name = ""
	obj.selected_vehicle_type_number = 1
	obj.vehicle_door_list = {}
	obj.selected_vehicle_door_name = ""
	obj.selected_vehicle_door_number = 1
	obj.vehicle_seat_list = {}
	obj.selected_vehicle_seat_name = ""
	obj.selected_vehicle_seat_number = 1

    return setmetatable(obj, self)
end

function Ui:Init(av_obj)
	self.av_obj = av_obj
    self.all_av_models = av_obj.all_models
    self:SetTweekDB()
    self:SetOverride()
	self:InitVehicleModelList()
end

function Ui:SetTweekDB()
	local index = self.av_obj.model_index
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
		Override("VehicleSystem", "SpawnPlayerVehicle", function(this, arg_1, wrapped_method)

			local record_hash = this:GetActivePlayerVehicle().recordID.hash

			if record_hash == self.dummy_vehicle_record_hash then
				self.log_obj:Record(LogLevel.Trace, "Vehicle call detected")        
				self.is_vehicle_call = true
				return false
			else
				local res = false
				if arg_1 == nil then
					res = wrapped_method()
				else
					res = wrapped_method(arg_1)
				end
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

	for i, model in ipairs(self.all_av_models) do
        self.vehicle_model_list[i] = model.name
	end
	self.selected_vehicle_model_number = 1
	self.selected_vehicle_model_name = self.vehicle_model_list[1]

	for i, type in ipairs(self.all_av_models[self.selected_vehicle_model_number].type) do
		self.vehicle_type_list[i] = type
	end
	self.selected_vehicle_type_number = 1
	self.selected_vehicle_type_name = self.vehicle_type_list[1]

	for i, door in ipairs(self.all_av_models[self.selected_vehicle_model_number].active_door) do
		self.vehicle_door_list[i] = door
	end
	self.selected_vehicle_door_number = 1
	self.selected_vehicle_door_name = self.vehicle_door_list[1]

	for i, seat in ipairs(self.all_av_models[self.selected_vehicle_model_number].active_seat) do
		self.vehicle_seat_list[i] = seat
	end
	self.selected_vehicle_seat_number = 1
	self.selected_vehicle_seat_name = self.vehicle_seat_list[1]

end

function Ui:ShowSettingMenu()
	local selected = false
    ImGui.SetNextWindowSize(800, 1000, ImGuiCond.Appearing)
    ImGui.Begin("Drive an AV Setting Menu")
	if not DAV.core_obj.event_obj:IsNotSpawned() then
		ImGui.Text("Setting is not available while driving an AV.")
		ImGui.Text("Please despawn your AV by pushing vehicle button.")
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

	self.vehicle_type_list = {}
	self.vehicle_door_list = {}
	self.vehicle_seat_list = {}

	for i, type in ipairs(self.all_av_models[self.selected_vehicle_model_number].type) do
		self.vehicle_type_list[i] = type
	end

	for i, door in ipairs(self.all_av_models[self.selected_vehicle_model_number].active_door) do
		self.vehicle_door_list[i] = door
	end

	for i, seat in ipairs(self.all_av_models[self.selected_vehicle_model_number].active_seat) do
		self.vehicle_seat_list[i] = seat
	end

	self.selected_vehicle_type_name = self.vehicle_type_list[self.selected_vehicle_type_number]
	self.selected_vehicle_door_name = self.vehicle_door_list[self.selected_vehicle_door_number]
	self.selected_vehicle_seat_name = self.vehicle_seat_list[self.selected_vehicle_seat_number]

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

	ImGui.Text("Select the door of AV")
	if ImGui.BeginCombo("##AV Door", self.selected_vehicle_door_name) then
		for index, value in ipairs(self.vehicle_door_list) do
			if self.selected_vehicle_door_name == value then
				selected = true
			else 
				selected = false
			end
			if(ImGui.Selectable(value, selected)) then
				self.selected_vehicle_door_name = value
				self.selected_vehicle_door_number = index
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

	if ImGui.Button("Update", 150, 80) then
		self:SetParameters()
	end

    ImGui.End()
end

function Ui:SetParameters()

	self.av_obj.model_index = self.selected_vehicle_model_number
	self.av_obj.model_type_index = self.selected_vehicle_type_number
	self.av_obj.open_door_index = self.selected_vehicle_door_number
	self.av_obj.seat_index = self.selected_vehicle_seat_number
	self.av_obj:SetModel()
	DAV.core_obj.event_obj.hud_obj:SetChoiceTitle()
	self:ResetTweekDB()
	self:SetTweekDB()
	self:ActivateAVSummon(true)

end

return Ui