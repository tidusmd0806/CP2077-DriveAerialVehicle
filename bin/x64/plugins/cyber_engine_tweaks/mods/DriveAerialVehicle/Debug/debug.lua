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
    obj.is_im_gui_auto_pilot_info = false
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
    self:ImGuiAutoPilotInfo()
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
        ImGui.Text("Height : " .. tostring(DAV.core_obj.av_obj.position_obj:GetHeight()))
    end
end

function Debug:ImGuiVehicleInfo()
    self.is_im_gui_vehicle_info = ImGui.Checkbox("[ImGui] Vehicle Info", self.is_im_gui_vehicle_info)
    if self.is_im_gui_vehicle_info then
        if DAV.core_obj.av_obj == nil then
            return
        end
        if DAV.core_obj.av_obj:IsDestroyed() then
            ImGui.Text("Vehicle : Destroyed")
        else
            ImGui.Text("Vehicle : Alive")
        end
        local left_door_state = DAV.core_obj.av_obj:GetDoorState(EVehicleDoor.seat_front_left)
        local right_door_state = DAV.core_obj.av_obj:GetDoorState(EVehicleDoor.seat_front_right)
        ImGui.Text("Door State : " .. tostring(left_door_state) .. ", ")
        ImGui.Text(tostring(right_door_state))
        local lock_list = DAV.core_obj.av_obj.door_input_lock_list
        ImGui.Text("Door Input Lock : " .. tostring(lock_list["seat_front_left"]) .. ", " .. tostring(lock_list["seat_front_right"]))
        if DAV.core_obj.av_obj.engine_obj.fly_av_system == nil then
            return
        end
        if DAV.core_obj.av_obj.engine_obj.fly_av_system:IsOnGround() then
            ImGui.Text("On Ground")
        else
            ImGui.Text("In Air")
        end
        ImGui.Text("Phy State: " .. tostring(DAV.core_obj.av_obj.engine_obj.fly_av_system:GetPhysicsState()))
        if DAV.core_obj.av_obj.engine_obj.fly_av_system:HasGravity() then
            ImGui.Text("Gravity : On")
        else
            ImGui.Text("Gravity : Off")
        end
        local speed = DAV.core_obj.av_obj.engine_obj.fly_av_system:GetVelocity()
        local speed_x = string.format("%.2f", speed.x)
        local speed_y = string.format("%.2f", speed.y)
        local speed_z = string.format("%.2f", speed.z)
        ImGui.Text("Speed : X:" .. speed_x .. ", Y:" .. speed_y .. ", Z:" .. speed_z)

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
            DAV.core_obj.av_obj.autopilot_profile = Utils:ReadJson(DAV.core_obj.av_obj.profile_path)
            DAV.core_obj.av_obj:ReloadAutopilotProfile()
        end
        ImGui.Text("Speed Level : " .. DAV.user_setting_table.autopilot_speed_level)
        ImGui.Text("speed : " .. DAV.core_obj.av_obj.auto_pilot_speed .. ", searching_range : " .. DAV.core_obj.av_obj.searching_range .. ", searching_step : " .. DAV.core_obj.av_obj.searching_step)
    end
end

function Debug:ImGuiAutoPilotInfo()
    self.is_im_gui_auto_pilot_info = ImGui.Checkbox("[ImGui] Auto Pilot Info", self.is_im_gui_auto_pilot_info)
    if self.is_im_gui_auto_pilot_info then
        ImGui.Text("Angle : " .. tostring(DAV.core_obj.av_obj.autopilot_angle))
        ImGui.Text("hotizontal : " .. tostring(DAV.core_obj.av_obj.autopilot_horizontal_sign))
        ImGui.Text("vertical : " .. tostring(DAV.core_obj.av_obj.autopilot_vertical_sign))
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
    if ImGui.Button("TF2") then
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local comp = entity:FindComponentByName("ThrusterLight_FrontLeft1617")
        local evt = ToggleLightEvent.new()
        evt.toggle = false
        comp:OnToggleLight(evt)
        print("Excute Test Function 2")
    end
    ImGui.SameLine()
    if ImGui.Button("TF3") then
        local depot = Game.GetResourceDepot()
        local token = depot:LoadResource("base\\sound\\metadata\\cooked_metadata.audio_metadata")
        local meta_data = token:GetResource()
        for _, value in pairs(meta_data.entries) do
            if value.name.value == "v_heli_q000_border_heli" then
                local settings = audioCommonEntitySettings.new()
                settings.onAttachEvent = CName.new("q000_nomad_sc_04_heli")
                settings.onDetachEvent = CName.new("q000_nomad_sc_04_heli_stop")
                settings.stopAllSoundsOnDetach = true
                value.commonSettings = settings
            end
        end
        print("Excute Test Function 3")
    end
    ImGui.SameLine()
    if ImGui.Button("TF4") then
        DAV.core_obj.event_obj.hud_obj.is_manually_setting_speed = true
        DAV.core_obj.event_obj.hud_obj.is_manually_setting_rpm = true
        inkTextRef.SetText(DAV.core_obj.event_obj.hud_obj.hud_car_controller.SpeedValue, 101)
        DAV.core_obj.event_obj.hud_obj.hud_car_controller:EvaluateRPMMeterWidget(7)
        print("Excute Test Function 4")
    end
    ImGui.SameLine()
    if ImGui.Button("TF5") then
        DAV.core_obj.event_obj.hud_obj.is_manually_setting_speed = false
        DAV.core_obj.event_obj.hud_obj.is_manually_setting_rpm = false
        print("Excute Test Function 5")
    end
end

return Debug
