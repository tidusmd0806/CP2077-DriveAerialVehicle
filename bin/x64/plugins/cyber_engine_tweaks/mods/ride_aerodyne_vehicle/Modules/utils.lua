local Utils = {}
Utils.__index = Util

function Utils:New()
    local obj = {}
    return setmetatable(obj, self)
end

function Utils:IsTablesAreEqual(table1, table2)
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

return Utils