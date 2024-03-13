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
    self.event_obj:Init()

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
    -- self.av_obj:LockDoor()
    self.av_obj:Despawn()
    -- local audioEvent = SoundPlayEvent.new()

    -- audioEvent.soundName = StringToName("v_av_rayfield_excalibur_traffic_engine_01_av_dplr_01")
    -- print("sound")
    -- Game.GetPlayer():QueueEvent(audioEvent)

    DAV.hudCarController:HideRequest()
    DAV.hudCarController:OnCameraModeChanged(false)
end

function Core:UnlockAerodyneDoor()
    -- self.av_obj:UnlockDoor()

    SaveLocksManager.RequestSaveLockAdd("PersonalLink")

    local choice = gameinteractionsvisListChoiceData.new()
    choice.localizedName = "Choice"
    choice.inputActionName = CName.new("Forward")

    local part = gameinteractionsChoiceCaption.new()
    part:AddPartFromRecord(TweakDBInterface.GetChoiceCaptionIconPartRecord("ChoiceIcons.SitIcon"))
    choice.captionParts = part

    local hub = gameinteractionsvisListChoiceHubData.new()
    hub.title = "Title"
    hub.choices = {choice}
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
    hub.hubPriority = 1
    hub.id = 100000 + math.random(99999)

    DAV.ui_choice_hub = hub

    local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UIInteractions);
    local ibd = GetAllBlackboardDefs().UIInteractions;

    ib:SetInt(ibd.ActiveChoiceHubID, hub.id)
    local data = ib:GetVariant(ibd.DialogChoiceHubs)
    DAV.ui_choice_handler:OnDialogsData(data)
    DAV.is_ui_choice_custom = true

    -- DAV.GameHUD.ShowMessage("Test")

    -- local ink_system = Game.GetInkSystem()
    -- local layers = ink_system:GetLayers()

    -- DAV.Cron.After(1, function()
    --     for _, layer in ipairs(layers) do
    --         print(layer:GetLayerName())
    --         for _, controller in ipairs(layer:GetGameControllers()) do
    --             print(controller:GetClassName())
    --         end
    --     end
    -- end)

    -- local hud_root = ink_system:GetLayer("inkHUDLayer"):GetVirtualWindow()

    -- local hello = inkText.new()
    -- hello:SetText("Hello World")
    -- hello:SetFontFamily("base\\gameplay\\gui\\fonts\\orbitron\\orbitron.inkfontfamily")
    -- hello:SetFontStyle("Bold")
    -- hello:SetFontSize(200)
    -- hello:SetTintColor(HDRColor.new(1.1761, 0.3809, 0.3476, 1.0))
    -- hello:SetAnchor(inkEAnchor.Centered)
    -- hello:SetAnchorPoint(0.5, 0.5)
    -- hello:Reparent(hud_root)
    local ui_system = Game.GetUISystem()
    local event = UpdateInputHintMultipleEvent.new()
    event.targetHintContainer = CName.new("GameplayInputHelper")

    local data = InputHintData.new()
    data.source = CName.new("IK_G")
    data.action = CName.new("Forward")
    data.holdIndicationType = inkInputHintHoldIndicationType.FromInputConfig
    data.sortingPriority = 0
    data.enableHoldAnimation = false
    data.localizedLabel = GetLocalizedTextByKey("Input-Hint-Enable-Flight")
    if string.len(data.localizedLabel) == 0 then
        data.localizedLabel = tostring("Input-Hint-Enable-Flight")
      end

    event:AddInputHint(data, true)
    ui_system:QueueEvent(event)

    DAV.hudCarController:ShowRequest()
    DAV.hudCarController:OnInitialize()
    DAV.hudCarController:OnCameraModeChanged(true)
    DAV.Cron.Every(1, function()
        local rand = math.random(0,7)
        DAV.hudCarController:OnSpeedValueChanged(rand)
        DAV.hudCarController:OnRpmValueChanged(rand)
        DAV.hudCarController:EvaluateRPMMeterWidget(rand)
    end)
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
