local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
Player = {}
Player.__index = Player

function Player:New(player)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Player")

    obj.player = player
    obj.workspot_resorce_component_name = "av_seat_workspot"
    obj.workspot_entity_path = "base\\dav\\dummy_seat.ent"

    -- set default parameters
    obj.dummy_entity_id = nil
    obj.player_position_in_vehicle = Vector4.new(0, 0, 0, 1.0)

    return setmetatable(obj, self)
end

function Player:SetPositionInVehicle(cordinate)
    self.player_position_in_vehicle = Vector4.new(cordinate.x, cordinate.y, cordinate.z, 1.0)
end

function Player:PlayPose(pose_name)
    local player = Game.GetPlayer()
    local transform = player:GetWorldTransform()
    transform:SetPosition(player:GetWorldPosition())
    local angles = player:GetWorldOrientation():ToEulerAngles()
    angles.yaw = angles.yaw + 180
    transform:SetOrientationEuler(EulerAngles.new(0, 0, angles.yaw))

    self.dummy_entity_id = exEntitySpawner.Spawn(self.workspot_entity_path, transform, '')
    -- local anim_name = "sit_chair_lean180__2h_on_lap__01"
 
    DAV.Cron.Every(0.1, {tick = 1}, function(timer)
        local dummy_entity = Game.FindEntityByID(self.dummy_entity_id)
        if dummy_entity ~= nil then
            Game.GetWorkspotSystem():PlayInDeviceSimple(dummy_entity, player, true, self.workspot_resorce_component_name, nil, nil, 0, 1, nil)
            Game.GetWorkspotSystem():SendJumpToAnimEnt(player, pose_name, false)

            -- for some reason, the pose is not played at the first time, so we need to play it again
            DAV.Cron.After(1, function()
                Game.GetWorkspotSystem():PlayInDeviceSimple(dummy_entity, player, true, self.workspot_resorce_component_name, nil, nil, 0, 1, nil)
                Game.GetWorkspotSystem():SendJumpToAnimEnt(player, pose_name, false)
            end)
            DAV.Cron.Halt(timer)
        end
    end)
end

function Player:StopPose()
    local player = Game.GetPlayer()
    if self.dummy_entity_id ~= nil then
        local dummy_entity = Game.FindEntityByID(self.dummy_entity_id)
        if dummy_entity ~= nil then
            Game.GetWorkspotSystem():StopInDevice(player)
            exEntitySpawner.Despawn(dummy_entity)
            self.dummy_entity_id = nil
        end
    end
end


return Player