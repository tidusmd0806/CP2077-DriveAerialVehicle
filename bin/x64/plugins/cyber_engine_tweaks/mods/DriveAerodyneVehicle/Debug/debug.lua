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
    obj.is_im_gui_player_angle = false
    obj.is_im_gui_av_position = false
    obj.is_im_gui_av_angle = false
    obj.is_im_gui_lift_force = false
    return setmetatable(obj, self)
end

function Debug:Init()
    ImGui.SetNextWindowPos(100, 500, ImGuiCond.FirstUseEver) -- set window position x, y
    ImGui.SetNextWindowSize(800, 1000, ImGuiCond.Appearing) -- set window size w, h
    ImGui.Begin("RAV DEBUG WINDOW")
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
    self:SelectPrint()
    self:ImGuiSituation()
    self:ImGuiPlayerPosition()
    self:ImGuiPlayerAngle()
    self:ImGuiAVPosition()
    self:ImGuiAVAngle()
    self:ImGuiLiftForceAndSpped()
end

function Debug:ImGuiSituation()
    self.is_im_gui_situation = ImGui.Checkbox("[ImGui] Current Situation", self.is_im_gui_situation)
    if self.is_im_gui_situation then
        ImGui.Text("Current Situation : " .. self.core_obj.event_obj.current_situation)
    end
end

function Debug:ImGuiPlayerPosition()
    self.is_im_gui_player_position = ImGui.Checkbox("[ImGui] Player Position", self.is_im_gui_player_position)
    if self.is_im_gui_player_position then
        ImGui.Text("Player X:" .. Game.GetPlayer():GetWorldPosition().x .. ", Y:" .. Game.GetPlayer():GetWorldPosition().y .. ", Z:" .. Game.GetPlayer():GetWorldPosition().z)
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local absolute_position = Utils:WorldToBodyCoordinates(Game.GetPlayer():GetWorldPosition(), self.core_obj.av_obj.position_obj:GetPosition(), self.core_obj.av_obj.position_obj:GetQuaternion())
        ImGui.Text("Player IN AV X" .. absolute_position.x .. ", Y:" .. absolute_position.y .. ", Z:" .. absolute_position.z)
    end
end

function Debug:ImGuiPlayerAngle()
    self.is_im_gui_player_angle = ImGui.Checkbox("[ImGui] Player Angle", self.is_im_gui_player_angle)
    if self.is_im_gui_player_angle then
        ImGui.Text("Player Roll:" .. Game.GetPlayer():GetWorldOrientation():ToEulerAngles().roll .. ", Pitch:" .. Game.GetPlayer():GetWorldOrientation():ToEulerAngles().pitch .. ", Yaw:" .. Game.GetPlayer():GetWorldOrientation():ToEulerAngles().yaw)
    end
end

function Debug:ImGuiAVPosition()
    self.is_im_gui_av_position = ImGui.Checkbox("[ImGui] AV Position", self.is_im_gui_av_position)
    if self.is_im_gui_av_position then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        ImGui.Text("AV X:" .. self.core_obj.av_obj.position_obj:GetPosition().x .. ", Y:" .. self.core_obj.av_obj.position_obj:GetPosition().y .. ", Z:" .. self.core_obj.av_obj.position_obj:GetPosition().z)
    end
end

function Debug:ImGuiAVAngle()
    self.is_im_gui_av_angle = ImGui.Checkbox("[ImGui] AV Angle", self.is_im_gui_av_angle)
    if self.is_im_gui_av_angle then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        ImGui.Text("AV Roll:" .. self.core_obj.av_obj.position_obj:GetEulerAngles().roll .. ", Pitch:" .. self.core_obj.av_obj.position_obj:GetEulerAngles().pitch .. ", Yaw:" .. self.core_obj.av_obj.position_obj:GetEulerAngles().yaw)
    end
end

function Debug:ImGuiLiftForceAndSpped()
    self.is_im_gui_lift_force = ImGui.Checkbox("[ImGui] Lift Force And Speed", self.is_im_gui_lift_force)
    if self.is_im_gui_lift_force then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local v_x = string.format("%.2f", self.core_obj.av_obj.engine_obj.horizenal_x_speed)
        local v_y = string.format("%.2f", self.core_obj.av_obj.engine_obj.horizenal_y_speed)
        local v_z = string.format("%.2f", self.core_obj.av_obj.engine_obj.vertical_speed)
        ImGui.Text("F: " .. self.core_obj.av_obj.engine_obj.lift_force .. ", v_x: " .. v_x .. ", v_y: " .. v_y .. ", v_z: " .. v_z)
    end
end

function Debug:PrintActionCommand(action_name, action_type, action_value)
    if self.is_print_command then
        print("Action Name : " .. action_name .. ", Action Type : " .. action_type, ", Action Value : " .. action_value)
    end
end

return Debug
