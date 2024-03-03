local Debug = {}
Debug.__index = Debug

function Debug:New(core_obj)
    local obj = {}
    obj.core_obj = core_obj

    -- set parameters
    obj.is_print_command = false
    obj.is_im_gui_player_position = false
    obj.is_im_gui_av_position = false
    return setmetatable(obj, self)
end

function Debug:Init()
    ImGui.SetNextWindowPos(100, 500, ImGuiCond.FirstUseEver) -- set window position x, y
    ImGui.SetNextWindowSize(500, 600, ImGuiCond.Appearing) -- set window size w, h
    ImGui.Begin("RAV DEBUG WINDOW")
    ImGui.Text("Debug Mode : On")
end

function Debug:End()
    ImGui.End()
end

function Debug:SelectParameter()
    self.is_print_command = ImGui.Checkbox("[Print] Action Command", self.is_print_command)
    self.is_im_gui_player_position = ImGui.Checkbox("[ImGui]  Player Position", self.is_im_gui_player_position)
    self.is_im_gui_av_position = ImGui.Checkbox("[ImGui]  AV Position", self.is_im_gui_av_position)
end

function Debug:ImGuiMain()
    self:Init()
    self:SelectParameter()
    self:ImGuiPlayerPosition()
    self:ImGuiAvPosition()
end

function Debug:ImGuiPlayerPosition()
    if self.is_im_gui_player_position then
        ImGui.Text("Player X:" .. Game.GetPlayer():GetWorldPosition().x .. ", Y:" .. Game.GetPlayer():GetWorldPosition().y .. ", Z:" .. Game.GetPlayer():GetWorldPosition().z)
    end
end

function Debug:ImGuiAvPosition()
    if self.is_im_gui_av_position then
        ImGui.Text("AV X:" .. self.core_obj.av_obj.position_obj:GetPosition().x .. ", Y:" .. self.core_obj.av_obj.position_obj:GetPosition().y .. ", Z:" .. self.core_obj.av_obj.position_obj:GetPosition().z)
    end
end

function Debug:PrintActionCommand(action_name, action_type, action_value)
    if self.is_print_command then
        print("Action Name : " .. action_name .. ", Action Type : " .. action_type, ", Action Value : " .. action_value)
    end
end

return Debug
