local Utils = {}
Utils.__index = Utils

function Utils:New()
    local obj = {}
    return setmetatable(obj, self)
end

function Utils:IsTablesEqual(table1, table2)
    for key, value in pairs(table1) do
       if value ~= table2[key] then
          return false
       end
    end

    for key, value in pairs(table2) do
       if value ~= table1[key] then
          return false
       end
    end

    return true
end

function Utils:GetKeyFromValue(table_, target_value)
   for key, value in pairs(table_) do
       if value == target_value then
           return key
       end
   end
   return nil
end

function Utils:GetKeys(table_)
   local keys = {}
   for key, _ in pairs(table_) do
       table.insert(keys, key)
   end
   return keys
end

function Utils:Normalize(v)
   local norm = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
   v.x = v.x / norm
   v.y = v.y / norm
   v.z = v.z / norm
   return v
end

-- wheather table2 elements are in table1
function Utils:IsTablesNearlyEqual(big_table, small_table)
   for key, value in pairs(small_table) do
      if value ~= big_table[key] then
         return false
      end
   end
   return true
end

-- y = k(x - a)^2 + b and cross point is (0, c). Calculate Slope.
function Utils:CalculationQuadraticFuncSlope(a, b, c, x)
   return 2*(c - b)*(x - a)/(a * a)
end

function Utils:ChangePolarCoordinates(x, y, z)
   local r = math.sqrt(x*x + y*y + z*z)
   local theta = math.atan2(y, x) * 180 / Pi()
   local phi = math.acos(z / r) * 180 / Pi()
   return r, theta, phi
end

function Utils:QuaternionMultiply(q1, q2)
   local r = q1.r*q2.r - q1.i*q2.i - q1.j*q2.j - q1.k*q2.k
   local i = q1.r*q2.i + q1.i*q2.r + q1.j*q2.k - q1.k*q2.j
   local j = q1.r*q2.j - q1.i*q2.k + q1.j*q2.r + q1.k*q2.i
   local k = q1.r*q2.k + q1.i*q2.j - q1.j*q2.i + q1.k*q2.r
   return {r = r, i = i, j = j, k = k}
end

function Utils:QuaternionConjugate(q)
   return {r = q.r, i = -q.i, j = -q.j, k = -q.k}
end

function Utils:RotateVectorByQuaternion(v, q)
   local q_conj = self:QuaternionConjugate(q)
   local temp = self:QuaternionMultiply({r = 0, i = v.x, j = v.y, k = v.z}, q_conj)
   local result = self:QuaternionMultiply(q, temp)
   return {x = result.i, y = result.j, z = result.k}
end

function Utils:WorldToBodyCoordinates(world_coordinates, body_world_coordinates, body_quaternion)

   local relative_coordinates = {x = world_coordinates.x - body_world_coordinates.x, y = world_coordinates.y - body_world_coordinates.y, z = world_coordinates.z - body_world_coordinates.z}

   local q_conj = self:QuaternionConjugate(body_quaternion)

   local temp = self:QuaternionMultiply({r = 0, i = relative_coordinates.x, j = relative_coordinates.y, k = relative_coordinates.z}, q_conj)
   local result = self:QuaternionMultiply(body_quaternion, temp)

   return {x = result.i, y = result.j, z = result.k}
end

function Utils:ReadJson(fill_path)
   local file = io.open(fill_path, "r")
   if file then
      local contents = file:read( "*a" )
      local data = json.decode(contents)
      file:close()
      return data
   end
   self.log_obj:Record(LogLevel.Error, "Failed to read json file")
   return nil
end

function Utils:WriteJson(fill_path, write_data)
   local file = io.open(fill_path, "w")
   if file then
      local contents = json.encode(write_data)
      file:write(contents)
      file:close()
   end
 end

return Utils