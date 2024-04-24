local AV = require("Modules/av.lua")
local Event = require("Modules/event.lua")
local Log = require("Tools/log.lua")
local Queue = require("Tools/queue.lua")
local Utils = require("Tools/utils.lua")

local Core = {}
Core.__index = Core

function Core:New()

    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Core")
    obj.queue_obj = Queue:New()
    obj.av_obj = nil
    obj.event_obj = nil

    obj.all_models = nil

    obj.av_model_path = "Data/default_model.json"
    obj.heli_input_path = "Data/heli_input.json"
    obj.spinner_input_path = "Data/spinner_input.json"
    obj.axis_dead_zone = 0.5
    obj.relative_dead_zone = 0.01
    obj.relative_table = {}
    obj.relative_resolution = 0.1
    obj.hold_progress = 0.9

    obj.language_file_list = {}
    obj.language_name_list = {}

    obj.max_speed_for_freezing = 75

    -- set default parameters
    obj.heli_input_table = {}
    obj.spinner_input_table = {}
    obj.current_custom_mappin_position = {x = 0, y = 0, z = 0}
    obj.current_purchased_vehicle_count = 0

    obj.is_vehicle_call = false
    obj.is_purchased_vehicle_call = false

    obj.is_freezing = false
    obj.freeze_detect_range_mouse = 1
    obj.freeze_detect_range_stick = 0.1

    obj.initial_user_setting_table = {}

    return setmetatable(obj, self)

end

function Core:Init()

    self.all_models = self:GetAllModel()

    if self.all_models == nil then
        self.log_obj:Record(LogLevel.Error, "Model is nil")
        return
    end

    self:InitGarageInfo()

    -- set initial user setting
    self.initial_user_setting_table = DAV.user_setting_table

    self:LoadSetting()
    self:SetTranslationNameList()

    self.heli_input_table = self:GetInputTable(self.heli_input_path)
    self.spinner_input_table = self:GetInputTable(self.spinner_input_path)

    self.av_obj = AV:New(self.all_models)
    self.av_obj:Init()

    self.event_obj = Event:New()
    self.event_obj:Init(self.av_obj)

    Cron.Every(DAV.time_resolution, function()
        self.event_obj:CheckAllEvents()
        self:GetActions()
    end)

    self:SetInputListener()
    self:SetCustomMappinPosition()

    self:SetOverride()

end

function Core:Reset()

    self.av_obj = AV:New(self.all_models)
    self.av_obj:Init()

    self.event_obj:Init(self.av_obj)

end

function Core:LoadSetting()

    local setting_data = Utils:ReadJson(DAV.user_setting_path)
    if setting_data.version == DAV.version then
        DAV.user_setting_table = setting_data

        -- grobal
        DAV.model_index = DAV.user_setting_table.model_index
        DAV.model_type_index = DAV.user_setting_table.model_type_index

        --- garage
        DAV.garage_info_list = DAV.user_setting_table.garage_info_list

        --- free summon mode
        DAV.is_free_summon_mode = DAV.user_setting_table.is_free_summon_mode
        DAV.model_index_in_free = DAV.user_setting_table.model_index_in_free
        DAV.model_type_index_in_free = DAV.user_setting_table.model_type_index_in_free

        --- control
        DAV.flight_mode = DAV.user_setting_table.flight_mode
        DAV.is_disable_heli_roll_tilt = DAV.user_setting_table.is_disable_heli_roll_tilt
        DAV.is_disable_heli_pitch_tilt = DAV.user_setting_table.is_disable_heli_pitch_tilt
        DAV.heli_heli_horizenal_boost_ratio = DAV.user_setting_table.heli_horizenal_boost_ratio
        DAV.is_disable_spinner_roll_tilt = DAV.user_setting_table.is_disable_spinner_roll_tilt

        --- environment
        DAV.is_enable_community_spawn = DAV.user_setting_table.is_enable_community_spawn
        DAV.spawn_frequency = DAV.user_setting_table.spawn_frequency

        --- general
        DAV.language_index = DAV.user_setting_table.language_index
        DAV.is_unit_km_per_hour = DAV.user_setting_table.is_unit_km_per_hour
    end

end

function Core:ResetSetting()

    DAV.user_setting_table = self.initial_user_setting_table

    self:UpdateGarageInfo(true)
    for key, _ in ipairs(DAV.user_setting_table.garage_info_list) do
        DAV.garage_info_list[key].type_index = 1
    end

    Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)

    self:LoadSetting()

    self:Reset()

end

function Core:SetOverride()

	if not DAV.is_ready then
		Override("VehicleSystem", "SpawnPlayerVehicle", function(this, vehicle_type, wrapped_method)
			local record_id = this:GetActivePlayerVehicle(vehicle_type).recordID

			if self.event_obj.ui_obj.dummy_av_record.hash == record_id.hash then
				self.log_obj:Record(LogLevel.Trace, "Free Summon AV call detected")
                DAV.model_index = DAV.model_index_in_free
                DAV.model_type_index = DAV.model_type_index_in_free
                self.av_obj:Init()
				self.is_vehicle_call = true
				return false
			end
			local str = string.gsub(record_id.value, "_dummy", "")
			local new_record_id = TweakDBID.new(str)
			for _, record in ipairs(self.event_obj.ui_obj.av_record_list) do
				if record.hash == new_record_id.hash then
					self.log_obj:Record(LogLevel.Trace, "Purchased AV call detected")
					for key, value in ipairs(self.av_obj.all_models) do
						if value.tweakdb_id == record.value then
							DAV.model_index = key
							DAV.model_type_index = DAV.garage_info_list[key].type_index
							self.av_obj:Init()
							break
						end
					end
					self.is_purchased_vehicle_call = true
					return false
				end
			end
			local res = wrapped_method(vehicle_type)
			self.is_vehicle_call = false
			self.is_purchased_vehicle_call = false
			return res
		end)
	end

end

function Core:ActivateDummySummon(is_avtive)
    Game.GetVehicleSystem():EnablePlayerVehicle(self.event_obj.ui_obj.dummy_vehicle_record, is_avtive, true)
end

function Core:GetCallStatus()
    local call_status = self.is_vehicle_call
    self.is_vehicle_call = false
    return call_status
end

function Core:GetPurchasedCallStatus()
    local call_status = self.is_purchased_vehicle_call
    self.is_purchased_vehicle_call = false
    return call_status
end

function Core:SetTranslationNameList()

    self.language_file_list = {}
    self.language_name_list = {}

    local files = dir(DAV.language_path)
    local default_file
    local other_files = {}

    for _, file in ipairs(files) do
        if string.match(file.name, 'default.json') then
            default_file = file
        elseif string.match(file.name, '%a%a%-%a%a.json') then
            table.insert(other_files, file)
        end
    end

    if default_file then
        local default_language_table = Utils:ReadJson(DAV.language_path .. "/" .. default_file.name)
        if default_language_table and default_language_table.language then
            table.insert(self.language_file_list, default_file)
            table.insert(self.language_name_list, default_language_table.language)
        end
    else
        self.log_obj:Record(LogLevel.Critical, "Default Language File is not found")
        return
    end

    for _, file in ipairs(other_files) do
        local language_table = Utils:ReadJson(DAV.language_path .. "/" .. file.name)
        if language_table and language_table.language then
            table.insert(self.language_file_list, file)
            table.insert(self.language_name_list, language_table.language)
        end
    end

end

function Core:GetTranslationText(text)

    local language_table = Utils:ReadJson((DAV.language_path .. "/" .. self.language_file_list[DAV.language_index].name))

    if table == nil then
        self.log_obj:Record(LogLevel.Critical, "Language File is invalid")
        return nil
    end
    local translated_text = language_table[text]
    if translated_text == nil then
        self.log_obj:Record(LogLevel.Warning, "Translation is not found")
        language_table = Utils:ReadJson((DAV.language_path .. "/" .. self.language_file_list[1].name))
        translated_text = language_table[text]
        if translated_text == nil then
            self.log_obj:Record(LogLevel.Error, "Translation is not found in default language")
            translated_text = "???"
        end
        return translated_text
    end

    return translated_text

end

function Core:SetInputListener()

    local player = Game.GetPlayer()

    player:UnregisterInputListener(player, "dav_heli_lift")
    player:UnregisterInputListener(player, "dav_heli_forward_backward")
    player:UnregisterInputListener(player, "dav_heli_left_right")
    player:UnregisterInputListener(player, "dav_heli_rotate")
    player:UnregisterInputListener(player, "dav_heli_hover")
    player:UnregisterInputListener(player, "dav_spinner_forward_backward")
    player:UnregisterInputListener(player, "dav_spinner_left_right")
    player:UnregisterInputListener(player, "dav_spinner_up")
    player:UnregisterInputListener(player, "dav_spinner_down")
    player:UnregisterInputListener(player, "dav_get_on")
    player:UnregisterInputListener(player, "dav_get_off")
    player:UnregisterInputListener(player, "dav_change_view")
    player:UnregisterInputListener(player, "dav_toggle_door_1")
    player:UnregisterInputListener(player, "dav_toggle_auto_pilot")

    player:RegisterInputListener(player, "dav_heli_lift")
    player:RegisterInputListener(player, "dav_heli_forward_backward")
    player:RegisterInputListener(player, "dav_heli_left_right")
    player:RegisterInputListener(player, "dav_heli_rotate")
    player:RegisterInputListener(player, "dav_heli_hover")
    player:RegisterInputListener(player, "dav_spinner_forward_backward")
    player:RegisterInputListener(player, "dav_spinner_left_right")
    player:RegisterInputListener(player, "dav_spinner_up")
    player:RegisterInputListener(player, "dav_spinner_down")
    player:RegisterInputListener(player, "dav_get_on")
    player:RegisterInputListener(player, "dav_get_off")
    player:RegisterInputListener(player, "dav_change_view")
    player:RegisterInputListener(player, "dav_toggle_door_1")
    player:RegisterInputListener(player, "dav_toggle_auto_pilot")

    local exception_list = Utils:ReadJson("Data/exception_input.json")

    Observe("PlayerPuppet", "OnAction", function(this, action, consumer)
        local action_name = action:GetName(action).value
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
            for _, exception in pairs(exception_list) do
                if string.find(action_name, exception) then
                    consumer:Consume()
                    return
                end
            end
        end

        if (string.match(action_name, "mouse") and action_value > self.freeze_detect_range_mouse) or (string.match(action_name, "right_stick") and action_value > self.freeze_detect_range_stick) then
            self.is_freezing = true
        end

        if DAV.is_debug_mode then
            DAV.debug_obj:PrintActionCommand(action_name, action_type, action_value)
        end

        self:StorePlayerAction(action_name, action_type, action_value)

    end)

end

function Core:IsEnableFreeze()

    if not DAV.is_enable_community_spawn then
        return false
    end

    local freeze = self.is_freezing
    self.is_freezing = false
    if freeze and self.av_obj.engine_obj:GetSpeed() < self.max_speed_for_freezing then
        return true
    else
        return false
    end

end

function Core:SetCustomMappinPosition()

    Observe('BaseWorldMapMappinController', 'SelectMappin', function(this)
		local mappin = this.mappin
        if mappin:GetVariant() == gamedataMappinVariant.CustomPositionVariant then
            local pos = mappin:GetWorldPosition()
            self.current_custom_mappin_position = {x = pos.x, y = pos.y, z = pos.z}
            self.av_obj:SetDestination(pos)
        end

	end)

end

function Core:GetAllModel()

    local model = Utils:ReadJson(self.av_model_path)

    if model == nil then
        self.log_obj:Record(LogLevel.Error, "Default Model is nil")
        return nil
    end
    return model

end

function Core:InitGarageInfo()

    DAV.garage_info_list = {}

    for index, model in ipairs(self.all_models) do
        local garage_info = {name = "", model_index = 1, type_index = 1, is_purchased = false}
        garage_info.name = model.tweakdb_id
        garage_info.model_index = index
        table.insert(DAV.garage_info_list, garage_info)
    end

    DAV.user_setting_table.garage_info_list = DAV.garage_info_list

end

function Core:UpdateGarageInfo(is_force_update)

    local list = Game.GetVehicleSystem():GetPlayerUnlockedVehicles()

    if (self.current_purchased_vehicle_count == #list or #list == 0) and not is_force_update then
        return
    else
        self.current_purchased_vehicle_count = #list
    end

    for _, garage_info in ipairs(DAV.garage_info_list) do
        garage_info.is_purchased = false
    end

    for _, purchased_vehicle in ipairs(list) do
        if string.match(purchased_vehicle.recordID.value, "_dummy") then
            local purchased_vehicle_name = string.gsub(purchased_vehicle.recordID.value, "_dummy", "")
            for index, garage_info in ipairs(DAV.garage_info_list) do
                if garage_info.name == purchased_vehicle_name then
                    DAV.garage_info_list[index].is_purchased = true
                    break
                end
            end
        end
    end

    DAV.user_setting_table.garage_info_list = DAV.garage_info_list
	Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)

end

function Core:ChangeGarageAVType(name, type_index)

    self:UpdateGarageInfo(false)

    for idx, garage_info in ipairs(DAV.garage_info_list) do
        if garage_info.name == name then
            DAV.garage_info_list[idx].type_index = type_index
            break
        end
    end

    DAV.user_setting_table.garage_info_list = DAV.garage_info_list
	Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)

end

function Core:GetInputTable(input_path)

    local input = Utils:ReadJson(input_path)

    if input == nil then
        self.log_obj:Record(LogLevel.Error, "Input is nil")
        return nil
    end
    return input

end

function Core:StorePlayerAction(action_name, action_type, action_value)

    local action_value_type = "ZERO"

    if action_type == "RELATIVE_CHANGE" then
        if action_value > self.relative_dead_zone then
            action_value_type = "POSITIVE"
        elseif action_value < -self.relative_dead_zone then
            action_value_type = "NEGATIVE"
        else
            action_value_type = "ZERO"
        end
    elseif action_type == "BUTTON_HOLD_PROGRESS" then
        if action_value > self.hold_progress then
            action_value_type = "POSITIVE"
        else
            action_value_type = "ZERO"
        end
    else
        if action_value > self.axis_dead_zone then
            action_value_type = "POSITIVE"
        elseif action_value < -self.axis_dead_zone then
            action_value_type = "NEGATIVE"
        else
            action_value_type = "ZERO"
        end
    end

    local cmd, loop_count = 0, 1

    if DAV.flight_mode == Def.FlightMode.Heli then
        cmd, loop_count = self:ConvertHeliActionList(action_name, action_type, action_value_type)
    elseif DAV.flight_mode == Def.FlightMode.Spinner then
        cmd, loop_count = self:ConvertSpinnerActionList(action_name, action_type, action_value_type)
    end

    for _ = 1, loop_count do
        if cmd ~= Def.ActionList.Nothing then
            self.queue_obj:Enqueue(cmd)
        end
    end

end

function Core:ConvertHeliActionList(action_name, action_type, action_value_type)

    local action_command = Def.ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value_type}
    local loop_count = 1

    if Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_ACCELERTOR) then
        action_command = Def.ActionList.HeliUp
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_DOWN) then
        action_command = Def.ActionList.HeliDown
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_FORWARD_MOVE) then
        action_command = Def.ActionList.HeliForward
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_BACK_MOVE) then
        action_command = Def.ActionList.HeliBackward
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_RIGHT_MOVE) then
        action_command = Def.ActionList.HeliRight
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_LEFT_MOVE) then
        action_command = Def.ActionList.HeliLeft
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_RIGHT_ROTATE) then
        action_command = Def.ActionList.HeliTurnRight
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_LEFT_ROTATE) then
        action_command = Def.ActionList.HeliTurnLeft
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_HOVER) then
        action_command = Def.ActionList.HeliHover
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_HOLD) then
        action_command = Def.ActionList.HeliHold
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_WORLD_ENTER_AV) then
        action_command = Def.ActionList.Enter
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_EXIT_AV) then
        action_command = Def.ActionList.Exit
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_CAMERA) then
        action_command = Def.ActionList.ChangeCamera
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_TOGGLE_DOOR_1) then
        action_command = Def.ActionList.ChangeDoor1
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_AV_TOGGLE_AUTO_PILOT) then
        action_command = Def.ActionList.AutoPilot
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_WORLD_SELECT_UPPER_CHOICE) then
        action_command = Def.ActionList.SelectUp
    elseif Utils:IsTablesNearlyEqual(action_dist, self.heli_input_table.KEY_WORLD_SELECT_LOWER_CHOICE) then
        action_command = Def.ActionList.SelectDown
    else
        action_command = Def.ActionList.Nothing
    end

    return action_command, loop_count

end

function Core:ConvertSpinnerActionList(action_name, action_type, action_value_type)

    local action_command = Def.ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value_type}
    local loop_count = 1

    if Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_FORWARD_MOVE) then
        action_command = Def.ActionList.SpinnerForward
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_BACK_MOVE) then
        action_command = Def.ActionList.SpinnerBackward
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_RIGHT_MOVE) then
        action_command = Def.ActionList.SpinnerRight
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_LEFT_MOVE) then
        action_command = Def.ActionList.SpinnerLeft
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_UP_MOVE) then
        action_command = Def.ActionList.SpinnerUp
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_DOWN_MOVE) then
        action_command = Def.ActionList.SpinnerDown
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_WORLD_ENTER_AV) then
        action_command = Def.ActionList.Enter
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_EXIT_AV) then
        action_command = Def.ActionList.Exit
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_CAMERA) then
        action_command = Def.ActionList.ChangeCamera
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_TOGGLE_DOOR_1) then
        action_command = Def.ActionList.ChangeDoor1
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_AV_TOGGLE_AUTO_PILOT) then
        action_command = Def.ActionList.AutoPilot
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_WORLD_SELECT_UPPER_CHOICE) then
        action_command = Def.ActionList.SelectUp
    elseif Utils:IsTablesNearlyEqual(action_dist, self.spinner_input_table.KEY_WORLD_SELECT_LOWER_CHOICE) then
        action_command = Def.ActionList.SelectDown
    else
        action_command = Def.ActionList.Nothing
    end

    return action_command, loop_count

end

function Core:GetActions()

    local move_actions = {}

    if self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.queue_obj:Clear()
        return
    end

    while not self.queue_obj:IsEmpty() do
        local action = self.queue_obj:Dequeue()
        if action >= Def.ActionList.Enter then
            self:SetEvent(action)
        else
            table.insert(move_actions, action)
        end
    end

    if #move_actions == 0 then
        table.insert(move_actions, Def.ActionList.Nothing)
    end

    self:OperateAerialVehicle(move_actions)

end

function Core:OperateAerialVehicle(actions)

    if not self.is_locked_operation then
        if self.event_obj:IsInVehicle() then
            self.av_obj:Operate(actions)
        elseif self.event_obj:IsWaiting() then
            self.av_obj:Operate({Def.ActionList.Nothing})
        end
    end

end

function Core:SetEvent(action)

    if action == Def.ActionList.Enter then
        self.event_obj:EnterVehicle()
    elseif action == Def.ActionList.Exit then
        self.event_obj:ExitVehicle()
    elseif action == Def.ActionList.ChangeCamera then
        self:ToggleCamera()
    elseif action == Def.ActionList.ChangeDoor1 then
        self.event_obj:ChangeDoor()
    elseif action == Def.ActionList.AutoPilot then
        self.event_obj:ToggleAutoMode()
    elseif action == Def.ActionList.SelectUp then
        self.event_obj:SelectChoice(Def.ActionList.SelectUp)
    elseif action == Def.ActionList.SelectDown then
        self.event_obj:SelectChoice(Def.ActionList.SelectDown)
    end

end

function Core:ToggleCamera()

    if self.event_obj:IsInVehicle() then
        self.av_obj.camera_obj:Toggle()
    end

end

return Core
