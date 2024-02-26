local Log = require("Modules/log.lua")
local Event = {}
Event.__index = Event

function Event:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Event")

    -- set flag
    obj.in_av = false

    return setmetatable(obj, self)
end

function Event:CheckInAV()
    local inVehicle = Game.GetWorkspotSystem():IsActorInWorkspot(Game.GetPlayer())
    if (inVehicle) then
        local vehicle = Game['GetMountedVehicle;GameObject'](Game.GetPlayer())
        if(vehicle ~= nil) then
            local isThiscar = (string.find(string.lower(Game.NameToString(vehicle:GetCurrentAppearanceName())), "excalibur") ~= nil)
            if isThiscar then
                if not self.in_av then
                    self.log_obj:Record(LogLevel.Info, "Enter In AV")
                end
                self.in_av = true
            end
        else
            if self.in_av then
                self.log_obj:Record(LogLevel.Info, "Exit AV")
            end
            self.in_av = false
        end
    end
end

return Event
