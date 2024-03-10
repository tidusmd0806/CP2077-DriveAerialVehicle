local Log = require("Modules/log")
local UI = {}
UI.__index = UI

function UI:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "UI")
    return setmetatable(obj, self)
end

return UI