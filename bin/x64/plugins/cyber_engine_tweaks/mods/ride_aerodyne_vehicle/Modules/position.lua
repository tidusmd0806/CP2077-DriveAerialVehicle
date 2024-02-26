local Log = require("Modules/log.lua")
local Position = {}
Position.__index = Position

function Position:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Position")
    obj.unmount_vehicle_obj = nil
    obj.next_vehicle_vector = nil

    return setmetatable(obj, self)
end
function Position:GetUnmountVehicle()
    return self.unmount_vehicle_obj
end

function Position:SetUnmountVehicle(obj)
    self.unmount_vehicle_obj = obj
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
    if self.game_obj == nil then
        self.game_obj = Game['GetMountedVehicle;GameObject'](Game.GetPlayer()) or self.unmount_vehicle_obj
    end
    local pos = self.game_obj:GetWorldPosition()
    self.next_vehicle_vector = Vector4.new(pos.x + x, pos.y + y, pos.z + z, 1.0)
    if self:CheckVehicleCollision(pos, self.next_vehicle_vector) then
        self.log_obj:Record(LogLevel.Debug, "Collision Detected")
        self.next_vehicle_vector = Vector4.new(pos.x, pos.y, pos.z, 1.0)
        return false
    end
    local rot = self.game_obj:GetWorldOrientation():ToEulerAngles()
    self.next_vehicle_angle = EulerAngles.new(rot.roll + roll, rot.pitch + pitch, rot.yaw + yaw)
    return true
end

function Position:ChangeVehiclePosition()
    Game.GetTeleportationFacility():Teleport(self.game_obj, self.next_vehicle_vector, self.next_vehicle_angle)
end

function Position:CheckVehicleCollision(current_vector, next_vector)
    local filters = {'Static', 'Terrain'}
    for _, filter in ipairs(filters) do
        local success, result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_vector, next_vector, filter, false, false)
        if success then
            return true
        end
    end
    return false
end

return Position