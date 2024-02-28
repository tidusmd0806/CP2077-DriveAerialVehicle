local Debug = {}
Debug.__index = Debug

function Debug:New()
    local obj = {}

    -- set parameters
    obj.print_debug_mode = false
    return setmetatable(obj, self)
end

function Debug:Init()
    ImGui.SetNextWindowPos(100, 500, ImGuiCond.FirstUseEver) -- set window position x, y
    ImGui.SetNextWindowSize(500, 600, ImGuiCond.Appearing) -- set window size w, h
    ImGui.Begin("RAV DEBUG WINDOW")
    ImGui.Text("Debug Mode : On")
end

function Debug:CheckAction(action_name, action_type, action_value)
    if self.print_debug_mode then
        print("Action Name : " .. action_name .. ", Action Type : " .. action_type, ", Action Value : " .. action_value)
    end
end

return Debug
