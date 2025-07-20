local Queue = {}
Queue.__index = Queue

--- Constractor
---@return table
function Queue:New()
    local obj = {}
    obj._data = {}
    obj._front = 1
    obj._back = 0
    return setmetatable(obj, self)
end

--- Check if the queue is empty.
---@return boolean
function Queue:IsEmpty()
    return self._front > self._back
end

--- Get the size of the queue.
---@return number
function Queue:Size()
    return self._back - self._front + 1
end

--- Enqueue an element to the back of the queue.
---@param element any
function Queue:Enqueue(element)
    self._back = self._back + 1
    self._data[self._back] = element
end

--- Dequeue an element from the front of the queue.
---@return any
function Queue:Dequeue()
    if self:IsEmpty() then
        error("Queue is empty")
    end
    local element = self._data[self._front]
    self._data[self._front] = nil
    self._front = self._front + 1
    return element
end

--- Get the element at the front of the queue without removing it.
---@return any
function Queue:Front()
    if self:IsEmpty() then
        error("Queue is empty")
    end
    return self._data[self._front]
end

--- Clear the queue.
function Queue:Clear()
    self._data = {}
    self._front = 1
    self._back = 0
end

return Queue
