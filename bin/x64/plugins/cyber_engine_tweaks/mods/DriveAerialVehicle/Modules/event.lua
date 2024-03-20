local Log = require("Tools/log.lua")
local Camera = require("Modules/camera.lua")
local Def = require("Modules/def.lua")
local Hud = require("Modules/hud.lua")
local Ui = require("Modules/ui.lua")
local Event = {}
Event.__index = Event

function Event:New(av_obj)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Event")
    obj.hud_obj = Hud:New(av_obj.engine_obj)
    obj.ui_obj = Ui:New()
    obj.av_obj = av_obj
    obj.camera_obj = Camera:New()

    -- set default parameters
    obj.current_situation = Def.Situation.Normal
    obj.door_open_wait_time = 5.0

    return setmetatable(obj, self)
end

function Event:Init(index)
    local display_name_lockey = self.av_obj.all_models[index].display_name_lockey
    local logo_inkatlas_path = self.av_obj.all_models[index].logo_inkatlas_path
    local logo_inkatlas_part_name = self.av_obj.all_models[index].logo_inkatlas_part_name
    local choice_title = self.av_obj.all_models[index].name

    self.ui_obj:Init(display_name_lockey, logo_inkatlas_path, logo_inkatlas_part_name)
    self.hud_obj:Init(choice_title)

    Override("OpenVendorUI", "CreateInteraction", function(this, arg_1, arg_2, arg_3, wrapped_method)
        if this:GetActionName().value == "vehicle_door_quest_locked" and self:IsInEntryArea() then
            self.log_obj:Record(LogLevel.Trace, "Disappear vehicle door quest locked")
            return
        end
        wrapped_method(arg_1, arg_2, arg_3)
    end)
end

function Event:SetSituation(situation)
    if self.current_situation == Def.Situation.Normal and situation == Def.Situation.Landing then
        self.log_obj:Record(LogLevel.Info, "Landing detected")
        self.current_situation = Def.Situation.Landing
        return true
    elseif self.current_situation == Def.Situation.Landing and situation == Def.Situation.Waiting then
        self.log_obj:Record(LogLevel.Info, "Waiting detected")
        self.current_situation = Def.Situation.Waiting
        return true
    elseif (self.current_situation == Def.Situation.Waiting and situation == Def.Situation.InVehicle) then
        self.log_obj:Record(LogLevel.Info, "InVehicle detected")
        self.current_situation = Def.Situation.InVehicle
        return true
    elseif (self.current_situation == Def.Situation.Waiting and situation == Def.Situation.TalkingOff) then
        self.log_obj:Record(LogLevel.Info, "TalkingOff detected")
        self.current_situation = Def.Situation.TalkingOff
        return true
    elseif (self.current_situation == Def.Situation.InVehicle and situation == Def.Situation.Waiting) then
        self.log_obj:Record(LogLevel.Info, "Waiting detected")
        self.current_situation = Def.Situation.Waiting
        return true
    elseif (self.current_situation == Def.Situation.TalkingOff and situation == Def.Situation.Normal) then
        self.log_obj:Record(LogLevel.Info, "Normal detected")
        self.current_situation = Def.Situation.Normal
        return true
    else
        self.log_obj:Record(LogLevel.Critical, "Invalid translating situation")
        return false
    end
end

function Event:CheckAllEvents()
    if self.current_situation == Def.Situation.Normal then
        self:CheckCallVehicle()
    elseif self.current_situation == Def.Situation.Landing then
        self:CheckLanded()
    elseif self.current_situation == Def.Situation.Waiting then
        self:CheckInEntryArea()
        self:CheckInAV()
        self:CheckReturnVehicle()
    elseif self.current_situation == Def.Situation.InVehicle then
        self:CheckInAV()
    elseif self.current_situation == Def.Situation.TalkingOff then
        print("TalkingOff")
    else
        self.log_obj:Record(LogLevel.Critical, "Invalid situation detected")
    end
end

function Event:CheckCallVehicle()
    if self.ui_obj:GetCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle call detected")
        self:SetSituation(Def.Situation.Landing)
        self.av_obj:SpawnToSky(5.5, 50)
    end
end

function Event:CheckLanded()
    if self.av_obj.position_obj:IsCollision() then
        self.log_obj:Record(LogLevel.Trace, "Landed detected")
        self:SetSituation(Def.Situation.Waiting)
        self.av_obj:ChangeDoorState(1,Def.DoorOperation.Open)
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
        if self.current_situation == Def.Situation.Waiting then
            self.log_obj:Record(LogLevel.Info, "Enter In AV")
            SaveLocksManager.RequestSaveLockAdd(CName.new("DAV_IN_AV"))
            self:SetSituation(Def.Situation.InVehicle)
            self.hud_obj:HideChoice()
            self:ChangeCamera()
            self.av_obj:ChangeDoorState(1, Def.DoorOperation.Close)
            self.hud_obj:ShowMeter()
            self.hud_obj:ShowCustomHint()
        end
    else
        -- when player take off from AV
        if self.current_situation == Def.Situation.InVehicle then
            self.log_obj:Record(LogLevel.Info, "Exit AV")
            self:SetSituation(Def.Situation.Waiting)
            self.av_obj:ChangeDoorState(1, Def.DoorOperation.Open)
            self:ChangeCamera()
            self.hud_obj:HideMeter()
            self.hud_obj:HideCustomHint()
            SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
        end
    end
end

function Event:CheckReturnVehicle()
    if self.ui_obj:GetCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle return detected")
        self:SetSituation(Def.Situation.TalkingOff)
        self.av_obj:ChangeDoorState(1, Def.DoorOperation.Close)
        self.av_obj:DespawnFromGround()
        DAV.Cron.After(10, function()
            self:SetSituation(Def.Situation.Normal)
        end)
    end
end

function Event:IsAvailableMovement()
    if self.current_situation == Def.Situation.Waiting or self.current_situation == Def.Situation.InVehicle then
        return true
    else
        return false
    end
end

function Event:IsInEntryArea()
    if self.current_situation == Def.Situation.Waiting and self.av_obj.position_obj:IsPlayerInEntryArea() then
        return true
    else
        return false
    end
end

function Event:IsInVehicle()
    if self.current_situation == Def.Situation.InVehicle and self.av_obj:IsPlayerIn() then
        return true
    else
        return false
    end
end

function Event:ChangeCamera()
    if self.current_situation == Def.Situation.InVehicle then
        self.camera_obj:SetCameraPosition(Def.CameraDistanceLevel.TppClose)
    elseif self.current_situation == Def.Situation.Waiting then
        self.camera_obj:SetCameraPosition(Def.CameraDistanceLevel.Fpp)
    end
end

function Event:ToggleCamera()
    if self.current_situation == Def.Situation.InVehicle then
        local res = self.camera_obj:ToggleCameraPosition()
        if res == Def.CameraDistanceLevel.Fpp then
            self.av_obj.player_obj:ActivateTPPHead(false)
        elseif res == Def.CameraDistanceLevel.TppClose then
            self.av_obj.player_obj:ActivateTPPHead(true)
         end
    end
end

function Event:ChangeDoor()
    if self.current_situation == Def.Situation.InVehicle then
        self.av_obj:ChangeDoorState(1, Def.DoorOperation.Change)
    end
end

function Event:EnterOrExitVehicle(player)
    if self:IsInEntryArea() then
        self.av_obj:TakeOn(player)
        self.av_obj:Mount(3)
    elseif self:IsInVehicle() then
        self.av_obj:Unmount()
        self.av_obj:TakeOff()
    end
end

return Event
