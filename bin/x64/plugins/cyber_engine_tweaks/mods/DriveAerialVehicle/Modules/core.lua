local AV = require("Modules/av.lua")
local Event = require("Modules/event.lua")
local Queue = require("Tools/queue.lua")
local Utils = require("Tools/utils.lua")

local Core = {}
Core.__index = Core

function Core:New()
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Core")
    obj.queue_obj = Queue:New()
    obj.av_obj = nil
    obj.event_obj = nil
    -- static --
    -- lock
    obj.delay_action_time_in_waiting = 0.05
    obj.delay_action_time_in_vehicle = 0.05
    -- import path
    obj.av_model_path = "Data/default_model.json"
    obj.input_key_path = "Data/input_key.json"
    -- input setting
    obj.axis_dead_zone = 0.5
    obj.relative_dead_zone = 0.01
    obj.relative_resolution = 0.1
    obj.hold_progress = 0.9
    -- custom mappin
    obj.huge_distance = 1000000
    obj.max_mappin_history = 10
    -- radio
    obj.default_station_num = 13
    obj.get_track_name_time_resolution = 1
    -- dynamic --
    -- lock
    obj.is_locked_action_in_waiting = false
    obj.is_locked_action_in_vehicle = false
    -- model table
    obj.all_models = nil
    -- input table
    obj.input_key_table = {}
    obj.relative_table = {}
    obj.hold_time_resolution = 0.1
    obj.radio_hold_complete_time_count = 5
    obj.radio_button_hold_count = 0
    obj.is_radio_button_hold_counter = false
    -- AV
    obj.move_up_button_hold_count = 0
    obj.max_move_hold_count = 50000
    obj.is_move_up_button_hold_counter = false
    obj.move_down_button_hold_count = 0
    obj.is_move_down_button_hold_counter = false
    obj.move_left_button_hold_count = 0
    obj.is_move_left_button_hold_counter = false
    obj.move_right_button_hold_count = 0
    obj.is_move_right_button_hold_counter = false
    obj.lean_reset_button_hold_count = 0
    obj.is_lean_reset_button_hold_counter = false
    obj.auto_pilot_hold_complete_time_count = 5
    obj.auto_pilot_button_hold_count = 0
    obj.is_auto_pilot_button_hold_counter = false
    -- Helicopter
    obj.h_ascend_button_hold_count = 0
    obj.is_h_ascend_button_hold_counter = false
    obj.h_descend_button_hold_count = 0
    obj.is_h_descend_button_hold_counter = false
    obj.h_turn_left_button_hold_count = 0
    obj.is_h_turn_left_button_hold_counter = false
    obj.h_turn_right_button_hold_count = 0
    obj.is_h_turn_right_button_hold_counter = false
    obj.h_acceleration_button_hold_count = 0
    obj.is_h_acceleration_button_hold_counter = false
    -- user setting table
    obj.initial_user_setting_table = {}
    -- language table
    obj.language_file_list = {}
    obj.language_name_list = {}
    obj.translation_table_list = {}
    -- summon
    obj.current_purchased_vehicle_count = 0
    -- obj.is_purchased_vehicle_call = false
    -- custom mappin
    obj.current_custom_mappin_position = Vector4.new(0, 0, 0, 1)
    obj.fast_travel_position_list = {}
    obj.ft_index_nearest_mappin = 1
    obj.ft_to_mappin_distance = obj.huge_distance
    obj.ft_index_nearest_favorite = 1
    obj.ft_to_favorite_distance = obj.huge_distance
    obj.mappin_controller = nil
    obj.dist_mappin_id = nil
    obj.is_custom_mappin = false
    -- radio
    obj.current_station_index = -1
    obj.current_radio_volume = 50
    obj.is_opened_radio_popup = false
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
    self:StoreTranslationtableList()

    self.input_key_table = self:GetInputTable(self.input_key_path)

    self.av_obj = AV:New(self.all_models)
    self.av_obj:Init()

    self.event_obj = Event:New()
    self.event_obj:Init(self.av_obj)

    Cron.Every(DAV.time_resolution, function()
        self.event_obj:CheckAllEvents()
        self:GetActions()
    end)

    -- set observer
    self:SetInputListener()
    self:SetMappinController()
    self:SetSummonTrigger()

end

function Core:Reset()
    self.av_obj = AV:New(self.all_models)
    self.av_obj:Init()
    self.event_obj:Init(self.av_obj)
end

function Core:LoadSetting()

    local setting_data = Utils:ReadJson(DAV.user_setting_path)
    if setting_data == nil then
        self.log_obj:Record(LogLevel.Error, "Failed to load setting data. Restore default setting")
        Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
        return
    end
    if setting_data.version == DAV.version then
        DAV.user_setting_table = setting_data
    end

end

function Core:ResetSetting()

    DAV.user_setting_table = self.initial_user_setting_table
    self:UpdateGarageInfo(true)
    for key, _ in ipairs(DAV.user_setting_table.garage_info_list) do
        DAV.user_setting_table.garage_info_list[key].type_index = 1
    end
    Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
    self:Reset()

end

function Core:SetSummonTrigger()

    Override("VehicleSystem", "SpawnPlayerVehicle", function(this, vehicle_type, wrapped_method)
        local record_id = this:GetActivePlayerVehicle(vehicle_type).recordID
        local prev_model_index = DAV.model_index

        local av_record_name = string.gsub(record_id.value, "_dummy", "")
        local new_record_id = TweakDBID.new(av_record_name)
        for index, record in ipairs(self.event_obj.ui_obj.av_record_list) do
            if record.hash == new_record_id.hash then
                self.log_obj:Record(LogLevel.Trace, "Purchased AV call detected")
                for key, value in ipairs(self.av_obj.all_models) do
                    if value.tweakdb_id == record.value then
                        DAV.model_index = key
                        DAV.model_type_index = DAV.user_setting_table.garage_info_list[key].type_index
                        self.av_obj:Init()
                        break
                    end
                end
                -- self.is_purchased_vehicle_call = true
                if self.event_obj:IsNotSpawned() then
                    self.event_obj:CallVehicle()
                elseif self.event_obj:IsWaiting() then
                    if prev_model_index ~= DAV.model_index then
                        self.event_obj:CallVehicle()
                    else
                        self.event_obj:ReturnVehicle()
                    end
                end
                return false
            end
        end
        return wrapped_method(vehicle_type)
    end)

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

function Core:StoreTranslationtableList()

    self.translation_table_list = {}
    for _, file in ipairs(self.language_file_list) do
        local language_table = Utils:ReadJson(DAV.language_path .. "/" .. file.name)
        if language_table then
            table.insert(self.translation_table_list, language_table)
        end
    end

end

function Core:GetTranslationText(text)

    if self.translation_table_list == {} then
        self.log_obj:Record(LogLevel.Critical, "Language File is invalid")
        return nil
    end
    local translated_text = self.translation_table_list[DAV.user_setting_table.language_index][text]
    if translated_text == nil then
        self.log_obj:Record(LogLevel.Warning, "Translation is not found")
        translated_text = self.translation_table_list[1][text]
        if translated_text == nil then
            self.log_obj:Record(LogLevel.Error, "Translation is not found in default language")
            translated_text = "???"
        end
        return translated_text
    end

    return translated_text

end

function Core:SetInputListener()

    local exception_in_entry_area_list = Utils:ReadJson("Data/exception_in_entry_area_input.json")
    local exception_in_veh_list = Utils:ReadJson("Data/exception_in_veh_input.json")

    Observe("PlayerPuppet", "OnAction", function(this, action, consumer)

        if self.event_obj.current_situation ~= Def.Situation.Waiting and self.event_obj.current_situation ~= Def.Situation.InVehicle then
            return
        end

        local action_name = action:GetName(action).value
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
            for _, exception in pairs(exception_in_veh_list) do
                if action_name == exception then
                    consumer:Consume()
                end
            end
        elseif self.event_obj:IsInEntryArea() then
            for _, exception in pairs(exception_in_entry_area_list) do
                if action_name == exception then
                    consumer:Consume()
                end
            end
        end

        self.log_obj:Record(LogLevel.Debug, "Action Name: " .. action_name .. " Type: " .. action_type .. " Value: " .. action_value)

        self:StorePlayerAction(action_name, action_type, action_value)

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

    DAV.user_setting_table.garage_info_list = {}

    for index, model in ipairs(self.all_models) do
        local garage_info = {name = "", model_index = 1, type_index = 1, is_purchased = false}
        garage_info.name = model.tweakdb_id
        garage_info.model_index = index
        table.insert(DAV.user_setting_table.garage_info_list, garage_info)
    end

end

function Core:UpdateGarageInfo(is_force_update)

    local list = Game.GetVehicleSystem():GetPlayerUnlockedVehicles()
    if (self.current_purchased_vehicle_count == #list or #list == 0) and not is_force_update then
        return
    else
        self.current_purchased_vehicle_count = #list
    end

    for _, garage_info in ipairs(DAV.user_setting_table.garage_info_list) do
        garage_info.is_purchased = false
    end

    for _, purchased_vehicle in ipairs(list) do
        if string.match(purchased_vehicle.recordID.value, "_dummy") then
            local purchased_vehicle_name = string.gsub(purchased_vehicle.recordID.value, "_dummy", "")
            for index, garage_info in ipairs(DAV.user_setting_table.garage_info_list) do
                if garage_info.name == purchased_vehicle_name then
                    DAV.user_setting_table.garage_info_list[index].is_purchased = true
                    break
                end
            end
        end
    end

	Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)

end

function Core:ChangeGarageAVType(name, type_index)

    self:UpdateGarageInfo(false)

    for idx, garage_info in ipairs(DAV.user_setting_table.garage_info_list) do
        if garage_info.name == name then
            DAV.user_setting_table.garage_info_list[idx].type_index = type_index
            break
        end
    end

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

    local cmd = 0

    cmd = self:ConvertActionList(action_name, action_type, action_value_type)

    if cmd ~= Def.ActionList.Nothing then
        self.queue_obj:Enqueue(cmd)
    end

end

function Core:ConvertActionList(action_name, action_type, action_value_type)

    local flight_mode = self.av_obj.engine_obj.flight_mode
    if flight_mode == Def.FlightMode.AV then
        return self:GetAVAction(action_name, action_type, action_value_type)
    elseif flight_mode == Def.FlightMode.Helicopter then
        return self:GetHeliAction(action_name, action_type, action_value_type)
    end

end

function Core:GetAVAction(action_name, action_type, action_value_type)

    local action_command = Def.ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value_type}

    if self.event_obj.current_situation == Def.Situation.InVehicle then
        if Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_AV_FORWARD_MOVE) then
            action_command = Def.ActionList.Forward
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_AV_BACK_MOVE) then
            action_command = Def.ActionList.Backward
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_AV_RIGHT_ROTATE) then
            action_command = Def.ActionList.RightRotate
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_AV_LEFT_ROTATE) then
            action_command = Def.ActionList.LeftRotate
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_AV_LEAN_FORWARD) then
            action_command = Def.ActionList.LeanForward
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_AV_LEAN_BACKWARD) then
            action_command = Def.ActionList.LeanBackward
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_AV_EXIT_AV) then
            action_command = Def.ActionList.Exit
        end
    elseif self.event_obj.current_situation == Def.Situation.Waiting then
        if Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_WORLD_ENTER_AV) then
            action_command = Def.ActionList.Enter
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_WORLD_SELECT_UPPER_CHOICE) then
            action_command = Def.ActionList.SelectUp
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_WORLD_SELECT_LOWER_CHOICE) then
            action_command = Def.ActionList.SelectDown
        end
    end

    return action_command

end

function Core:GetHeliAction(action_name, action_type, action_value_type)

    local action_command = Def.ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value_type}

    if self.event_obj.current_situation == Def.Situation.InVehicle then
        if DAV.is_keyboard_input and Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_HELI_LEAN_FORWARD) then
            action_command = Def.ActionList.HLeanForward
        elseif not DAV.is_keyboard_input and Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.PAD_HELI_LEAN_FORWARD) then
            action_command = Def.ActionList.HLeanForward
        elseif DAV.is_keyboard_input and Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_HELI_LEAN_BACKWARD) then
            action_command = Def.ActionList.HLeanBackward
        elseif not DAV.is_keyboard_input and Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.PAD_HELI_LEAN_BACKWARD) then
            action_command = Def.ActionList.HLeanBackward
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_HELI_LEAN_RIGHT) then
            action_command = Def.ActionList.HLeanRight
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_HELI_LEAN_LEFT) then
            action_command = Def.ActionList.HLeanLeft
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_AV_EXIT_AV) then
            action_command = Def.ActionList.Exit
        end
    elseif self.event_obj.current_situation == Def.Situation.Waiting then
        if Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_WORLD_ENTER_AV) then
            action_command = Def.ActionList.Enter
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_WORLD_SELECT_UPPER_CHOICE) then
            action_command = Def.ActionList.SelectUp
        elseif Utils:IsTablesNearlyEqual(action_dist, self.input_key_table.KEY_WORLD_SELECT_LOWER_CHOICE) then
            action_command = Def.ActionList.SelectDown
        end
    end

    return action_command

end

function Core:ConvertHoldButtonAction(key)

    local keybind_name = ""
    if self.av_obj.engine_obj.flight_mode == Def.FlightMode.AV then
        for _, keybind in ipairs(DAV.user_setting_table.keybind_table) do
            if key == keybind.key or key == keybind.pad then
                keybind_name = keybind.name
                self:ConvertAVHoldAction(keybind_name)
                return
            end
        end
    elseif self.av_obj.engine_obj.flight_mode == Def.FlightMode.Helicopter then
        for _, keybind in ipairs(DAV.user_setting_table.heli_keybind_table) do
            if key == keybind.key or key == keybind.pad then
                keybind_name = keybind.name
                self:ConvertHeliHoldAction(keybind_name)
                return
            end
        end
    end
    for _, keybind in ipairs(DAV.user_setting_table.common_keybind_table) do
        if key == keybind.key or key == keybind.pad then
            keybind_name = keybind.name
            self:ConvertCommonHoldAction(keybind_name)
            return
        end
    end

end

function Core:ConvertAVHoldAction(keybind_name)

    if keybind_name == "move_up" then
        self.is_move_up_button_hold_counter = false
        self.move_up_button_hold_count = 0
    elseif keybind_name == "move_down" then
        self.is_move_down_button_hold_counter = false
        self.move_down_button_hold_count = 0
    elseif keybind_name == "move_left" then
        self.is_move_left_button_hold_counter = false
        self.move_left_button_hold_count = 0
    elseif keybind_name == "move_right" then
        self.is_move_right_button_hold_counter = false
        self.move_right_button_hold_count = 0
    elseif keybind_name == "lean_reset" then
        self.is_lean_reset_button_hold_counter = false
        self.lean_reset_button_hold_count = 0
    end

end

function Core:ConvertHeliHoldAction(keybind_name)

    if keybind_name == "ascend" then
        self.is_h_ascend_button_hold_counter = false
        self.h_ascend_button_hold_count = 0
    elseif keybind_name == "descend" then
        self.is_h_descend_button_hold_counter = false
        self.h_descend_button_hold_count = 0
    elseif keybind_name == "turn_left" then
        self.is_h_turn_left_button_hold_counter = false
        self.h_turn_left_button_hold_count = 0
    elseif keybind_name == "turn_right" then
        self.is_h_turn_right_button_hold_counter = false
        self.h_turn_right_button_hold_count = 0
    elseif keybind_name == "acceleration" then
        self.is_h_acceleration_button_hold_counter = false
        self.h_acceleration_button_hold_count = 0
    end

end

function Core:ConvertCommonHoldAction(keybind_name)

    if keybind_name == "toggle_radio" then
        self.is_radio_button_hold_counter = false
        self.radio_button_hold_count = 0
    elseif keybind_name == "toggle_autopilot" then
        self.is_auto_pilot_button_hold_counter = false
        self.auto_pilot_button_hold_count = 0
    end

end

function Core:ConvertPressButtonAction(key)

    local keybind_name = ""
    if self.av_obj.engine_obj.flight_mode == Def.FlightMode.AV then
        for _, keybind in ipairs(DAV.user_setting_table.keybind_table) do
            if key == keybind.key or key == keybind.pad then
                keybind_name = keybind.name
                self:ConvertAVPressAction(keybind_name)
                return
            end
        end
    elseif self.av_obj.engine_obj.flight_mode == Def.FlightMode.Helicopter then
        for _, keybind in ipairs(DAV.user_setting_table.heli_keybind_table) do
            if key == keybind.key or key == keybind.pad then
                keybind_name = keybind.name
                self:ConvertHeliPressAction(keybind_name)
                return
            end
        end
    end
    for _, keybind in ipairs(DAV.user_setting_table.common_keybind_table) do
        if key == keybind.key or key == keybind.pad then
            keybind_name = keybind.name
            self:ConvertCommonPressAction(keybind_name)
            return
        end
    end

end

function Core:ConvertAVPressAction(keybind_name)

    if keybind_name == "move_up" then
        if not self.is_move_up_button_hold_counter then
            self.is_move_up_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.move_up_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_move_up_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_move_up_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.Up)
                end
            end)
        end
    elseif keybind_name == "move_down" then
        if not self.is_move_down_button_hold_counter then
            self.is_move_down_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.move_down_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_move_down_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_move_down_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.Down)
                end
            end)
        end
    elseif keybind_name == "move_left" then
        if not self.is_move_left_button_hold_counter then
            self.is_move_left_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.move_left_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_move_left_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_move_left_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.Left)
                end
            end)
        end
    elseif keybind_name == "move_right" then
        if not self.is_move_right_button_hold_counter then
            self.is_move_right_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.move_right_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_move_right_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_move_right_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.Right)
                end
            end)
        end
    elseif keybind_name == "lean_reset" then
        if not self.is_lean_reset_button_hold_counter then
            self.is_lean_reset_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.lean_reset_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_lean_reset_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_lean_reset_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.LeanReset)
                end
            end)
        end
    end

end

function Core:ConvertHeliPressAction(keybind_name)

    if keybind_name == "ascend" then
        if not self.is_h_ascend_button_hold_counter then
            self.is_h_ascend_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.h_ascend_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_h_ascend_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_h_ascend_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.HUp)
                end
            end)
        end
    elseif keybind_name == "descend" then
        if not self.is_h_descend_button_hold_counter then
            self.is_h_descend_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.h_descend_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_h_descend_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_h_descend_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.HDown)
                end
            end)
        end
    elseif keybind_name == "turn_left" then
        if not self.is_h_turn_left_button_hold_counter then
            self.is_h_turn_left_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.h_turn_left_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_h_turn_left_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_h_turn_left_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.HLeftRotate)
                end
            end)
        end
    elseif keybind_name == "turn_right" then
        if not self.is_h_turn_right_button_hold_counter then
            self.is_h_turn_right_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.h_turn_right_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_h_turn_right_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_h_turn_right_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.HRightRotate)
                end
            end)
        end
    elseif keybind_name == "acceleration" then
        if not self.is_h_acceleration_button_hold_counter then
            self.is_h_acceleration_button_hold_counter = true
            Cron.Every(DAV.time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.h_acceleration_button_hold_count = timer.tick
                if timer.tick >= self.max_move_hold_count then
                    self.is_h_acceleration_button_hold_counter = false
                    Cron.Halt(timer)
                elseif not self.is_h_acceleration_button_hold_counter then
                    Cron.Halt(timer)
                else
                    self.queue_obj:Enqueue(Def.ActionList.HAccelerate)
                end
            end)
        end
    -- elseif keybind_name == "hover" then
    --     self.queue_obj:Enqueue(Def.ActionList.HHover)
    end

end

function Core:ConvertCommonPressAction(keybind_name)

    if keybind_name == "toggle_autopilot" then
        if not self.is_auto_pilot_button_hold_counter then
            self.is_auto_pilot_button_hold_counter = true
            Cron.Every(self.hold_time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.auto_pilot_button_hold_count = timer.tick
                if timer.tick >= self.auto_pilot_hold_complete_time_count then
                    self.is_auto_pilot_button_hold_counter = false
                    self.queue_obj:Enqueue(Def.ActionList.ToggleAutopilot)
                    Cron.Halt(timer)
                elseif not self.is_auto_pilot_button_hold_counter then
                    self.queue_obj:Enqueue(Def.ActionList.OpenAutopilotPanel)
                    Cron.Halt(timer)
                end
            end)
        end
    elseif keybind_name == "toggle_camera" then
        self.queue_obj:Enqueue(Def.ActionList.ChangeCamera)
    elseif keybind_name == "toggle_door" then
        self.queue_obj:Enqueue(Def.ActionList.ChangeDoor1)
    elseif keybind_name == "toggle_radio" then
        if not self.is_radio_button_hold_counter then
            self.is_radio_button_hold_counter = true
            Cron.Every(self.hold_time_resolution, {tick=0}, function(timer)
                timer.tick = timer.tick + 1
                self.radio_button_hold_count = timer.tick
                if timer.tick >= self.radio_hold_complete_time_count then
                    self.is_radio_button_hold_counter = false
                    self.queue_obj:Enqueue(Def.ActionList.OpenRadio)
                    Cron.Halt(timer)
                elseif not self.is_radio_button_hold_counter then
                    self.queue_obj:Enqueue(Def.ActionList.ToggleRadio)
                    Cron.Halt(timer)
                end
            end)
        end
    elseif keybind_name == "toggle_crystal_dome" then
        self.queue_obj:Enqueue(Def.ActionList.ToggleCrystalDome)
    elseif keybind_name == "toggle_appearance" then
        self.queue_obj:Enqueue(Def.ActionList.ToggleAppearance)
    end

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
        elseif self.event_obj:IsWaiting() or self.event_obj:IsTakingOff() then
            self.av_obj:Operate({Def.ActionList.Idle})
        end
    end

end

function Core:SetEvent(action)

    if self.event_obj.current_situation == Def.Situation.Waiting and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        if self.is_locked_action_in_waiting then
            return
        end
        if action == Def.ActionList.Enter then
            self.event_obj:EnterVehicle()
        elseif action == Def.ActionList.SelectUp then
            self.is_locked_action_in_waiting = true
            self.event_obj:SelectChoice(Def.ActionList.SelectUp)
        elseif action == Def.ActionList.SelectDown then
            self.is_locked_action_in_waiting = true
            self.event_obj:SelectChoice(Def.ActionList.SelectDown)
        elseif action == Def.ActionList.ToggleAppearance then
            self:ToggleAppearance()
        end
        Cron.After(self.delay_action_time_in_waiting, function()
            self.is_locked_action_in_waiting = false
        end)
    elseif self.event_obj.current_situation == Def.Situation.InVehicle then
        if self.is_locked_action_in_vehicle then
            return
        end
        if action == Def.ActionList.Exit then
            self:ExitVehicle()
        elseif action == Def.ActionList.ChangeCamera then
            self.is_locked_action_in_vehicle = true
            self:ToggleCamera()
        elseif action == Def.ActionList.ChangeDoor1 then
            self:ToggleDoors()
        elseif action == Def.ActionList.ToggleAutopilot then
            self:ToggleAutopilot()
        elseif action == Def.ActionList.OpenAutopilotPanel then
            self:OpenAutopioltPanel()
        elseif action == Def.ActionList.ToggleRadio then
            self:ToggleRadio()
        elseif action == Def.ActionList.OpenRadio then
            self:OpenRadioPort()
        elseif action == Def.ActionList.ToggleCrystalDome then
            self:ToggleCrystalDome()
        elseif action == Def.ActionList.ToggleAppearance then
            self:ToggleAppearance()
        end
        Cron.After(self.delay_action_time_in_vehicle, function()
            self.is_locked_action_in_vehicle = false
        end)
    end

end

function Core:ExitVehicle()
    if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.event_obj:ExitVehicle()
    end
end

function Core:ToggleAutopilot()
    if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.event_obj:ToggleAutoMode()
    end
end

function Core:OpenAutopioltPanel()
    if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.event_obj.ui_obj:OpenAutopilotPopup()
    end
end

function Core:ToggleCamera()
    if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.av_obj.camera_obj:Toggle()
    end
end

function Core:ToggleDoors()
    if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.event_obj:ChangeDoor()
    end
end

function Core:ToggleCrystalDome()
    if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.av_obj:ToggleCrystalDome()
    end
end

function Core:ToggleAppearance()
    local type_list = self.all_models[DAV.model_index].type
    local type_count = #type_list
    local type_index = DAV.user_setting_table.garage_info_list[DAV.model_index].type_index
    if type_index >= type_count then
        type_index = 1
    else
        type_index = type_index + 1
    end
    self:ChangeGarageAVType(self.all_models[DAV.model_index].tweakdb_id, type_index)
    if not self.event_obj:IsNotSpawned() then
        self.av_obj:ChangeAppearance(type_list[type_index])
    end
end

function Core:SetMappinController()

    ObserveAfter("BaseMappinBaseController", "UpdateRootState", function(this)
        local mappin = this:GetMappin()
        if mappin:GetVariant() == gamedataMappinVariant.CustomPositionVariant then
            self.mappin_controller = this
        end
   end)

end

---@return boolean
function Core:IsCustomMappin()
    return self.is_custom_mappin
end

---@param mappin IMappin 
function Core:SetCustomMappin(mappin)

    local mappin_position = self.current_custom_mappin_position
    if self.event_obj:IsInVehicle() then
        self.log_obj:Record(LogLevel.Info, "Custom Mappin is set")
        local mappin_pos = mappin:GetWorldPosition()
        self.current_custom_mappin_position = mappin_pos
        if Vector4.Distance(mappin_position, mappin_pos) == 0 then
            self.log_obj:Record(LogLevel.Trace, "Same Mappin is selected")
            return
        end
        self.is_custom_mappin = true
        self:SetDestinationMappin()
    end

end

function Core:SetDestinationMappin()
    self.av_obj:SetMappinDestination(self.current_custom_mappin_position)
    self.ft_index_nearest_mappin, self.ft_to_mappin_distance = self:FindNearestFastTravelPosition(self.current_custom_mappin_position)
end

function Core:SetFavoriteMappin(pos)
    local position = Vector4.new(pos.x, pos.y, pos.z, 1)
    -- self.current_custom_mappin_position = position
    if position:IsZero() then
        self.log_obj:Record(LogLevel.Trace, "Invalid Mappin Position")
        return
    end
    self.av_obj:SetFavoriteDestination(position)
    self:CreateFavoriteMappin(position)
    if not self.is_custom_mappin then
        self.ft_index_nearest_favorite, self.ft_to_favorite_distance = self:FindNearestFastTravelPosition(position)
    end
end

---@param position Vector4
function Core:CreateFavoriteMappin(position)

    self:RemoveFavoriteMappin()
    if self.event_obj:IsInVehicle() then
        local mappin_data = MappinData.new()
        mappin_data.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
        mappin_data.variant = gamedataMappinVariant.ExclamationMarkVariant
        mappin_data.visibleThroughWalls = true
        self.dist_mappin_id = Game.GetMappinSystem():RegisterMappin(mappin_data, position)
    end

end

function Core:RemoveFavoriteMappin()

    if self.dist_mappin_id ~= nil then
        Game.GetMappinSystem():UnregisterMappin(self.dist_mappin_id)
        self.dist_mappin_id = nil
    end

end

function Core:SetAutoPilotHistory()

    repeat
        if #DAV.user_setting_table.mappin_history >= self.max_mappin_history then
            table.remove(DAV.user_setting_table.mappin_history)
        end
    until #DAV.user_setting_table.mappin_history < self.max_mappin_history

    local history_info = {}
    history_info.district = self:GetCurrentDistrict()
    if self.is_custom_mappin then
        history_info.location = self:GetNearbyLocation(self.ft_index_nearest_mappin)
        history_info.distance = self:GetFT2MappinDistance()
    else
        history_info.location = self:GetNearbyLocation(self.ft_index_nearest_favorite)
        history_info.distance = self:GetFT2FavoriteDistance()
    end
    history_info.position = {x = self.current_custom_mappin_position.x, y = self.current_custom_mappin_position.y, z = self.current_custom_mappin_position.z}
    table.insert(DAV.user_setting_table.mappin_history, 1, history_info)

    Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)

end

function Core:SetFastTravelPosition()

    self.fast_travel_position_list = {}
    local fast_travel_list = Game.GetScriptableSystemsContainer():Get('FastTravelSystem'):GetFastTravelPoints()

    local mappin_type = gamemappinsMappinTargetType.Map
    local mappin_list = Game.GetMappinSystem():GetMappins(mappin_type)

    for _, fast_travel in ipairs(fast_travel_list) do
        local position_name = GetLocalizedText(fast_travel:GetPointDisplayName())
        local record_id = fast_travel:GetPointRecord()
        local district_list = {}
        local district_record = nil
        local fast_travel_record = TweakDB:GetRecord(record_id)
        if fast_travel_record == nil then
            self.log_obj:Record(LogLevel.Error, "Fast Travel Record is nil")
        else
            district_record = fast_travel_record:District()
        end
        if district_record ~= nil then
            repeat
                table.insert(district_list, 1, GetLocalizedText(district_record:LocalizedName()))
                district_record = district_record:ParentDistrict()
            until district_record == nil
        else
            table.insert(district_list, " ")
        end

        local position = nil
        for index, mappin in ipairs(mappin_list) do
            if mappin.id.value == fast_travel.mappinID.value then
                position = mappin.worldPosition -- Vector4
                table.remove(mappin_list, index)
                break
            end
        end
        if position ~= nil then
            local position_info = {name = position_name, district = district_list, pos = position}
            table.insert(self.fast_travel_position_list, position_info)
        end
    end

end

---@return number
function Core:GetFTIndexNearbyMappin()
    return self.ft_index_nearest_mappin
end

---@return number
function Core:GetFTIndexNearbyFavorite()
    return self.ft_index_nearest_favorite
end

---@param current_pos Vector4
---@return number, number
function Core:FindNearestFastTravelPosition(current_pos)

    local ft_index = 1
    local ft_distance = self.huge_distance
    for index, position_info in ipairs(self.fast_travel_position_list) do
        local distance = Vector4.Distance(current_pos, position_info.pos)
        if distance < ft_distance then
            ft_distance = distance
            ft_index = index
        end
    end
    return ft_index, ft_distance

end

---@param index number
---@return table | nil
function Core:GetNearbyDistrictList(index)

    if self.fast_travel_position_list[index] == nil then
        return nil
    else
        return self.fast_travel_position_list[index].district
    end

end

---@param index number
---@return string | nil
function Core:GetNearbyLocation(index)

    if self.fast_travel_position_list[index] == nil then
        return nil
    else
        return self.fast_travel_position_list[index].name
    end

end

---@return number
function Core:GetFT2MappinDistance()
    return self.ft_to_mappin_distance
end

---@return number
function Core:GetFT2FavoriteDistance()
    return self.ft_to_favorite_distance
end

---@return table
function Core:GetCurrentDistrict()

    local current_district_list = {}
    local district_manager = Game.GetScriptableSystemsContainer():Get('PreventionSystem').districtManager
    local district = district_manager:GetCurrentDistrict()
    if district == nil then
        return current_district_list
    end
    local district_record = district:GetDistrictRecord()
    if district_record ~= nil then
        repeat
            table.insert(current_district_list, 1, GetLocalizedText(district_record:LocalizedName()))
            district_record = district_record:ParentDistrict()
        until district_record == nil
    end
    return current_district_list

end

function Core:ToggleRadio()
    if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.av_obj:ToggleRadio()
    end
end

function Core:OpenRadioPort()
    if self.event_obj:IsInVehicle() and not self.event_obj:IsInMenuOrPopupOrPhoto() then
        self.event_obj:ShowRadioPopup()
    end
end

return Core