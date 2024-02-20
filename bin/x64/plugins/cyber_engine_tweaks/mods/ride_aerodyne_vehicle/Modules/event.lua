local Log = require("Modules/log.lua")
local Event = {}
Event.__index = Event

function Event:new()
    local obj = {}
    obj.log_obj = Log:new()
    obj.log_obj:setLevel(LogLevel.INFO, "Event")

    -- set flag
    obj.in_av = false

    return setmetatable(obj, self)
end

function Event:checkInAV()
    local inVehicule = Game.GetWorkspotSystem():IsActorInWorkspot(Game.GetPlayer())
    if (inVehicule) then
        local vehicule = Game['GetMountedVehicle;GameObject'](Game.GetPlayer())
        if(vehicule ~= nil) then
            local isThiscar = (string.find(string.lower(Game.NameToString(vehicule:GetCurrentAppearanceName())), "excalibur") ~= nil)
            if isThiscar then
                if not self.in_av then
                    self.log_obj:record(LogLevel.INFO, "Enter In AV")
                end
                self.in_av = true
                -- local pos = Game.GetPlayer():GetWorldPosition()
                -- local rot = GetPlayer():GetWorldOrientation():ToEulerAngles()
                -- print(pos.x)
                -- print(pos.y)
                -- print(pos.z)
                -- Game.GetTeleportationFacility():Teleport(vehicule, Vector4.new(pos.x, pos.y, pos.z + 50,1), EulerAngles.new(rot.roll, rot.pitch, rot.yaw))
                -- Game.GetPlayer():GetFPPCameraComponent():SetLocalOrientation(GetSingleton('EulerAngles'):ToQuat(EulerAngles.new(rot.roll, 0, 0)))
            end
        else
            if self.in_av then
                self.log_obj:record(LogLevel.INFO, "Exit AV")
            end
            self.in_av = false
        end
    end
end

return Event
