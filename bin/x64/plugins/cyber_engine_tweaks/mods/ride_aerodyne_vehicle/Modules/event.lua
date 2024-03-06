local Log = require("Tools/log.lua")
local Camera = require("Modules/camera.lua")
local Event = {}
Event.__index = Event

function Event:New(av_obj)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Event")
    obj.av_obj = av_obj
    obj.camera_obj = Camera:New()

    -- set flag
    obj.in_av = false -- player is in AV or not

    return setmetatable(obj, self)
end

function Event:CheckAllEvents()
    self:CheckInAV()
end

function Event:CheckInAV()
    local player = Game.GetPlayer()
    if Game.GetWorkspotSystem():IsActorInWorkspot(player) then
        local mount_entity = Game['GetMountedVehicle;GameObject'](player)
        if mount_entity ~= nil then
            if string.find(string.lower(Game.NameToString(mount_entity:GetCurrentAppearanceName())), "excalibur") ~= nil then
                -- when player take on AV
                if not self.in_av then
                    self.log_obj:Record(LogLevel.Info, "Enter In AV")
                    self.camera_obj:SetVehiclePosition()
                end
                self.in_av = true
            end
        else
            -- when player take off from AV
            if self.in_av then
                self.log_obj:Record(LogLevel.Info, "Exit AV")
                self.camera_obj:SetDefaultPosition()
            end
            self.in_av = false
        end
    end
end

function Event:IsInAV()
    return self.in_av
end

return Event
