local Log = require("Modules/log")
local Hud = {}
Hud.__index = Hud

function Hud:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Hud")
    return setmetatable(obj, self)
end

return Hud