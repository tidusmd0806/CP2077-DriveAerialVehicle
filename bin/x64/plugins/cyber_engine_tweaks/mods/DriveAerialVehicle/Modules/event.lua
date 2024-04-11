local Log = require("Tools/log.lua")
local Def = require("Tools/def.lua")
local GameUI = require('External/GameUI.lua')
local Hud = require("Modules/hud.lua")
local Sound = require("Modules/sound.lua")
local Ui = require("Modules/ui.lua")
local Event = {}
Event.__index = Event

function Event:New()

    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Event")
    obj.av_obj = nil
    obj.hud_obj = Hud:New()
    obj.ui_obj = Ui:New()
    obj.sound_obj = Sound:New()

    obj.re_enter_wait = 8.0

    -- set default parameters
    obj.current_situation = Def.Situation.Normal
    obj.is_in_menu = false
    obj.is_in_popup = false
    obj.is_in_photo = false
    obj.is_locked_operation = false

    return setmetatable(obj, self)

end

function Event:Init(av_obj)

    self.current_situation = Def.Situation.Normal

    self.av_obj = av_obj

    self.ui_obj:Init(self.av_obj)
    self.hud_obj:Init(self.av_obj)
    self.sound_obj:Init(self.av_obj)

    if not DAV.ready then
        self:SetObserve()
        self:SetOverride()
    end

end

function Event:SetObserve()

    GameUI.Observe("SessionStart", function()
        DAV.Cron.After(0.5, function()
            DAV.core_obj:Reset()
            self.ui_obj:ActivateAVSummon(true)
        end)
    end)

    GameUI.Observe("MenuOpen", function()
        self.is_in_menu = true
    end)

    GameUI.Observe("MenuClose", function()
        self.is_in_menu = false
    end)

    GameUI.Observe("PopupOpen", function()
        self.is_in_popup = true
    end)

    GameUI.Observe("PopupClose", function()
        self.is_in_popup = false
    end)

    GameUI.Observe("PhotoModeOpen", function()
        self.is_in_photo = true
    end)

    GameUI.Observe("PhotoModeClose", function()
        self.is_in_photo = false
    end)

    GameUI.Observe("LoadingFinish", function()
        DAV.Cron.After(0.5, function()
            DAV.core_obj:Reset()
            self.ui_obj:ActivateAVSummon(true)
        end)
    end)

    GameUI.Observe("SessionEnd", function()
        self.ui_obj:ActivateAVSummon(false)
    end)
end

function Event:SetOverride()
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
        self:CheckCollision()
        self:CheckAutoModeChange()
    elseif self.current_situation == Def.Situation.TalkingOff then
        self:CheckDespawn()
    else
        self.log_obj:Record(LogLevel.Critical, "Invalid situation detected")
    end
end

function Event:CheckCallVehicle()
    if self.ui_obj:GetCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle call detected")
        self.sound_obj:PlaySound("101_call_vehicle")
        self.sound_obj:PlaySound("211_landing")
        self:SetSituation(Def.Situation.Landing)
        self.av_obj:SpawnToSky(5.5, 50)
    end
end

function Event:CheckLanded()
    if self.av_obj.position_obj:IsCollision() or self.av_obj.is_landed then
        self.log_obj:Record(LogLevel.Trace, "Landed detected")
        self.sound_obj:StopSound("211_landing")
        self.sound_obj:PlaySound("131_arrive_vehicle")
        self:SetSituation(Def.Situation.Waiting)
        self.av_obj:ChangeDoorState(Def.DoorOperation.Open)
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
            self.sound_obj:PlaySound("232_fly_loop")
            self:SetSituation(Def.Situation.InVehicle)
            self.hud_obj:HideChoice()
            self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
            self.hud_obj:ShowMeter()
            self.hud_obj:ShowCustomHint()
            self.hud_obj:HideActionButtons()
        end
    else
        -- when player take off from AV
        if self.current_situation == Def.Situation.InVehicle then
            self.log_obj:Record(LogLevel.Info, "Exit AV")
            self.sound_obj:StopSound("232_fly_loop")
            self:SetSituation(Def.Situation.Waiting)
            self.hud_obj:HideMeter()
            self.hud_obj:HideCustomHint()
            self.hud_obj:ShowActionButtons()
            SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
        end
    end
end

function Event:CheckCollision()
    if self.av_obj.is_collision then
        self.log_obj:Record(LogLevel.Debug, "Collision detected")
        if not self.av_obj.engine_obj:IsInFalling() then
            self.sound_obj:PlaySound("233_crash")
        end
    end
end

function Event:CheckReturnVehicle()
    if self.ui_obj:GetCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle return detected")
        self.sound_obj:PlaySound("243_leaving")
        self.sound_obj:PlaySound("104_call_vehicle")
        self:SetSituation(Def.Situation.TalkingOff)
        self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
        self.av_obj:DespawnFromGround()
    end
end

function Event:CheckDespawn()
    if self.av_obj:IsDespawned() then
        self.log_obj:Record(LogLevel.Trace, "Despawn detected")
        self.sound_obj:StopSound("243_leaving")
        self:SetSituation(Def.Situation.Normal)
        DAV.core_obj:Reset()
    end
end

function Event:CheckAutoModeChange()
    if self:IsAutoMode() and not self.is_locked_operation then
        self.is_locked_operation = true
    elseif not self:IsAutoMode() and self.is_locked_operation then
        self.is_locked_operation = false
        self.hud_obj:ShowArrivalDisplay()
    end

end

function Event:IsNotSpawned()
    if self.current_situation == Def.Situation.Normal then
        return true
    else
        return false
    end
end

function Event:IsWaiting()
    if self.current_situation == Def.Situation.Waiting then
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

function Event:IsAutoMode()
    if self.av_obj.is_auto_pilot then
        return true
    else
        return false
    end
end

function Event:IsInMenuOrPopupOrPhoto()
    if self.is_in_menu or self.is_in_popup or self.is_in_photo then
        return true
    else
        return false
    end
end

function Event:IsAllowedEntry()
    return self.is_allowed_entry
end

function Event:ChangeDoor()
    if self.current_situation == Def.Situation.InVehicle then
        self.av_obj:ChangeDoorState(Def.DoorOperation.Change)
    end
end

function Event:EnterVehicle()
    if self:IsInEntryArea()then
        self.av_obj:Mount()
    end
end

function Event:ExitVehicle()
    if self:IsInVehicle() then
        self.av_obj:Unmount()
    end
end

function Event:ToggleAutoMode()
    if self:IsInVehicle() then
        if not self.av_obj.is_auto_pilot then
            self.hud_obj:ShowAutoModeDisplay()
            self.is_locked_operation = true
            self.av_obj:AutoPilotNew()
        else
            self.hud_obj:ShowDriveModeDisplay()
            self.is_locked_operation = false
            self.av_obj:InterruptAutoPilot()
        end
    end
end

return Event
