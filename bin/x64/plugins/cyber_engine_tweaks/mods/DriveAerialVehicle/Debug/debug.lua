local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Debug = {}
Debug.__index = Debug

function Debug:New(core_obj)
    local obj = {}
    obj.core_obj = core_obj

    -- set parameters
    obj.is_print_command = false
    obj.is_im_gui_situation = false
    obj.is_im_gui_player_position = false
    obj.is_im_gui_av_position = false
    obj.is_im_gui_heli_info = false
    obj.is_im_gui_spinner_info = false
    obj.is_im_gui_engine_info = false
    obj.is_im_gui_sound_check = false
    obj.is_im_gui_mappin_position = false

    obj.selected_sound = "first"
    return setmetatable(obj, self)
end

function Debug:Init()
    ImGui.SetNextWindowPos(100, 500, ImGuiCond.FirstUseEver) -- set window position x, y
    ImGui.SetNextWindowSize(800, 1000, ImGuiCond.Appearing) -- set window size w, h
    ImGui.Begin("DAV DEBUG WINDOW")
    ImGui.Text("Debug Mode : On")
end

function Debug:End()
    ImGui.End()
end

function Debug:SelectPrint()
    self.is_print_command = ImGui.Checkbox("[Print] Action Command", self.is_print_command)
end

function Debug:ImGuiMain()

    self:Init()
    self:SetLogLevel()
    self:ImGuiSituation()
    self:ImGuiPlayerPosition()
    self:ImGuiAVPosition()
    self:ImGuiHeliInfo()
    self:ImGuiSpinnerInfo()
    self:ImGuiCurrentEngineInfo()
    self:ImGuiSoundCheck()
    self:ImGuiMappinPosition()
    self:ImGuiExcuteFunction()
    self:SelectPrint()

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
        ImGui.Text("F_h: " .. f_h .. ", F_v : " .. f_v .. ", v_x: " .. v_x .. ", v_y: " .. v_y .. ", v_z: " .. v_z)
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

function Debug:ImGuiExcuteFunction()
    if ImGui.Button("Test Function 1",300, 60) then
        print("Excute Test Function 1")
    end
    if ImGui.Button("Test Function 2",300, 60) then
        print("Excute Test Function 2")
    end
    if ImGui.Button("Test Function 3",300, 60) then
        print("Excute Test Function 3")
    end
end

function Debug:PrintActionCommand(action_name, action_type, action_value)
    if self.is_print_command then
        print("Action Name : " .. action_name .. ", Action Type : " .. action_type, ", Action Value : " .. action_value)
    end
end

return Debug
