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
    obj.volume_ajustment_resolution = 20
    obj.station_mapping =
    {
        [0] = 4,
        [1] = 0,
        [2] = 11,
        [3] = 10,
        [4] = 1,
        [5] = -1,
        [6] = 8,
        [7] = 6,
        [8] = 13,
        [9] = 2,
        [10] = 3,
        [11] = 7,
        [12] = 5,
        [13] = 12
    }
    -- station list --
    -- 1: 88.9 Pacific Dreams - 4
    -- 2: 89.3 Radio Vexelstrom - 0
    -- 3: 89.7 Growl FM - 11
    -- 4: 91.9 Royal Blue Radio - 10
    -- 5: 92.9 Night FM - 1
    -- 6: 95.2 Samizdat Radio - 9
    -- 7: 96.1 Ritual FM - 8
    -- 8: 98.7 Body Heat Radio - 6
    -- 9: 99.9 IMPULSE - 13
    -- 10: 101.9 The Dirge - 2
    -- 11: 103.5 Radio Pebkac - 3
    -- 12: 106.9 30 Principales  - 7
    -- 13: 107.3 Morro Rock Radio - 5
    -- 14: 107.5 Dark Star - 12
    ------------------
    -- dynamic --
    obj.radio_entity_list = {}
    obj.play_index = -1
    obj.volume = 0
    obj.is_playing = false
    obj.is_changing_volume = false
    return setmetatable(obj, self)
end

function Radio:Update(station_index, volume_str)

    self:SetVolumeFromString(volume_str)
    Cron.Every(DAV.time_resolution, {tick = 1} , function(timer)
        if self.volume == #self.radio_entity_list then
            self:Play(station_index)
            Cron.Halt(timer)
        end
    end)

end

function Radio:Spawn()

    self.log_obj:Record(LogLevel.Trace, "Radio Obj Create")
    local radio_transform = Transform.new()
    if self.position_obj == nil then
        self.log_obj:Record(LogLevel.Critical, "Position object is nil")
        return false
    end
    local av_pos = self.position_obj:GetPosition()
    radio_transform:SetPosition(av_pos)
    local radio_entity_id = exEntitySpawner.Spawn(self.radio_ent_path, radio_transform, '')
    Cron.Every(DAV.time_resolution, {tick = 1} , function(timer)
        local radio_entity = Game.FindEntityByID(radio_entity_id)
        if radio_entity ~= nil then
            local radio_controller_ps = radio_entity:GetDevicePS()
            radio_controller_ps.activeStation = self.play_index
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
    end

end

function Radio:Move()

    if #self.radio_entity_list == 0 then
        self.log_obj:Record(LogLevel.Trace, "Radio entity is nil in Move()")
        return false
    end
    for i = 1, #self.radio_entity_list do
        Game.GetTeleportationFacility():Teleport(self.radio_entity_list[i], self.position_obj:GetPosition(), EulerAngles.new(0, 0, 0))
    end
    return true

end

function Radio:GetPlayingStationIndex()
    return self.play_index
end

function Radio:Play(station_index)

    local actual_statiton_index = self.station_mapping[station_index]
    -- tmp
    if actual_statiton_index < 0 then
        repeat
            actual_statiton_index = math.random(0, 13)
        until actual_statiton_index ~= 9
    end

    self:Respawn()

    Cron.Every(DAV.time_resolution, {tick = 1} , function(timer)
        if #self.radio_entity_list == self.volume then
            self:SetStation()
            if self.is_playing then
                self.log_obj:Record(LogLevel.Trace, "Radio is already playing")
                return
            end
            self.play_index = actual_statiton_index
            Cron.Every(DAV.time_resolution, {tick = 1} , function(timer_in)
                self.is_playing = true
                for i = 1, #self.radio_entity_list do
                    self.radio_entity_list[i]:PlayGivenStation()
                end
                self:Move()
                if #self.radio_entity_list == 0 then
                    self.is_playing = false
                    Cron.Halt(timer_in)
                end
            end)
            Cron.Halt(timer)
        end
    end)

    return true

end

function Radio:SetStation()

    for i = 1, #self.radio_entity_list do
        local radio_controller_ps = self.radio_entity_list[i]:GetDevicePS()
        radio_controller_ps.activeStation = self.play_index
    end

end

function Radio:Stop()

    if #self.radio_entity_list ~= 0 then
        repeat
            self:Despawn()
        until #self.radio_entity_list == 0
    end
    self.volume = 0

end

function Radio:Respawn()

    local volume = self.volume
    if #self.radio_entity_list ~= 0 then
        repeat
            self:Despawn()
        until #self.radio_entity_list == 0
    end

    Cron.Every(DAV.time_resolution, {tick = 1} , function(timer)
        if #self.radio_entity_list ~= volume then
            for i = #self.radio_entity_list + 1, volume do
                self:Spawn()
            end
            Cron.Halt(timer)
        end
    end)

end

---@param volume_str string
function Radio:SetVolumeFromString(volume_str) -- volume_str: "Volume: 50%"

    local volume_num_string = string.gsub(volume_str, "%%", "")
    local volume_num = tonumber(volume_num_string)
    local volume = math.floor(volume_num / self.volume_ajustment_resolution) + 1
    if self.volume == volume then
        self.log_obj:Record(LogLevel.Trace, "Volume is already set")
        return
    end
    self:ChangeVolume(volume)

end

---@return number
function Radio:GetVolume()
    return self.volume
end

---@return boolean
function Radio:IsPlaying()
    return self.is_playing
end

---@param volume number
function Radio:ChangeVolume(volume)

    if self.is_changing_volume then
        self.log_obj:Record(LogLevel.Trace, "Volume is already changing")
        return
    end
    self.is_changing_volume = true
    if volume > self.volume then
        for i = 1, volume - self.volume do
            self:Spawn()
        end
    elseif volume < self.volume then
        for i = 1, self.volume - volume do
            self:Despawn()
        end
    end
    Cron.Every(DAV.time_resolution, {tick = 1} , function(timer)
        if #self.radio_entity_list == volume then
            self.volume = volume
            self.is_changing_volume = false
            Cron.Halt(timer)
        end
    end)

end

---@return CName | nil
function Radio:GetTrackName()

    if #self.radio_entity_list == 0 then
        self.log_obj:Record(LogLevel.Debug, "Radio entity is nil in GetTrackName()")
        return nil
    end
    local current_station_index = self:GetPlayingStationIndex()
    if current_station_index == -1 then
        self.log_obj:Record(LogLevel.Trace, "Radio is not playing any station")
        return nil
    end
    return GetRadioStationCurrentTrackName(RadioStationDataProvider.GetStationNameByIndex(current_station_index))

end

return Radio