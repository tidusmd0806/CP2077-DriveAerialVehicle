local Utils = require("Tools/utils.lua")
local Debug = {}
Debug.__index = Debug

function Debug:New(core_obj)
    local obj = {}
    obj.core_obj = core_obj

    -- set parameters
    obj.is_set_observer = false
    obj.is_im_gui_rw_count = false
    obj.is_im_gui_situation = false
    obj.is_im_gui_player_position = false
    obj.is_im_gui_av_position = false
    obj.is_im_gui_heli_info = false
    obj.is_im_gui_spinner_info = false
    obj.is_im_gui_engine_info = false
    obj.is_im_gui_sound_check = false
    obj.selected_sound = "100_call_vehicle"
    obj.is_im_gui_mappin_position = false
    obj.is_im_gui_model_type_status = false
    obj.is_im_gui_auto_pilot_status = false
    obj.is_im_gui_change_auto_setting = false
    obj.is_im_gui_radio_info = false
    obj.is_im_gui_measurement = false
    obj.is_exist_av_1 = false
    obj.is_exist_av_2 = false
    obj.is_exist_av_3 = false
    obj.is_exist_av_4 = false
    obj.is_exist_av_5 = false

    return setmetatable(obj, self)
end

function Debug:ImGuiMain()

    ImGui.Begin("DAV DEBUG WINDOW")
    ImGui.Text("Debug Mode : On")

    self:SetObserver()
    self:SetLogLevel()
    self:SelectPrintDebug()
    self:ImGuiShowRWCount()
    self:ImGuiSituation()
    self:ImGuiPlayerPosition()
    self:ImGuiAVPosition()
    self:ImGuiHeliInfo()
    self:ImGuiSpinnerInfo()
    self:ImGuiCurrentEngineInfo()
    self:ImGuiSoundCheck()
    self:ImGuiModelTypeStatus()
    self:ImGuiMappinPosition()
    self:ImGuiAutoPilotStatus()
    self:ImGuiToggleAutoPilotPanel()
    self:ImGuiChangeAutoPilotSetting()
    self:ImGuiRadioInfo()
    self:ImGuiMeasurement()
    self:ImGuiToggleGarageVehicle()
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

function Debug:ImGuiHeliInfo()
    self.is_im_gui_heli_info = ImGui.Checkbox("[ImGui] Heli Info", self.is_im_gui_heli_info)
    if self.is_im_gui_heli_info then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local f = string.format("%.2f", self.core_obj.av_obj.engine_obj.lift_force)
        local v_x = string.format("%.2f", self.core_obj.av_obj.engine_obj.horizenal_x_speed)
        local v_y = string.format("%.2f", self.core_obj.av_obj.engine_obj.horizenal_y_speed)
        local v_z = string.format("%.2f", self.core_obj.av_obj.engine_obj.vertical_speed)
        ImGui.Text("F: " .. f .. ", v_x: " .. v_x .. ", v_y: " .. v_y .. ", v_z: " .. v_z)
    end
end

function Debug:ImGuiSpinnerInfo()
    self.is_im_gui_spinner_info = ImGui.Checkbox("[ImGui] Spinner Info", self.is_im_gui_spinner_info)
    if self.is_im_gui_spinner_info then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local f_h = string.format("%.2f", self.core_obj.av_obj.engine_obj.spinner_horizenal_force)
        local f_v = string.format("%.2f", self.core_obj.av_obj.engine_obj.spinner_vertical_force)
        local v_x = string.format("%.2f", self.core_obj.av_obj.engine_obj.horizenal_x_speed)
        local v_y = string.format("%.2f", self.core_obj.av_obj.engine_obj.horizenal_y_speed)
        local v_z = string.format("%.2f", self.core_obj.av_obj.engine_obj.vertical_speed)
        local v_angle = string.format("%.2f", self.core_obj.av_obj.engine_obj.spinner_speed_angle * 180 / Pi())
        ImGui.Text("F_h: " .. f_h .. ", F_v : " .. f_v)
        ImGui.Text("v_x: " .. v_x .. ", v_y: " .. v_y .. ", v_z: " .. v_z .. ", v_angle: " .. v_angle)
    end
end

function Debug:ImGuiCurrentEngineInfo()
    self.is_im_gui_engine_info = ImGui.Checkbox("[ImGui] Current Engine Info", self.is_im_gui_engine_info)
    if self.is_im_gui_engine_info then
        local v = string.format("%.2f", self.core_obj.av_obj.engine_obj.current_speed)
        ImGui.Text("Current Power Mode : " .. self.core_obj.av_obj.engine_obj.current_mode .. ", Current Speed : " .. v .. " , Clock: " .. self.core_obj.av_obj.engine_obj.clock)
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

function Debug:ImGuiToggleAutoPilotPanel()
    DAV.core_obj.event_obj.hud_obj.is_forced_autopilot_panel = ImGui.Checkbox("[ImGui] Enable Autopilot Panel", DAV.core_obj.event_obj.hud_obj.is_forced_autopilot_panel)
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

function Debug:ImGuiRadioInfo()
    self.is_im_gui_radio_info = ImGui.Checkbox("[ImGui] Radio Info", self.is_im_gui_radio_info)
    if self.is_im_gui_radio_info then
        local volume = self.core_obj.av_obj.radio_obj:GetVolume()
        local entity_num = #self.core_obj.av_obj.radio_obj.radio_entity_list
        local station_index = self.core_obj.av_obj.radio_obj:GetPlayingStationIndex()
        local station_name = CName("No Play")
        if station_index >= 0 then
            station_name = RadioStationDataProvider.GetStationNameByIndex(station_index)
        end
        local track_name = GetLocalizedText(LocKeyToString(self.core_obj.av_obj.radio_obj:GetTrackName()))
        local is_playing = self.core_obj.av_obj.radio_obj.is_playing
        local is_opened_radio_popup = self.core_obj.is_opened_radio_popup
        local radio_port_index = self.core_obj.current_station_index
        local radio_port_volume = self.core_obj.current_radio_volume
        ImGui.Text("Radio Port Index : " .. radio_port_index .. ", Radio Port Volume : " .. radio_port_volume)
        ImGui.Text("Actual Volume : " .. volume .. ", Entity Num : " .. entity_num)
        ImGui.Text("Actual Station Index : " .. station_index .. ", Station Name : " .. station_name.value)
        ImGui.Text("Track Name : " .. track_name)
        ImGui.Text("Is Playing : " .. tostring(is_playing) .. ", Is Radio Popup : " .. tostring(is_opened_radio_popup))
    end
end

function Debug:ImGuiMeasurement()
    self.is_im_gui_measurement = ImGui.Checkbox("[ImGui] Measurement", self.is_im_gui_measurement)
    if self.is_im_gui_measurement then
        local res_x, res_y = GetDisplayResolution()
        ImGui.SetNextWindowPos((res_x / 2) - 20, (res_y / 2) - 20)
        ImGui.SetNextWindowSize(40, 40)
        ImGui.SetNextWindowSizeConstraints(40, 40, 40, 40)
        ---
        ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 10)
        ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize, 5)
        ---
        ImGui.Begin("Crosshair", ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoCollapse + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoResize)
        ImGui.End()
        ---
        ImGui.PopStyleVar(2)
        ImGui.PopStyleColor(1)
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

function Debug:ImGuiToggleGarageVehicle()
    if ImGui.Button("av1") then
        self.is_exist_av_1 = not self.is_exist_av_1
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.av_rayfield_excalibur_dav_dummy", self.is_exist_av_1, true)
    end
    ImGui.SameLine()
    if ImGui.Button("av2") then
        self.is_exist_av_2 = not self.is_exist_av_2
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.av_militech_manticore_dav_dummy", self.is_exist_av_2, true)
    end
    ImGui.SameLine()
    if ImGui.Button("av3") then
        self.is_exist_av_3 = not self.is_exist_av_3
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.av_zetatech_atlus_dav_dummy", self.is_exist_av_3, true)
    end
    ImGui.SameLine()
    if ImGui.Button("av4") then
        self.is_exist_av_4 = not self.is_exist_av_4
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.av_zetatech_surveyor_dav_dummy", self.is_exist_av_4, true)
    end
    ImGui.SameLine()
    if ImGui.Button("av5") then
        self.is_exist_av_5 = not self.is_exist_av_5
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.q000_nomad_border_patrol_heli_dav_dummy", self.is_exist_av_5, true)
    end
end

function Debug:ImGuiExcuteFunction()
    if ImGui.Button("TF1") then
        self.component:Activate(0, false)
        print("Excute Test Function 1")
    end
    ImGui.SameLine()
    if ImGui.Button("TF2") then
        DAV.core_obj.av_obj.radio_obj:Update(5, "100%")
        print("Excute Test Function 2")
    end
    ImGui.SameLine()
    if ImGui.Button("TF3") then
        GetMountedVehicle(GetPlayer()):ToggleRadioReceiver(false)
        print(GetPlayer():GetPocketRadio():IsActive())
        print(GetPlayer():GetPocketRadio():IsRestricted())
        print("Excute Test Function 3")
    end
    ImGui.SameLine()
    if ImGui.Button("TF4") then
        local player = Game.GetPlayer()
        local ent_id = self.metro_entity:GetEntityID()
        local seat = "Passengers"
        local data = NewObject('handle:gameMountEventData')
        data.isInstant = false
        data.slotName = seat
        data.mountParentEntityId = ent_id


        local slot_id = NewObject('gamemountingMountingSlotId')
        slot_id.id = seat

        local mounting_info = NewObject('gamemountingMountingInfo')
        mounting_info.childId = player:GetEntityID()
        mounting_info.parentId = ent_id
        mounting_info.slotId = slot_id

        local mounting_request = NewObject('handle:gamemountingMountingRequest')
        mounting_request.lowLevelMountingInfo = mounting_info
        mounting_request.mountData = data

        Game.GetMountingFacility():Mount(mounting_request)
        print("Excute Test Function 4")
    end
    ImGui.SameLine()
    if ImGui.Button("TF5") then
        local player = Game.GetPlayer()
        self.metro_entity = GetMountedVehicle(player)
        Game.GetWorkspotSystem():UnmountFromVehicle(self.metro_entity, player, false, Vector4.new(0, 0, 0, 1), Quaternion.new(0, 0, 0, 1), "Passengers")
        print("Excute Test Function 5")
    end
    ImGui.SameLine()
    if ImGui.Button("TF6") then
        local player = Game.GetPlayer()
        Game.GetWorkspotSystem():StopInDevice(player)
        print("Excute Test Function 6")
    end
    if ImGui.Button("TF7") then
        local player = Game.GetPlayer()
        self.metro_entity = GetMountedVehicle(player)
        local ent_id = self.metro_entity:GetEntityID()
        local seat = "Passengers"

        local data = NewObject('handle:gameMountEventData')
        data.isInstant = true
        data.slotName = seat
        data.mountParentEntityId = ent_id
        data.entryAnimName = "forcedTransition"

        local slotID = NewObject('gamemountingMountingSlotId')
        slotID.id = seat

        local mounting_info = NewObject('gamemountingMountingInfo')
        mounting_info.childId = player:GetEntityID()
        mounting_info.parentId = ent_id
        mounting_info.slotId = slotID

        local mount_event = NewObject('handle:gamemountingUnmountingRequest')
        mount_event.lowLevelMountingInfo = mounting_info
        mount_event.mountData = data

		Game.GetMountingFacility():Unmount(mount_event)
        print("Excute Test Function 7")
    end
    ImGui.SameLine()
    if ImGui.Button("TF8") then
        local name = CName.new("ue_metro_next_station")
        Game.GetQuestsSystem():SetFact(name, 1)
        print("Excute Test Function 8")
    end
    ImGui.SameLine()
    if ImGui.Button("TF9") then
        local con = CustomQuestNotificationGameController.new()
        con:OnInitialize()
        con:Setup()
        con:ShowRequest()
        print("Excute Test Function 9")
    end
    ImGui.SameLine()
    if ImGui.Button("TF10") then
        local inkSystem = Game.GetInkSystem()
        local hudRoot = inkSystem:GetLayer("inkHUDLayer"):GetVirtualWindow()

        local hello = inkText.new()
        hello:SetText("HELLO HUD")
        hello:SetFontFamily("base\\gameplay\\gui\\fonts\\orbitron\\orbitron.inkfontfamily")
        hello:SetFontStyle("Bold")
        hello:SetFontSize(50)
        hello:SetTintColor(HDRColor.new(1.1761, 0.3809, 0.3476, 1.0))
        hello:SetAnchor(inkEAnchor.CenterFillHorizontaly)
        hello:SetAnchorPoint(0.5, 0.5)
        hello:Reparent(hudRoot)

        -- local rectangle = inkRectangle.new()
        -- rectangle:SetSize(100, 100)
        -- rectangle:SetAnchor(inkEAnchor.Centered)
        -- rectangle:SetAnchorPoint(0.5, 0.5)
        -- rectangle:Reparent(hudRoot)

        local image = inkImage.new()
        image:SetAtlasResource("base\\gameplay\\gui\\common\\shapes\\atlas_shapes_sync.inkatlas")
        image:SetTexturePart("button_big2_fg")
        image:SetSize(100, 100)
        image:SetAnchor(inkEAnchor.Centered)
        image:SetAnchorPoint(0.5, 0.5)
        image:Reparent(hudRoot)
        print("Excute Test Function 10")
    end
    if ImGui.Button("TF11") then
        self.popup = DAV_AerialVehiclePopupWrapper.new()
        self.popup:Create()
        self.popup:SetTranslation("ui_popup_title","abc")
        self.popup:SetTranslation("ui_popup_destination_title","defあ")
        self.popup:SetTranslation("ui_popup_destination_button","あああ")
        self.popup:SetTranslation("ui_popup_register_confirm_text","でバック")
        self.popup:SetTranslation("ui_popup_register_input_hint","AR3う")
        Cron.After(0.1, function()
            self.popup:Show(self.core_obj.event_obj.ui_obj.ui_game_menu_controller)
            local arr = {}
            for i = 1, 5 do
                table.insert(arr, DAV.user_setting_table.favorite_location_list[i].name)
            end
            Cron.After(0.1, function()
                self.popup:SetDestination("Test Destination fsa", "aaa", 2)
                self.popup:SetFavoriteList(arr)
                self.popup:SetCurrentAddress("Test Address wwa")
            end)
        end)
        print("Excute Test Function 11")
    end
    ImGui.SameLine()
    if ImGui.Button("TF12") then
        if self.popup:IsClosed() then
            local num = self.popup:GetSelectedNumber()
            print(num)
            local arr = self.popup:GetFavoriteList()
            for i = 1, #arr do
                print(arr[i])
            end
        end
        print("Excute Test Function 12")
    end
    ImGui.SameLine()
    if ImGui.Button("TF13") then
        DAV.core_obj.event_obj.ui_obj:OpenAutopilotPopup()
        print("Excute Test Function 13")
    end
    ImGui.SameLine()
    if ImGui.Button("TF14") then
        print("Excute Test Function 14")
    end
end

return Debug
