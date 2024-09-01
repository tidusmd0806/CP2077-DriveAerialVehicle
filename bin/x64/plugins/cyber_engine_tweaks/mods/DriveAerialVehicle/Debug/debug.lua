local Utils = require("Tools/utils.lua")
local Debug = {}
Debug.__index = Debug

function Debug:New(core_obj)
    local obj = {}
    obj.core_obj = core_obj

    -- set parameters
    obj.is_set_observer = false
    obj.is_im_gui_rw_count = false
    obj.is_im_gui_input_check = false
    obj.is_im_gui_situation = false
    obj.is_im_gui_player_position = false
    obj.is_im_gui_av_position = false
    obj.is_im_gui_vehicle_info = false
    obj.is_im_gui_sound_check = false
    obj.selected_sound = "100_call_vehicle"
    obj.is_im_gui_mappin_position = false
    obj.is_im_gui_model_type_status = false
    obj.is_im_gui_auto_pilot_status = false
    obj.is_im_gui_change_auto_setting = false
    obj.is_im_gui_measurement = false

    return setmetatable(obj, self)
end

function Debug:ImGuiMain()

    ImGui.Begin("DAV DEBUG WINDOW")
    ImGui.Text("Debug Mode : On")

    self:SetObserver()
    self:SetLogLevel()
    self:SelectPrintDebug()
    self:ImGuiShowRWCount()
    self:ImGuiInputCheck()
    self:ImGuiSituation()
    self:ImGuiPlayerPosition()
    self:ImGuiAVPosition()
    self:ImGuiVehicleInfo()
    self:ImGuiSoundCheck()
    self:ImGuiModelTypeStatus()
    self:ImGuiMappinPosition()
    self:ImGuiAutoPilotStatus()
    self:ImGuiChangeAutoPilotSetting()
    self:ImGuiMeasurement()
    self:ImGuiExcuteFunction()

    ImGui.End()

end

function Debug:SetObserver()

    if not self.is_set_observer then
        -- reserved
    end
    self.is_set_observer = true

    if self.is_set_observer then
        ImGui.SameLine()
        ImGui.Text("Observer : On")
    end

end

function Debug:SetLogLevel()
    local selected = false
    if ImGui.BeginCombo("LogLevel", Utils:GetKeyFromValue(LogLevel, MasterLogLevel)) then
		for _, key in ipairs(Utils:GetKeys(LogLevel)) do
			if Utils:GetKeyFromValue(LogLevel, MasterLogLevel) == key then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable(key, selected)) then
				MasterLogLevel = LogLevel[key]
			end
		end
		ImGui.EndCombo()
	end
end

function Debug:SelectPrintDebug()
    PrintDebugMode = ImGui.Checkbox("Print Debug Mode", PrintDebugMode)
end

function Debug:ImGuiShowRWCount()
    self.is_im_gui_rw_count = ImGui.Checkbox("[ImGui] R/W Count", self.is_im_gui_rw_count)
    if self.is_im_gui_rw_count then
        ImGui.Text("Read : " .. READ_COUNT .. ", Write : " .. WRITE_COUNT)
    end
end

function Debug:ImGuiInputCheck()
    self.is_im_gui_input_check = ImGui.Checkbox("[ImGui] Input Check", self.is_im_gui_input_check)
    if self.is_im_gui_input_check then
        if DAV.is_keyboard_input then
            ImGui.Text("Keyboard : On")
        else
            ImGui.Text("Keyboard : Off")
        end
    end
end

function Debug:ImGuiSituation()
    self.is_im_gui_situation = ImGui.Checkbox("[ImGui] Current Situation", self.is_im_gui_situation)
    if self.is_im_gui_situation then
        ImGui.Text("Current Situation : " .. self.core_obj.event_obj.current_situation)
    end
end

function Debug:ImGuiPlayerPosition()
    self.is_im_gui_player_position = ImGui.Checkbox("[ImGui] Player Position Angle", self.is_im_gui_player_position)
    if self.is_im_gui_player_position then
        local x = string.format("%.2f", Game.GetPlayer():GetWorldPosition().x)
        local y = string.format("%.2f", Game.GetPlayer():GetWorldPosition().y)
        local z = string.format("%.2f", Game.GetPlayer():GetWorldPosition().z)
        ImGui.Text("[world]X:" .. x .. ", Y:" .. y .. ", Z:" .. z)
        local roll = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().roll)
        local pitch = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().pitch)
        local yaw = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().yaw)
        ImGui.Text("[world]Roll:" .. roll .. ", Pitch:" .. pitch .. ", Yaw:" .. yaw)
    end
end

function Debug:ImGuiAVPosition()
    self.is_im_gui_av_position = ImGui.Checkbox("[ImGui] AV Position Angle", self.is_im_gui_av_position)
    if self.is_im_gui_av_position then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local x = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().x)
        local y = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().y)
        local z = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().z)
        local roll = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().roll)
        local pitch = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().pitch)
        local yaw = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().yaw)
        ImGui.Text("X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
        ImGui.Text("Roll:" .. roll .. ", Pitch:" .. pitch .. ", Yaw:" .. yaw)
    end
end

function Debug:ImGuiVehicleInfo()
    self.is_im_gui_vehicle_info = ImGui.Checkbox("[ImGui] Vehicle Info", self.is_im_gui_vehicle_info)
    if self.is_im_gui_vehicle_info then
        if DAV.core_obj.av_obj:IsDestroyed() then
            ImGui.Text("Vehicle : Destroyed")
        else
            ImGui.Text("Vehicle : Alive")
        end
        local left_door_state = DAV.core_obj.av_obj:GetDoorState(EVehicleDoor.seat_front_left)
        local right_door_state = DAV.core_obj.av_obj:GetDoorState(EVehicleDoor.seat_front_right)
        ImGui.Text("Left Door : ")
        ImGui.SameLine()
        ImGui.Text(tostring(left_door_state))
        ImGui.Text("Right Door : ")
        ImGui.SameLine()
        ImGui.Text(tostring(right_door_state))
        if DAV.core_obj.av_obj.engine_obj.fly_av_system:IsOnGround() then
            ImGui.Text("On Ground")
        else
            ImGui.Text("In Air")
        end
        ImGui.Text("Phy State: " .. tostring(DAV.core_obj.av_obj.engine_obj.fly_av_system:GetPhysicsState()))

    end
end

function Debug:ImGuiSoundCheck()
    self.is_im_gui_sound_check = ImGui.Checkbox("[ImGui] Sound Check", self.is_im_gui_sound_check)
    if self.is_im_gui_sound_check then
        if ImGui.BeginCombo("##Sound List", self.selected_sound) then
            for key, _ in pairs(self.core_obj.event_obj.sound_obj.sound_data) do
                if (ImGui.Selectable(key, (self.selected_sound==key))) then
                    self.selected_sound = key
                end
            end
            ImGui.EndCombo()
        end

        if ImGui.Button("Play", 150, 60) then
            self.core_obj.event_obj.sound_obj:PlaySound(self.selected_sound)
        end

        if ImGui.Button("Stop", 150, 60) then
            self.core_obj.event_obj.sound_obj:StopSound(self.selected_sound)
        end
    end
end

function Debug:ImGuiModelTypeStatus()
    self.is_im_gui_model_type_status = ImGui.Checkbox("[ImGui] Model Index Status", self.is_im_gui_model_type_status)
    if self.is_im_gui_model_type_status then
        local model_index = DAV.model_index
        local model_type_index = DAV.model_type_index
        ImGui.Text("Model Index : " .. model_index .. ", Model Type Index : " .. model_type_index)
        local garage_info_list = DAV.user_setting_table.garage_info_list
        for _, value in pairs(garage_info_list) do
            ImGui.Text("name : " .. value.name .. ", model_index : " .. value.model_index .. ", model_type_index : " .. value.type_index .. ", is_unlocked : " .. tostring(value.is_purchased))
        end
    end
end

function Debug:ImGuiMappinPosition()
    self.is_im_gui_mappin_position = ImGui.Checkbox("[ImGui] Custom Mappin Position", self.is_im_gui_mappin_position)
    if self.is_im_gui_mappin_position then
        local x = string.format("%.2f", self.core_obj.current_custom_mappin_position.x)
        local y = string.format("%.2f", self.core_obj.current_custom_mappin_position.y)
        local z = string.format("%.2f", self.core_obj.current_custom_mappin_position.z)
        ImGui.Text("X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
        if DAV.core_obj.is_custom_mappin then
            ImGui.Text("Custom Mappin : On")
        else
            ImGui.Text("Custom Mappin : Off")
        end
    end
end

function Debug:ImGuiAutoPilotStatus()
    self.is_im_gui_auto_pilot_status = ImGui.Checkbox("[ImGui] Auto Pilot Status", self.is_im_gui_auto_pilot_status)
    if self.is_im_gui_auto_pilot_status then
        ImGui.Text("FT Index near mappin : " .. tostring(DAV.core_obj.ft_index_nearest_mappin))
        ImGui.Text("FT Index near favorite : " .. tostring(DAV.core_obj.ft_index_nearest_favorite))
        local selected_history_index = DAV.core_obj.event_obj.ui_obj.selected_auto_pilot_history_index
        ImGui.Text("Selected History Index : " .. selected_history_index)
        ImGui.Text("-----History-----")
        local mappin_history = DAV.user_setting_table.mappin_history
        if #mappin_history ~= 0 then
            for i, value in ipairs(mappin_history) do
                ImGui.Text("[" .. i .. "] : " .. value.district[1])
                ImGui.SameLine()
                ImGui.Text("/ " .. value.location)
                ImGui.SameLine()
                ImGui.Text("/ " .. value.distance)
                if value.position ~= nil then
                    ImGui.Text("[" .. i .. "] : " .. value.position.x .. ", " .. value.position.y .. ", " .. value.position.z)
                else
                    ImGui.Text("[" .. i .. "] : nil")
                end
            end
        else
            ImGui.Text("No History")
        end
        local selected_favorite_index = DAV.core_obj.event_obj.ui_obj.selected_auto_pilot_favorite_index
        ImGui.Text("Selected Favorite Index : " .. selected_favorite_index)
        ImGui.Text("------Favorite Location------")
        local favorite_location_list = DAV.user_setting_table.favorite_location_list
        for i, value in ipairs(favorite_location_list) do
            ImGui.Text("[" .. i .. "] : " .. value.name)
            if value.pos ~= nil then
                ImGui.Text("[" .. i .. "] : " .. value.pos.x .. ", " .. value.pos.y .. ", " .. value.pos.z)
            else
                ImGui.Text("[" .. i .. "] : nil")
            end
        end
    end
end

function Debug:ImGuiChangeAutoPilotSetting()
    self.is_im_gui_change_auto_setting = ImGui.Checkbox("[ImGui] Change AP Profile", self.is_im_gui_change_auto_setting)
    if self.is_im_gui_change_auto_setting then
        if ImGui.Button("Update Profile") then
            local autopilot_profile = Utils:ReadJson(DAV.core_obj.av_obj.profile_path)
            local speed_level = DAV.user_setting_table.autopilot_speed_level
            DAV.core_obj.av_obj.auto_pilot_speed = autopilot_profile[speed_level].speed
            DAV.core_obj.av_obj.avoidance_range = autopilot_profile[speed_level].avoidance_range
            DAV.core_obj.av_obj.max_avoidance_speed = autopilot_profile[speed_level].max_avoidance_speed
            DAV.core_obj.av_obj.sensing_constant = autopilot_profile[speed_level].sensing_constant
            DAV.core_obj.av_obj.autopilot_turn_speed = autopilot_profile[speed_level].turn_speed
            DAV.core_obj.av_obj.autopilot_land_offset = autopilot_profile[speed_level].land_offset
            DAV.core_obj.av_obj.autopilot_down_time_count = autopilot_profile[speed_level].down_time_count
            DAV.core_obj.av_obj.autopilot_leaving_height = autopilot_profile[speed_level].leaving_hight
            DAV.core_obj.av_obj.position_obj:SetSensorPairVectorNum(autopilot_profile[speed_level].sensor_pair_vector_num)
            DAV.core_obj.av_obj.position_obj:SetJudgedStackLength(autopilot_profile[speed_level].judged_stack_length)
        end
        ImGui.Text("Speed Level : " .. DAV.user_setting_table.autopilot_speed_level)
        ImGui.Text("speed : " .. DAV.core_obj.av_obj.auto_pilot_speed .. ", avoidance : " .. DAV.core_obj.av_obj.avoidance_range .. ", max_avoidance : " .. DAV.core_obj.av_obj.max_avoidance_speed .. ", sensing : " .. DAV.core_obj.av_obj.sensing_constant .. ", stack_len : " .. DAV.core_obj.av_obj.position_obj.judged_stack_length)
        ImGui.Text("turn : " .. DAV.core_obj.av_obj.autopilot_turn_speed .. ", land : " .. DAV.core_obj.av_obj.autopilot_land_offset .. ", down_t : " .. DAV.core_obj.av_obj.autopilot_down_time_count .. ", height : " .. DAV.core_obj.av_obj.autopilot_leaving_height .. ", sensor_num : " .. DAV.core_obj.av_obj.position_obj.sensor_pair_vector_num)
    end
end

function Debug:ImGuiMeasurement()
    self.is_im_gui_measurement = ImGui.Checkbox("[ImGui] Measurement", self.is_im_gui_measurement)
    if self.is_im_gui_measurement then
        local look_at_pos = Game.GetTargetingSystem():GetLookAtPosition(Game.GetPlayer())
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local origin = self.core_obj.av_obj.position_obj:GetPosition()
        local right = self.core_obj.av_obj.position_obj.entity:GetWorldRight()
        local forward = self.core_obj.av_obj.position_obj.entity:GetWorldForward()
        local up = self.core_obj.av_obj.position_obj.entity:GetWorldUp()
        local relative = Vector4.new(look_at_pos.x - origin.x, look_at_pos.y - origin.y, look_at_pos.z - origin.z, 1)
        local x = Vector4.Dot(relative, right)
        local y = Vector4.Dot(relative, forward)
        local z = Vector4.Dot(relative, up)
        local absolute_position_x = string.format("%.2f", x)
        local absolute_position_y = string.format("%.2f", y)
        local absolute_position_z = string.format("%.2f", z)
        ImGui.Text("[LookAt]X:" .. absolute_position_x .. ", Y:" .. absolute_position_y .. ", Z:" .. absolute_position_z) 
    end
end

function Debug:ImGuiExcuteFunction()
    if ImGui.Button("TF1") then
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local comp = entity:FindComponentByName("AnimationController")
        local feat = AnimFeature_PartData.new()
        feat.duration = 1
        feat.state = 1
        -- AnimationControllerComponent.ApplyFeatureToReplicate(Game.GetPlayer():GetMountedVehicle(), CName.new("seat_front_left"), feat)
        AnimationControllerComponent.ApplyFeatureToReplicate(entity, CName.new("trunk"), feat)
        print("Excute Test Function 1")
    end
    ImGui.SameLine()
    if ImGui.Button("TF1-2") then
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local comp = entity:FindComponentByName("AnimationController")
        local feat = AnimFeature_PartData.new()
        feat.duration = 1
        feat.state = 3
        -- AnimationControllerComponent.ApplyFeatureToReplicate(Game.GetPlayer():GetMountedVehicle(), CName.new("seat_front_left"), feat)
        AnimationControllerComponent.ApplyFeatureToReplicate(entity, CName.new("trunk"), feat)
        print("Excute Test Function 1-2")
    end
    ImGui.SameLine()
    if ImGui.Button("TF2") then
        local depot = Game.GetResourceDepot()
        local token = depot:LoadResource("base\\sound\\metadata\\cooked_metadata.audio_metadata")
        local meta_data = token:GetResource()
        local basilisk_data
        local aerondight_data
        for _, value in pairs(meta_data.entries) do
            if value.name.value == "v_av_basilisk_tank" then
                basilisk_data = value
                -- value.collisionCooldown = 0.5 -- 0.2
                -- value.hasRadioReceiver = true -- false
                -- value.radioReceiverType = CName.new("radio_car_hyper_player")
                -- value.vehicleCollisionSettings = CName.new("v_car_default_collision") -- v_military_panzer_collision
                -- value.vehicleGridDestructionSettings = CName.new("v_grid_dst_car_default") -- None
                -- value.vehiclePartSettings = CName.new("v_car_damage_default") -- None
                -- -- local mechanical_data = audioVehicleMechanicalData.new()
                -- -- mechanical_data = value.mechanicalData
                -- -- mechanical_data.engineStartEvent = CName.new("v_car_rayfield_aerondight_engine_on")
                -- -- mechanical_data.engineStopEvent = CName.new("v_car_rayfield_aerondight_engine_off")
                -- -- value.mechanicalData = mechanical_data
                -- local general_data = audioVehicleGeneralData.new()
                -- general_data = value.generalData
                -- general_data.enterVehicleEvent = CName.new("v_car_rayfield_aerondight_enter") -- v_av_panzer_01_enter
                -- general_data.exitVehicleEvent = CName.new("v_car_rayfield_aerondight_exit") -- None
                -- value.generalData = general_data
            end
            if value.name.value == "v_car_rayfield_aerondight" then
                aerondight_data = value
            end
        end
        basilisk_data.collisionCooldown = 0.5 -- 0.2
        basilisk_data.hasRadioReceiver = true -- false
        basilisk_data.radioReceiverType = CName.new("radio_car_hyper_player")
        basilisk_data.vehicleCollisionSettings = CName.new("v_car_default_collision") -- v_military_panzer_collision
        basilisk_data.vehicleGridDestructionSettings = CName.new("v_grid_dst_car_default") -- None
        basilisk_data.vehiclePartSettings = CName.new("v_car_damage_default") -- None
        -- local mechanical_data = audioVehicleMechanicalData.new()
        -- mechanical_data = value.mechanicalData
        -- mechanical_data.engineStartEvent = CName.new("v_car_rayfield_aerondight_engine_on")
        -- mechanical_data.engineStopEvent = CName.new("v_car_rayfield_aerondight_engine_off")
        -- value.mechanicalData = mechanical_data
        -- local general_data = audioVehicleGeneralData.new()
        basilisk_data.generalData = aerondight_data.generalData
        print("Excute Test Function 2")
    end
    ImGui.SameLine()
    if ImGui.Button("TF3") then
        local depot = Game.GetResourceDepot()
        local token = depot:LoadResource("base\\sound\\metadata\\cooked_metadata.audio_metadata")
        local meta_data = token:GetResource()
        for _, value in pairs(meta_data.entries) do
            if value.name.value == "v_av_basilisk_tank" then
                print("Collision Cooldown : " .. value.collisionCooldown)
                print("Has Radio Receiver : " .. tostring(value.hasRadioReceiver))
                print("Radio Receiver Type : " .. value.radioReceiverType.value)
                print("Vehicle Collision Settings : " .. value.vehicleCollisionSettings.value)
                print("Vehicle Grid Destruction Settings : " .. value.vehicleGridDestructionSettings.value)
                print("Vehicle Part Settings : " .. value.vehiclePartSettings.value)
                print("Acelleration : " .. value.mechanicalData.acelleration.value)
                print("Enter Event : " .. value.generalData.enterVehicleEvent.value)
                print("Exit Event : " .. value.generalData.exitVehicleEvent.value)
            end
        end
        print("Excute Test Function 3")
    end
    ImGui.SameLine()
    if ImGui.Button("TF4") then
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local comp = entity:FindComponentByName("LandingVFXSlot")
        local player_pos = Game.GetPlayer():GetWorldPosition()
        comp:SetLocalPosition(Vector4.new(0,0,5,1))
        Cron.After(3, function()
            comp:SetLocalPosition(Vector4.new(0,0,4,1))
        end)
        Cron.After(6, function()
            comp:SetLocalPosition(Vector4.new(0,0,3,1))
        end)
        local effect_name = CName.new("landingWarning")
        GameObjectEffectHelper.StartEffectEvent(entity, effect_name, false)
        print("Excute Test Function 4")
    end
    ImGui.SameLine()
    if ImGui.Button("TF4-1") then
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local effect_name = CName.new("landingWarning")
        GameObjectEffectHelper.StopEffectEvent(entity, effect_name)
        print("Excute Test Function 4-1")
    end
    ImGui.SameLine()
    if ImGui.Button("TF4-2") then
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local comp = entity:FindComponentByName("LandingVFXSlot")
        local player_pos = Game.GetPlayer():GetWorldPosition()
        comp:SetLocalPosition(Vector4.new(0,0,1,1))
        local effect_name = CName.new("landingWarning")
        GameObjectEffectHelper.StartEffectEvent(entity, effect_name, false)
        print("Excute Test Function 4-2")
    end
    ImGui.SameLine()
    if ImGui.Button("TF5") then
        local door_event = VehicleDoorOpen.new()
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local vehicle_ps = entity:GetVehiclePS()
        door_event.slotID = CName.new("seat_front_right")
        door_event.forceScene = false
        vehicle_ps:QueuePSEvent(vehicle_ps, door_event)
        print("Excute Test Function 5")
    end
    ImGui.SameLine()
    if ImGui.Button("TF6") then
        DAV.core_obj.av_obj.engine_obj.fly_av_system:SetPhysicsState(16)
        print("Excute Test Function 6")
    end
end

return Debug
