local Log = require("Tools/log.lua")
Player = {}
Player.__index = Player

function Player:New(player)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Player")

    obj.player = player

    --require archive file
    obj.workspot_resorce_component_name = "av_seat_workspot"
    obj.workspot_entity_path = "base\\dav\\dummy_seat.ent"

    -- set default parameters
    obj.dummy_entity_id = nil
    obj.player_position_in_vehicle = nil
    obj.gender = nil

    return setmetatable(obj, self)
end

function Player:Init()
    local gender_string = Game.GetPlayer():GetResolvedGenderName()
    if string.find(tostring(gender_string), "Female") then
        self.gender = "Female"
    else
        self.gender = "Male"
    end
end

function Player:PlayPose(sit_pose)
    local pose_name = nil
    if self.gender == "Female" then
        pose_name = sit_pose.female
	else
        pose_name = sit_pose.male
	end

    local player = Game.GetPlayer()
    local transform = player:GetWorldTransform()
    transform:SetPosition(player:GetWorldPosition())
    local angles = player:GetWorldOrientation():ToEulerAngles()
    angles.yaw = angles.yaw + 180
    transform:SetOrientationEuler(EulerAngles.new(0, 0, angles.yaw))

    self.dummy_entity_id = exEntitySpawner.Spawn(self.workspot_entity_path, transform, '')

    DAV.Cron.Every(0.01, {tick = 1}, function(timer)
        local dummy_entity = Game.FindEntityByID(self.dummy_entity_id)
        if dummy_entity ~= nil then
            Game.GetWorkspotSystem():StopInDevice(Game.GetPlayer())
            DAV.Cron.After(0.1, function()
                Game.GetWorkspotSystem():PlayInDeviceSimple(dummy_entity, player, true, self.workspot_resorce_component_name, nil, nil, 0, 1, nil)
                Game.GetWorkspotSystem():SendJumpToAnimEnt(player, pose_name, true)
            end)

            -- DAV.Cron.After(0.2, function()
            --     Game.GetWorkspotSystem():PlayInDeviceSimple(dummy_entity, player, true, self.workspot_resorce_component_name, nil, nil, 0, 1, nil)
            --     Game.GetWorkspotSystem():SendJumpToAnimEnt(player, pose_name, true)
            -- end)
            DAV.Cron.Halt(timer)
        end
    end)
end

function Player:StopPose()
    if self.dummy_entity_id ~= nil then
        local dummy_entity = Game.FindEntityByID(self.dummy_entity_id)
        if dummy_entity ~= nil then
            exEntitySpawner.Despawn(dummy_entity)
            self.dummy_entity_id = nil
        end
    end
end

-- refer to https://github.com/MaximiliumM/appearancemenumod for changing head when tpp or fpp
function Player:ActivateTPPHead(is_tpp)
    local delay = 10
    local player = Game.GetPlayer()
    local head_type = nil
    if self.gender == "Famale" then
        head_type = "Items.CharacterCustomizationWaHead"
    else
        head_type = "Items.CharacterCustomizationMaHead"
    end

    local transcation_system = Game.GetTransactionSystem()
    local head_solt = TweakDBID.new("AttachmentSlots.TppHead")
    local head_id = ItemID.FromTDBID(TweakDBID.new(head_type))

    local fpp_head_id = ItemID.FromTDBID(TweakDBID.new("Items.PlayerFppHead"))

    if not transcation_system:HasItem(Game.GetPlayer(), head_id) then
        self.log_obj:Record(LogLevel.Trace, "No head item found")

        local equip_request = EquipRequest.new()
        Game.GetTransactionSystem():GiveItem(player, head_id, 1)
        equip_request.owner = player
        Game.GetScriptableSystemsContainer():Get("EquipmentSystem"):QueueRequest(equip_request)
    end

    if DAV.core_obj.event_obj:IsInVehicle() then
        transcation_system:ChangeItemAppearanceByName(player, head_id, "default&FPP")
    end

    transcation_system:RemoveItemFromSlot(player, head_solt, true, true, true)

    if is_tpp then
        DAV.Cron.Every(0.001, { tick = 1 }, function(timer)
            timer.tick = timer.tick + 1

            if timer.tick > delay then
                DAV.Cron.Halt(timer)
            end
            DAV.Cron.After(0.001, function()
                transcation_system:RemoveItemFromSlot(player, head_solt, true, true, true)
            end)

            DAV.Cron.After(0.1, function()
                if transcation_system:GetItemInSlot(player, head_solt) == nil then
                    transcation_system:AddItemToSlot(player, head_solt, head_id)
                end
            end)

        end)
    else
        DAV.Cron.Every(0.001, { tick = 1 }, function(timer)
            timer.tick = timer.tick + 1

            transcation_system:ChangeItemAppearanceByName(player, head_id, "default&FPP")

            if timer.tick > delay then
                DAV.Cron.After(1.0, function()
                    -- I dont know why this is needed, but it is important to change the head to fpp head
                    local tpp_event = ActivateTPPRepresentationEvent.new()
                    tpp_event.playerController = Game.GetPlayer()
                    GetPlayer():QueueEvent(tpp_event)
                    DAV.Cron.After(0.1, function()
                        Game.GetScriptableSystemsContainer():Get(CName.new("TakeOverControlSystem")):EnablePlayerTPPRepresenation(false)
                    end)
                end)
                DAV.Cron.Halt(timer)
            end
            DAV.Cron.After(0.001, function()
                transcation_system:RemoveItemFromSlot(player, head_solt, true, true, true)
            end)

            DAV.Cron.After(0.1, function()
                if transcation_system:GetItemInSlot(player, head_solt) == nil then
                    transcation_system:AddItemToSlot(player, head_solt, fpp_head_id)
                    transcation_system:ChangeItemAppearanceByName(player, fpp_head_id, "default&FPP")
                end
            end)

        end)
    end
end

return Player