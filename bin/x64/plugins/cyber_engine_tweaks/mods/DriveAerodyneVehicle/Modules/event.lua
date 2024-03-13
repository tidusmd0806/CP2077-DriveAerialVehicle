local Log = require("Tools/log.lua")
local Camera = require("Modules/camera.lua")
local Ui = require("Modules/ui.lua")
local GameSession = require('External/GameSession')
local Event = {}
Event.__index = Event

function Event:New(av_obj)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Event")
    obj.ui_obj = Ui:New()
    obj.av_obj = av_obj
    obj.camera_obj = Camera:New()

    -- set flag
    obj.in_av = false -- player is in AV or not
    obj.camera_mode = CameraDistanceLevel.Fpp

    return setmetatable(obj, self)
end

function Event:Init()
    self.ui_obj:Init()
    GameSession.OnStart(function()
        self.ui_obj:ActivateAVSummon(true)
    end)

    GameSession.OnEnd(function()
        self.ui_obj:ActivateAVSummon(false)
    end)

end

function Event:CheckAllEvents()
    self:CheckCameraMode()
    self:CheckInAV()
    self:CheckCallVehicle()
end

function Event:CheckCallVehicle()
    if self.ui_obj:GetCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle call detected")
        self.av_obj:SpawnToSky()
        local times = 150
        DAV.Cron.Every(0.01, { tick = 1 }, function(timer)
            timer.tick = timer.tick + 1
            if timer.tick == times then
                self.av_obj:LockDoor()
            elseif timer.tick > times then
                if not self.av_obj:Move(0.0, 0.0, -0.5, 0.0, 0.0, 0.0) then
                DAV.Cron.Halt(timer)
                end
            end
        end)
    end
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
