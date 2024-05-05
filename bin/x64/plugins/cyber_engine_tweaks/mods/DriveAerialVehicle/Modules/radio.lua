local Radio = {}
Radio.__index = Radio

function Radio:New(position_obj)
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Radio")
    obj.position_obj = position_obj
    -- sttatic --
    obj.radio_ent_path = "base\\quest\\main_quests\\prologue\\q000\\entities\\q000_invisible_radio.ent"
    -- dynamic --
    obj.radio_entity_list = {}
    obj.volume = 0
    return setmetatable(obj, self)
end

function Radio:Spawn()

    self.volume = self.volume + 1

    self.log_obj:Record(LogLevel.Trace, "Radio Obj Create")
    local radio_transform = Transform.new()
    if self.position_obj == nil then
        self.log_obj:Record(LogLevel.Critical, "Position object is nil")
        return false
    end
    local av_pos = self.position_obj:GetPosition()
    radio_transform:SetPosition(av_pos)
    local radio_entity_id = exEntitySpawner.Spawn(self.radio_ent_path, radio_transform, '')
    Cron.Every(0.01, {tick = 1} , function(timer)
        local radio_entity = Game.FindEntityByID(radio_entity_id)
        if radio_entity ~= nil then
            table.insert(self.radio_entity_list, radio_entity)
            Cron.Halt(timer)
        end
    end)
    return true

end

function Radio:Despawn()

    self.log_obj:Record(LogLevel.Trace, "Radio Obj Destroy")
    if #self.radio_entity_list ~= 0 then
        exEntitySpawner.Despawn(self.radio_entity_list[#self.radio_entity_list])
        table.remove(self.radio_entity_list)
        self.volume = self.volume - 1
    end

end

function Radio:Move()

    if #self.radio_entity_list == 0 then
        self.log_obj:Record(LogLevel.Error, "Radio entity is nil")
        return false
    end
    for i = 1, #self.radio_entity_list do
        Game.GetTeleportationFacility():Teleport(self.radio_entity_list[i], self.position_obj:GetPosition(), EulerAngles.new(0, 0, 0))
    end
    return true

end

function Radio:GetActiveStationIndex()

    local radio_controller_ps = self.radio_entity_list[1]:GetDevicePS()
    if radio_controller_ps ~= nil then
        return radio_controller_ps:GetActiveStationIndex()
    else
        self.log_obj:Record(LogLevel.Error, "Radio controller is nil")
        return -1
    end

end

function Radio:Play(station_index)

    if #self.radio_entity_list == 0 then
        self.log_obj:Record(LogLevel.Info, "Radio entity is empty, so spawn it")
        self:Spawn()
    end
    Cron.Every(0.01, {tick = 1} , function(timer)
        if #self.radio_entity_list == self.volume then
            local current_station_index = self:GetActiveStationIndex()
            if current_station_index == station_index then
                self.log_obj:Record(LogLevel.Info, "Radio is already playing the station")
            elseif current_station_index == -1 then
                self.log_obj:Record(LogLevel.Error, "Radio is not playing any station")
                return false
            else
                for i = 1, #self.radio_entity_list do
                    self.radio_entity_list[i].activeStation = station_index
                    self.radio_entity_list[i]:PlayGivenStation()
                end
            end
            Cron.Every(DAV.time_resolution, {tick = 1} , function(timer_in)
                self:Move()
                if #self.radio_entity_list == 0 then
                    Cron.Halt(timer_in)
                end
            end)
            Cron.Halt(timer)
        end
    end)

end

function Radio:Stop()

    if #self.radio_entity_list == 0 then
        self.log_obj:Record(LogLevel.Error, "Radio entity is nil")
        return false
    end

    repeat
        self:Despawn()
    until #self.radio_entity_list == 0

    return true

end

---@return CName | nil
function Radio:GetTrackName()

    if #self.radio_entity_list == 0 then
        self.log_obj:Record(LogLevel.Error, "Radio entity is nil")
        return nil
    end
    local radio_controller_ps = self.radio_entity_list[1]:GetDevicePS()
    if radio_controller_ps == nil then
        self.log_obj:Record(LogLevel.Error, "Radio controller is nil")
        return nil
    end
    local current_station_index = self:GetActiveStationIndex()
    if current_station_index == -1 then
        self.log_obj:Record(LogLevel.Error, "Radio is not playing any station")
        return nil
    end
    return GetRadioStationCurrentTrackName(RadioStationDataProvider.GetStationNameByIndex(current_station_index))

end

return Radio