local Aerodyne = require("Modules/aerodyne.lua")
local Player = require("Modules/player.lua")
local Event = require("Modules/event.lua")
local Input = require("Data/input.lua")
local Log = require("Tools/log.lua")
local Model = require("Data/model.lua")
local Queue = require("Tools/queue.lua")
local Utils = require("Tools/utils.lua")

local Core = {}
Core.__index = Core

function Core:New()
    local obj = {}
    obj.av_obj = Aerodyne:New(Model.Excalibur)
    obj.event_obj = Event:New(obj.av_obj)
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Core")
    obj.queue_obj = Queue:New()
    self.player_obj = nil

    return setmetatable(obj, self)
end

function Core:Init()
    self.player_obj = Player:New(Game.GetPlayer())

    DAV.Cron.Every(DAV.time_resolution, function()
        self.event_obj:CheckAllEvents()
        self:ExcutePriodicalTask()
    end)
end

function Core:StorePlayerAction(action_name, action_type, action_value)
    local action_value_type = "ZERO"
    if action_value > 0.1 then
        action_value_type = "POSITIVE"
    elseif action_value < -0.1 then
        action_value_type = "NEGATIVE"
    else
        action_value_type = "ZERO"
    end

    local cmd = self:ConvertActionList(action_name, action_type, action_value_type)

    if cmd ~= ActionList.Nothing then
        self.queue_obj:Enqueue(cmd)
    end

end

function Core:ConvertActionList(action_name, action_type, action_value)
    local action_command = ActionList.Nothing
    local action_dist = {name = action_name, type = action_type, value = action_value}

    if Utils:IsTablesEqual(action_dist, Input.KEY_CLICK_HOLD_IN_AV) then
        action_command = ActionList.Up
    elseif Utils:IsTablesEqual(action_dist, Input.KEY_CLICK_RELEASE_IN_AV) then
        action_command = ActionList.Down
    elseif Utils:IsTablesEqual(action_dist, Input.KEY_W_PRESS_IN_AV) then
        action_command = ActionList.Forward
    elseif Utils:IsTablesEqual(action_dist, Input.KEY_S_PRESS_IN_AV) then
        action_command = ActionList.Backward
    elseif Utils:IsTablesEqual(action_dist, Input.KEY_D_PRESS_IN_AV) then
        action_command = ActionList.Right
    elseif Utils:IsTablesEqual(action_dist, Input.KEY_A_PRESS_IN_AV) then
        action_command = ActionList.Left
    elseif Utils:IsTablesEqual(action_dist, Input.KEY_E_PRESS_IN_AV) then
        action_command = ActionList.TurnRight
    elseif Utils:IsTablesEqual(action_dist, Input.KEY_Q_PRESS_IN_AV) then
        action_command = ActionList.TurnLeft
    else
        action_command = ActionList.Nothing
    end

    return action_command
end

function Core:ExcutePriodicalTask()
    local actions = {}
    if self.queue_obj:IsEmpty() then
        local action = ActionList.Nothing
        table.insert(actions, action)
    else
        while not self.queue_obj:IsEmpty() do
            local action = self.queue_obj:Dequeue()
            table.insert(actions, action)
        end
    end
    self:OperateAerodyneVehicle(actions)
end

function Core:CallAerodyneVehicle()
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

function Core:ChangeAerodyneDoor()
    self.av_obj:ChangeDoorState(1)
end

function Core:LockAerodyneDoor()
    self.av_obj:LockDoor()
    self.av_obj:Despawn()
    local audioEvent = SoundPlayEvent.new()

    audioEvent.soundName = StringToName("v_av_rayfield_excalibur_traffic_engine_01_av_dplr_01")
    print("sound")
    Game.GetPlayer():QueueEvent(audioEvent)
end

function Core:UnlockAerodyneDoor()
    -- self.av_obj:UnlockDoor()
    -- SaveLocksManager.RequestSaveLockAdd("PersonalLink")
    -- if SaveLocksManager.IsSavingLocked() then
    --     print("locked")
    -- else
    --     print("unlocked")
    -- end
    -- local choice = interaction.createChoice("Choice", TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceIcons.SitIcon"))
    -- self.hub = interaction.createHub(self.name, {choice})
    -- interaction.setupHub(self.hub)
    -- interaction.callbacks[1] = function()
    --     interaction.hideHub()
    --     print("unlock")
    -- end
    -- interaction.showHub()
    local choice = gameinteractionsvisListChoiceData.new()
    choice.localizedName = "Choice"
    choice.inputActionName = "None"

    local part = gameinteractionsChoiceCaption.new()
    part:AddPartFromRecord(TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceIcons.SitIcon"))
    choice.captionParts = part

    local hub = gameinteractionsvisListChoiceHubData.new()
    hub.title = "Title"
    hub.choices = {choice}
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
    hub.hubPriority = -1
    hub.id = 69420 + math.random(99999)

    DAV.ui_choice_hub = hub

    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions);
    local ibd = GetAllBlackboardDefs().UIInteractions;

    local data = ib:GetVariant(ibd.DialogChoiceHubs)
    DAV.ui_choice_handler:OnDialogsData(data)

    DAV.GameHUD.ShowMessage("Test")

end

function Core:Mount()
    self.player_obj:Init()
    self.av_obj:TakeOn(self.player_obj)
    self.av_obj:Mount(3)
end

function Core:Unmount()
    self.av_obj:Unmount()
end

function Core:OperateAerodyneVehicle(actions)
    if self.event_obj:IsInAV() then
        for _, action_command in ipairs(actions) do
            self.av_obj:Operate(action_command)
        end
    end
end

return Core
