local Utils = {}
Utils.__index = Utils

Utils.log_obj = Log:New()
Utils.log_obj:SetLevel(LogLevel.Info, "Utils")

READ_COUNT = 0
WRITE_COUNT = 0

--- Deep Copy a table.
---@param orig table
---@return table
function Utils:DeepCopy(orig)
   local orig_type = type(orig)
   local copy
   if orig_type == 'table' then
       copy = {}
       for orig_key, orig_value in next, orig, nil do
           copy[self:DeepCopy(orig_key)] = self:DeepCopy(orig_value)
       end
       setmetatable(copy, self:DeepCopy(getmetatable(orig)))
   else -- number, string, boolean, etc
       copy = orig
   end
   return copy
end

--- Check if two tables are equal.
---@param table1 table
---@param table2 table
---@return boolean
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

--- Get the key of the value in the table.
---@param table_ table
---@param target_value any
---@return any | nil
function Utils:GetKeyFromValue(table_, target_value)
   for key, value in pairs(table_) do
       if value == target_value then
           return key
       end
   end
   return nil
end

--- Get the keys of the table.
---@param table_ table
---@return table
function Utils:GetKeys(table_)
   local keys = {}
   for key, _ in pairs(table_) do
       table.insert(keys, key)
   end
   return keys
end

--- Scale the values in the list.
---@param list table
---@param rate number
---@return table
function Utils:ScaleListValues(list, rate)
   local list_ = {}
   for key, value in pairs(list) do
       list_[key] = value * rate
   end
   return list_
end

--- Wheather table2 elements are in table1.
---@param big_table table
---@param small_table table
---@return boolean
function Utils:IsTablesNearlyEqual(big_table, small_table)
   for key, value in pairs(small_table) do
      if value ~= big_table[key] then
         return false
      end
   end
   return true
end

--- Quaternion Multiply
---@param q1 table
---@param q2 table
---@return table
function Utils:QuaternionMultiply(q1, q2)
   local r = q1.r*q2.r - q1.i*q2.i - q1.j*q2.j - q1.k*q2.k
   local i = q1.r*q2.i + q1.i*q2.r + q1.j*q2.k - q1.k*q2.j
   local j = q1.r*q2.j - q1.i*q2.k + q1.j*q2.r + q1.k*q2.i
   local k = q1.r*q2.k + q1.i*q2.j - q1.j*q2.i + q1.k*q2.r
   return {r = r, i = i, j = j, k = k}
end

--- Quaternion Conjugate
---@param q table
---@return table
function Utils:QuaternionConjugate(q)
   return {r = q.r, i = -q.i, j = -q.j, k = -q.k}
end

--- Rotate Vector By Quaternion
---@param v table
---@param q table
---@return table
function Utils:RotateVectorByQuaternion(v, q)
   local q_conj = self:QuaternionConjugate(q)
   local temp = self:QuaternionMultiply({r = 0, i = v.x, j = v.y, k = v.z}, q_conj)
   local result = self:QuaternionMultiply(q, temp)
   return {x = result.i, y = result.j, z = result.k}
end

--- Read json file.
---@param fill_path string
---@return table | nil
function Utils:ReadJson(fill_path)
   READ_COUNT = READ_COUNT + 1
   local success, result = pcall(function()
      local file = io.open(fill_path, "r")
      if file then
         local contents = file:read("*a")
         local data = json.decode(contents)
         file:close()
         return data
      else
         self.log_obj:Record(LogLevel.Error, "Failed to open file for reading")
         return nil
      end
   end)
   if not success then
      self.log_obj:Record(LogLevel.Warning, result)
      return nil
   end
   return result
end

--- Write json file.
---@param fill_path string
---@param write_data table
---@return boolean
function Utils:WriteJson(fill_path, write_data)
   WRITE_COUNT = WRITE_COUNT + 1
   local success, result = pcall(function()
      local file = io.open(fill_path, "w")
      if file then
         local contents = json.encode(write_data)
         file:write(contents)
         file:close()
         return true
      else
         self.log_obj:Record(LogLevel.Error, "Failed to open file for writing")
         return false
      end
   end)
   if not success then
      self.log_obj:Record(LogLevel.Critical, result)
      return false
   end
   return result
end

--- Calculate rotational speed.
---@param local_roll number
---@param local_pitch number
---@param local_yaw number
---@param current_roll number
---@param current_pitch number
---@param current_yaw number
---@return number roll
---@return number pitch
---@return number yaw
function Utils:CalculateRotationalSpeed(local_roll, local_pitch, local_yaw, current_roll, current_pitch, current_yaw)
   local angle = {roll = current_roll, pitch = current_pitch, yaw = current_yaw}

   -- Convert Euler angles to radians
   local rad_roll = math.rad(angle.roll)
   local rad_pitch = math.rad(angle.pitch)
   local rad_yaw = math.rad(angle.yaw)
   local rad_local_roll = math.rad(local_roll)
   local rad_local_pitch = math.rad(local_pitch)
   local rad_local_yaw = math.rad(local_yaw)

   -- Calculate sin and cos
   local cos_roll, sin_roll = math.cos(rad_roll), math.sin(rad_roll)
   local cos_pitch, sin_pitch = math.cos(rad_pitch), math.sin(rad_pitch)
   local cos_yaw, sin_yaw = math.cos(rad_yaw), math.sin(rad_yaw)
   local cos_local_roll, sin_local_roll = math.cos(rad_local_roll), math.sin(rad_local_roll)
   local cos_local_pitch, sin_local_pitch = math.cos(rad_local_pitch), math.sin(rad_local_pitch)
   local cos_local_yaw, sin_local_yaw = math.cos(rad_local_yaw), math.sin(rad_local_yaw)

   -- Calculate rotation matrices
   local R1 = {
       {cos_roll * cos_pitch, cos_roll * sin_pitch * sin_yaw - sin_roll * cos_yaw, cos_roll * sin_pitch * cos_yaw + sin_roll * sin_yaw},
       {sin_roll * cos_pitch, sin_roll * sin_pitch * sin_yaw + cos_roll * cos_yaw, sin_roll * sin_pitch * cos_yaw - cos_roll * sin_yaw},
       {-sin_pitch, cos_pitch * sin_yaw, cos_pitch * cos_yaw}
   }

   local R2 = {
       {cos_local_roll * cos_local_pitch, cos_local_roll * sin_local_pitch * sin_local_yaw - sin_local_roll * cos_local_yaw, cos_local_roll * sin_local_pitch * cos_local_yaw + sin_local_roll * sin_local_yaw},
       {sin_local_roll * cos_local_pitch, sin_local_roll * sin_local_pitch * sin_local_yaw + cos_local_roll * cos_local_yaw, sin_local_roll * sin_local_pitch * cos_local_yaw - cos_local_roll * sin_local_yaw},
       {-sin_local_pitch, cos_local_pitch * sin_local_yaw, cos_local_pitch * cos_local_yaw}
   }

   -- Calculate composite rotation matrix
   local R = {}
   for i = 1, 3 do
       R[i] = {}
       for j = 1, 3 do
           R[i][j] = 0
           for k = 1, 3 do
               R[i][j] = R[i][j] + R1[i][k] * R2[k][j]
           end
       end
   end

   -- Calculate Euler angles from composite rotation matrix
   local new_roll = math.deg(math.atan2(R[2][1], R[1][1]))
   local new_pitch = math.deg(math.atan2(-R[3][1], math.sqrt(R[3][2] * R[3][2] + R[3][3] * R[3][3])))
   local new_yaw = math.deg(math.atan2(R[3][2], R[3][3]))

   return new_pitch - angle.pitch, new_roll - angle.roll, new_yaw - angle.yaw
end

--- Calculate rotational roll speed.
---@param local_roll number
---@param current_roll number
---@param current_pitch number
---@param current_yaw number
---@return number roll
---@return number pitch
---@return number yaw
function Utils:CalculateRotationalRollSpeed(local_roll, current_roll, current_pitch, current_yaw)
   local local_pitch, local_yaw = 0, 0
   local angle = {roll = current_roll, pitch = current_pitch, yaw = current_yaw}

   -- Convert Euler angles to radians
   local rad_roll = math.rad(angle.roll)
   local rad_pitch = math.rad(angle.pitch)
   local rad_yaw = math.rad(angle.yaw)
   local rad_local_roll = math.rad(local_roll)
   local rad_local_pitch = math.rad(local_pitch)
   local rad_local_yaw = math.rad(local_yaw)

   -- Calculate sin and cos
   local cos_roll, sin_roll = math.cos(rad_roll), math.sin(rad_roll)
   local cos_pitch, sin_pitch = math.cos(rad_pitch), math.sin(rad_pitch)
   local cos_yaw, sin_yaw = math.cos(rad_yaw), math.sin(rad_yaw)
   local cos_local_roll, sin_local_roll = math.cos(rad_local_roll), math.sin(rad_local_roll)
   local cos_local_pitch, sin_local_pitch = math.cos(rad_local_pitch), math.sin(rad_local_pitch)
   local cos_local_yaw, sin_local_yaw = math.cos(rad_local_yaw), math.sin(rad_local_yaw)

   -- Calculate rotation matrices
   local R1 = {
       {cos_roll * cos_pitch, cos_roll * sin_pitch * sin_yaw - sin_roll * cos_yaw, cos_roll * sin_pitch * cos_yaw + sin_roll * sin_yaw},
       {sin_roll * cos_pitch, sin_roll * sin_pitch * sin_yaw + cos_roll * cos_yaw, sin_roll * sin_pitch * cos_yaw - cos_roll * sin_yaw},
       {-sin_pitch, cos_pitch * sin_yaw, cos_pitch * cos_yaw}
   }

   local R2 = {
       {cos_local_roll * cos_local_pitch, cos_local_roll * sin_local_pitch * sin_local_yaw - sin_local_roll * cos_local_yaw, cos_local_roll * sin_local_pitch * cos_local_yaw + sin_local_roll * sin_local_yaw},
       {sin_local_roll * cos_local_pitch, sin_local_roll * sin_local_pitch * sin_local_yaw + cos_local_roll * cos_local_yaw, sin_local_roll * sin_local_pitch * cos_local_yaw - cos_local_roll * sin_local_yaw},
       {-sin_local_pitch, cos_local_pitch * sin_local_yaw, cos_local_pitch * cos_local_yaw}
   }

   -- Calculate composite rotation matrix
   local R = {}
   for i = 1, 3 do
       R[i] = {}
       for j = 1, 3 do
           R[i][j] = 0
           for k = 1, 3 do
               R[i][j] = R[i][j] + R1[i][k] * R2[k][j]
           end
       end
   end

   -- Calculate Euler angles from composite rotation matrix
   local new_roll = math.deg(math.atan2(R[2][1], R[1][1]))
   local new_pitch = math.deg(math.atan2(-R[3][1], math.sqrt(R[3][2] * R[3][2] + R[3][3] * R[3][3])))
   local new_yaw = math.deg(math.atan2(R[3][2], R[3][3]))

   return new_pitch - angle.pitch, new_roll - angle.roll, new_yaw - angle.yaw
end

return Utils