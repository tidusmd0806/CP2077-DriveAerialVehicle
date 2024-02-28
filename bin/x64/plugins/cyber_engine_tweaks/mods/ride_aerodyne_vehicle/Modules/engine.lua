local Log = require("Modules/log")
Engine = {}
Engine.__index = Engine

function Engine:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Engine")
    return setmetatable(obj, self)
end

return Engine