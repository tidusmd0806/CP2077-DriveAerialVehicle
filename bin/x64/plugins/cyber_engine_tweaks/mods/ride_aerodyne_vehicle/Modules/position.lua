local Log = require("Modules/log.lua")
local Position = {}
Position.__index = Position

function Position:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Position")
    obj.av_obj = nil
    obj.next_position = nil
    obj.next_angle = nil

    return setmetatable(obj, self)
end

function Position:SetEntityId(entity_id)
    self.av_obj = Game.FindEntityByID(entity_id)
end

function Position:GetPosition()
    return self.av_obj:GetWorldPosition()
end

function Position:GetEulerAngles()
    return self.av_obj:GetWorldOrientation():ToEulerAngles()
end

function Position:GetPlayerDirection(angle)
    return Vector4.RotateAxis(Game.GetPlayer():GetWorldForward(), Vector4.new(0, 0, 1, 0), angle / 180.0 * Pi())
end

function Position:GetSpawnPosition(distance, angle, high)
    local pos = Game.GetPlayer():GetWorldPosition()
    local heading = self:GetPlayerDirection(angle)
    return Vector4.new(pos.x + (heading.x * distance), pos.y + (heading.y * distance), pos.z + heading.z + high, pos.w + heading.w)
end

function Position:GetSpawnOrientation(angle)
    return EulerAngles.ToQuat(Vector4.ToRotation(self:GetPlayerDirection(angle)))
end

function Position:SetNextVehiclePosition(x, y, z, roll, pitch, yaw)
    local mount_obj = Game['GetMountedVehicle;GameObject'](Game.GetPlayer())
    if self.av_obj == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity")
        return false
    elseif mount_obj ~= nil then
        self.av_obj = mount_obj
    end
    local pos = self:GetPosition()
    self.next_position = Vector4.new(pos.x + x, pos.y + y, pos.z + z, 1.0)
    if self:CheckVehicleCollision(pos, self.next_position) then
        self.log_obj:Record(LogLevel.Debug, "Collision Detected")
        self.next_position = Vector4.new(pos.x, pos.y, pos.z, 1.0)
        return false
    end
    local rot = self:GetEulerAngles()
    self.next_angle = EulerAngles.new(rot.roll + roll, rot.pitch + pitch, rot.yaw + yaw)
    return true
end

function Position:ChangeVehiclePosition()
    Game.GetTeleportationFacility():Teleport(self.av_obj, self.next_position, self.next_angle)
end

function Position:CheckVehicleCollision(current_pos, next_pos)
    local filters = {'Static', 'Terrain'}
    for _, filter in ipairs(filters) do
        local success, result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_pos, next_pos, filter, false, false)
        if success then
            return true
        end
    end
    return false
end

return Position