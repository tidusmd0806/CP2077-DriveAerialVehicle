local Utils = require("Tools/utils.lua")
local Debug = {}
Debug.__index = Debug

function Debug:New(core_obj)
    local obj = {}
    obj.core_obj = core_obj

    -- set parameters
    obj.is_im_gui_situation = false
    obj.is_im_gui_player_position = false
    obj.is_im_gui_av_position = false
    obj.is_im_gui_heli_info = false
    obj.is_im_gui_spinner_info = false
    obj.is_im_gui_engine_info = false
    obj.is_im_gui_sound_check = false
    obj.is_im_gui_mappin_position = false
    obj.is_im_gui_model_type_status = false
    obj.is_im_gui_auto_pilot_status = false
    obj.is_set_observer = false
    obj.is_exist_av_1 = false
    obj.is_exist_av_2 = false
    obj.is_exist_av_3 = false
    obj.is_exist_av_4 = false
    obj.is_exist_av_5 = false

    obj.selected_sound = "first"
    return setmetatable(obj, self)
end

function Debug:ImGuiMain()

    ImGui.SetNextWindowPos(100, 500, ImGuiCond.FirstUseEver) -- set window position x, y
    ImGui.SetNextWindowSize(800, 1000, ImGuiCond.Appearing) -- set window size w, h
    ImGui.Begin("DAV DEBUG WINDOW")
    ImGui.Text("Debug Mode : On")

    self:SetObserver()
    self:SetLogLevel()
    self:SelectPrintDebug()
    self:ImGuiSituation()
    self:ImGuiPlayerPosition()
    self:ImGuiAVPosition()
    self:ImGuiHeliInfo()
    self:ImGuiSpinnerInfo()
    self:ImGuiCurrentEngineInfo()
    self:ImGuiSoundCheck()
    self:ImGuiMappinPosition()
    self:ImGuiModelTypeStatus()
    self:ImGuiAutoPilotStatus()
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
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local absolute_position = Utils:WorldToBodyCoordinates(Game.GetPlayer():GetWorldPosition(), self.core_obj.av_obj.position_obj:GetPosition(), self.core_obj.av_obj.position_obj:GetQuaternion())
        local absolute_position_x = string.format("%.2f", absolute_position.x)
        local absolute_position_y = string.format("%.2f", absolute_position.y)
        local absolute_position_z = string.format("%.2f", absolute_position.z)
        ImGui.Text("[local]X:" .. absolute_position_x .. ", Y:" .. absolute_position_y .. ", Z:" .. absolute_position_z)
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

function Debug:ImGuiMappinPosition()
    self.is_im_gui_mappin_position = ImGui.Checkbox("[ImGui] Custom Mappin Position", self.is_im_gui_mappin_position)
    if self.is_im_gui_mappin_position then
        local x = string.format("%.2f", self.core_obj.current_custom_mappin_position.x)
        local y = string.format("%.2f", self.core_obj.current_custom_mappin_position.y)
        local z = string.format("%.2f", self.core_obj.current_custom_mappin_position.z)
        ImGui.Text("X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
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

function Debug:ImGuiAutoPilotStatus()
    self.is_im_gui_auto_pilot_status = ImGui.Checkbox("[ImGui] Auto Pilot Status", self.is_im_gui_auto_pilot_status)
    if self.is_im_gui_auto_pilot_status then
        if #DAV.core_obj.fast_travel_position_list == 0 then
            return
        end
        local near_ft_name = DAV.core_obj.fast_travel_position_list[DAV.core_obj.fast_travel_position_list_index_nearest_mappin].name
        ImGui.Text("Nearest FT Name : " .. near_ft_name)

        for _, history_info in pairs(DAV.core_obj.mappin_history) do
            for _, district in pairs(history_info.district) do
                ImGui.SameLine()
			    ImGui.Text("Dis" .. district)
            end
            ImGui.Text("Loc" .. history_info.location)
            ImGui.Text("Pos" .. history_info.pos.x .. ", " .. history_info.pos.y .. ", " .. history_info.pos.z)
        end
    end
end

function Debug:ImGuiToggleGarageVehicle()
    if ImGui.Button("av1",60, 30) then
        self.is_exist_av_1 = not self.is_exist_av_1
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.av_rayfield_excalibur_dav_dummy", self.is_exist_av_1, true)
    end
    ImGui.SameLine()
    if ImGui.Button("av2",60, 30) then
        self.is_exist_av_2 = not self.is_exist_av_2
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.av_militech_manticore_dav_dummy", self.is_exist_av_2, true)
    end
    ImGui.SameLine()
    if ImGui.Button("av3",60, 30) then
        self.is_exist_av_3 = not self.is_exist_av_3
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.av_zetatech_atlus_dav_dummy", self.is_exist_av_3, true)
    end
    ImGui.SameLine()
    if ImGui.Button("av4",60, 30) then
        self.is_exist_av_4 = not self.is_exist_av_4
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.av_zetatech_surveyor_dav_dummy", self.is_exist_av_4, true)
    end
    ImGui.SameLine()
    if ImGui.Button("av5",60, 30) then
        self.is_exist_av_5 = not self.is_exist_av_5
        Game.GetVehicleSystem():EnablePlayerVehicle("Vehicle.q000_nomad_border_patrol_heli_dav_dummy", self.is_exist_av_5, true)
    end
end

function Debug:ImGuiExcuteFunction()
    if ImGui.Button("Test Func1",150, 50) then
        print("Excute Test Function 1")
    end
    ImGui.SameLine()
    if ImGui.Button("Test Func2",150, 50) then
        local transform = Game.GetPlayer():GetWorldTransform()
        local pos = Game.GetPlayer():GetWorldPosition()
        pos.z = pos.z + 1.45
        transform:SetPosition(pos)
        local entity_id = exEntitySpawner.Spawn("base\\quest\\main_quests\\prologue\\q000\\entities\\q000_invisible_radio.ent", transform, '')
        Cron.Every(1, {tick = 1} , function(timer)
            self.ent = Game.FindEntityByID(entity_id)
            if self.ent ~= nil then
                self.ps = self.ent:GetDevicePS()
                self.ps.activeStation = 3
                self.ent:PlayGivenStation()
                Cron.Halt(timer)
            end
        end)

        print("Excute Test Function 2")
    end
    ImGui.SameLine()
    if ImGui.Button("Test Func3",150, 50) then
        local index = self.ps:GetActiveStationIndex()
        print(index)
        self.ps:SetActiveStation(index + 1)
        self.ent:PlayGivenStation()

        print("Excute Test Function 3")
    end
end

return Debug
