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
    obj.camera_mode = CameraDistanceLevel.Fpp

    return setmetatable(obj, self)
end

function Event:CheckAllEvents()
    self:CheckCameraMode()
    self:CheckInAV()
end


function Event:CheckInAV()
    if self.av_obj.is_player_in then
        -- when player take on AV
        if not self.in_av then
            self.log_obj:Record(LogLevel.Info, "Enter In AV")
            self:ChangeCamera()
        end
        self.in_av = true
    else
        -- when player take off from AV
        if self.in_av then
            self.log_obj:Record(LogLevel.Info, "Exit AV")
            self:ChangeCamera()
        end
        self.in_av = false
    end
end

function Event:CheckCameraMode()
    self.camera_mode = self.camera_obj.camera_mode
end

function Event:IsInAV()
    return self.in_av
end

function Event:IsCameraMode()
    return self.camera_mode
end

function Event:ChangeCamera()
    if self.camera_mode == CameraDistanceLevel.Fpp then
        self.camera_obj:SetCameraPosition(CameraDistanceLevel.TppClose)
    elseif self.camera_mode >= CameraDistanceLevel.TppClose then
        self.camera_obj:SetCameraPosition(CameraDistanceLevel.Fpp)
    end
end

return Event
