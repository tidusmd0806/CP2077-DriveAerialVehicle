local Log = require("Tools/log.lua")
local Camera = require("Modules/camera.lua")
local Hud = require("Modules/hud.lua")
local Ui = require("Modules/ui.lua")
local Event = {}
Event.__index = Event

Situation = {
    Normal = 0,
    Landing = 1,
    Waiting = 2,
    InVehicle = 3,
    TalkingOff = 4,
}

function Event:New(av_obj)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Event")
    obj.hud_obj = Hud:New()
    obj.ui_obj = Ui:New()
    obj.av_obj = av_obj
    obj.camera_obj = Camera:New()

    -- set default parameters
    obj.current_situation = Situation.Normal

    return setmetatable(obj, self)
end

function Event:Init(index)
    local display_name_lockey = self.av_obj.all_models[index].display_name_lockey
    local logo_inkatlas_path = self.av_obj.all_models[index].logo_inkatlas_path
    local logo_inkatlas_part_name = self.av_obj.all_models[index].logo_inkatlas_part_name
    local choice_title = self.av_obj.all_models[index].name

    self.ui_obj:Init(display_name_lockey, logo_inkatlas_path, logo_inkatlas_part_name)
    self.hud_obj:Init(choice_title)
end

function Event:SetSituation(situation)
    if self.current_situation == Situation.Normal and situation == Situation.Landing then
        self.log_obj:Record(LogLevel.Info, "Landing detected")
        self.current_situation = Situation.Landing
        return true
    elseif self.current_situation == Situation.Landing and situation == Situation.Waiting then
        self.log_obj:Record(LogLevel.Info, "Waiting detected")
        self.current_situation = Situation.Waiting
        return true
    elseif (self.current_situation == Situation.Waiting and situation == Situation.InVehicle) then
        self.log_obj:Record(LogLevel.Info, "InVehicle detected")
        self.current_situation = Situation.InVehicle
        return true
    elseif (self.current_situation == Situation.Waiting and situation == Situation.TalkingOff) then
        self.log_obj:Record(LogLevel.Info, "TalkingOff detected")
        self.current_situation = Situation.TalkingOff
        return true
    elseif (self.current_situation == Situation.InVehicle and situation == Situation.Waiting) then
        self.log_obj:Record(LogLevel.Info, "Waiting detected")
        self.current_situation = Situation.Waiting
        return true
    elseif (self.current_situation == Situation.TalkingOff and situation == Situation.Normal) then
        self.log_obj:Record(LogLevel.Info, "Normal detected")
        self.current_situation = Situation.Normal
        return true
    else
        self.log_obj:Record(LogLevel.Critical, "Invalid translating situation")
        return false
    end
end

function Event:CheckAllEvents()
    if self.current_situation == Situation.Normal then
        self:CheckCallVehicle()
    elseif self.current_situation == Situation.Landing then
        self:CheckLanded()
    elseif self.current_situation == Situation.Waiting then
        self:CheckInEntryArea()
        self:CheckInAV()
    elseif self.current_situation == Situation.InVehicle then
        self:CheckInAV()
    elseif self.current_situation == Situation.TalkingOff then
        print("TalkingOff")
    else
        self.log_obj:Record(LogLevel.Critical, "Invalid situation detected")
    end
end

function Event:CheckCallVehicle()
    if self.ui_obj:GetCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle call detected")
        self:SetSituation(Situation.Landing)
        self.av_obj:SpawnToSky(5.5, 50)
    end
end

function Event:CheckLanded()
    if self.av_obj.position_obj:IsCollision() then
        self.log_obj:Record(LogLevel.Trace, "Landed detected")
        self:SetSituation(Situation.Waiting)
    end
end

function Event:CheckInEntryArea()
    if self.av_obj.position_obj:IsPlayerInEntryArea() then
        self.log_obj:Record(LogLevel.Trace, "InEntryArea detected")
        self.hud_obj:ShowChoice()
    else
        self.hud_obj:HideChoice()
    end
end

function Event:CheckInAV()
    if self.av_obj:IsPlayerIn() then
        -- when player take on AV
        if self.current_situation == Situation.Waiting then
            self.log_obj:Record(LogLevel.Info, "Enter In AV")
            self:SetSituation(Situation.InVehicle)
            self.hud_obj:HideChoice()
            self:ChangeCamera()
        end
    else
        -- when player take off from AV
        if self.current_situation == Situation.InVehicle then
            self.log_obj:Record(LogLevel.Info, "Exit AV")
            self:SetSituation(Situation.Waiting)
            self:ChangeCamera()
        end
    end
end

function Event:IsInEntryArea()
    if self.current_situation == Situation.Waiting and self.av_obj.position_obj:IsPlayerInEntryArea() then
        return true
    else
        return false
    end
end

function Event:IsInVehicle()
    if self.current_situation == Situation.InVehicle and self.av_obj:IsPlayerIn() then
        return true
    else
        return false
    end
end

function Event:ChangeCamera()
    if self.current_situation == Situation.InVehicle then
        self.camera_obj:SetCameraPosition(CameraDistanceLevel.TppClose)
    elseif self.current_situation == Situation.Waiting then
        self.camera_obj:SetCameraPosition(CameraDistanceLevel.Fpp)
    end
end

function Event:EnterVehicle(player)
    if self:IsInEntryArea() then
        self.av_obj:TakeOn(player)
        self.av_obj:Mount(3)
    end
end

return Event
