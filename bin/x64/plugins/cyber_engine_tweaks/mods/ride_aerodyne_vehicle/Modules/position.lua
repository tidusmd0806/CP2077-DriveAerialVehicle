local Log = require("Modules/log.lua")
local Position = {}
Position.__index = Position

function Position:new()
    local obj = {}
    obj.log_obj = Log:new()
    obj.log_obj:setLevel(LogLevel.DEBUG, "Position")
    self.unmount_vehicle_obj = nil

    return setmetatable(obj, self)
end

function Position:getUnmountVehicle()
    return self.unmount_vehicle_obj
end

function Position:setUnmountVehicle(obj)
    self.unmount_vehicle_obj = obj
end

function Position:getPlayerDirection(angle)
    return Vector4.RotateAxis(Game.GetPlayer():GetWorldForward(), Vector4.new(0, 0, 1, 0), angle / 180.0 * Pi())
end

function Position:getSpawnPosition(distance, angle, high)
    local pos = Game.GetPlayer():GetWorldPosition()
    local heading = self:getPlayerDirection(angle)
    return Vector4.new(pos.x + (heading.x * distance), pos.y + (heading.y * distance), pos.z + heading.z + high, pos.w + heading.w)
end

function Position:getSpawnOrientation(angle)
    return EulerAngles.ToQuat(Vector4.ToRotation(self:getPlayerDirection(angle)))
end

function Position:setNextVehiclePosition(x, y, z, roll, pitch, yaw)
    if self.game_obj == nil then
        self.game_obj = Game['GetMountedVehicle;GameObject'](Game.GetPlayer()) or self.unmount_vehicle_obj
    end
    local pos = self.game_obj:GetWorldPosition()
    self.next_vehicle_vector = Vector4.new(pos.x + x, pos.y + y, pos.z + z, 1.0)
    if self:checkVehicleCollision(pos, self.next_vehicle_vector) then
        self.log_obj:record(LogLevel.DEBUG, "Collision Detected")
        self.next_vehicle_vector = Vector4.new(pos.x, pos.y, pos.z, 1.0)
        return false
    end
    local rot = self.game_obj:GetWorldOrientation():ToEulerAngles()
    self.next_vehicle_angle = EulerAngles.new(rot.roll + roll, rot.pitch + pitch, rot.yaw + yaw)
    return true
end

function Position:changeVehiclePosition()
    Game.GetTeleportationFacility():Teleport(self.game_obj, self.next_vehicle_vector, self.next_vehicle_angle)
end

function Position:checkVehicleCollision(current_vector, next_vector)
    local filters = {'Static', 'Terrain', 'Vehicle'}
    for _, filter in ipairs(filters) do
        local success, result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_vector, next_vector, filter, false, false)
        if success then
            return true
        end
    end
    return false
end

return Position
