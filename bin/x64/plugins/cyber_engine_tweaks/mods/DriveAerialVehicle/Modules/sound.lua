local Utils = require("Tools/utils")

local Sound = {}
Sound.__index = Sound

--- Constractor
--- @return table
function Sound:New()
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Sound")
    -- static --
    obj.av_audio_resource_model = "v_av_basilisk_tank"
    -- dynamic --
    obj.sound_data = {}
    obj.playing_sound = {}
    -- audio resource
    obj.av_audio_metadata = nil
    obj.basilisk_audio_general_data = nil
    return setmetatable(obj, self)
end

--- Initialize
function Sound:Init()
    self.sound_data = Utils:ReadJson("Data/sound.json")
    self.basilisk_audio_general_data = audioVehicleGeneralData.new()
    self.basilisk_audio_general_data.acoustingIsolationFactor = CName("veh_acoustic_isolation")
    self.basilisk_audio_general_data.dopplerShift = CName("doppler_shift")
    self.basilisk_audio_general_data.enterVehicleEvent = CName("v_av_panzer_01_enter")
    self.basilisk_audio_general_data.impactGridCellRawChange = CName("veh_grid_cell_raw_change")
    self.basilisk_audio_general_data.impactVelocity = CName("veh_collision_velocity")
    self.basilisk_audio_general_data.interiorReverbBus = CName("revb_indoor_car_nomad")
    local data_1 = audioVehicleInteriorParameterData.new()
    data_1.enterCurveTime = 3
    data_1.enterCurveType = CName("Linear")
    data_1.enterDelayTime = 2
    data_1.exitCurveTime = 3
    data_1.exitCurveType = CName("Linear")
    data_1.exitDelayTime = 2
    self.basilisk_audio_general_data.vehicleInteriorParameterData = data_1
    local data_2 = audioVehicleTemperatureSettings.new()
    data_2.cooldownTime = 30
    data_2.rpmThreshold = 3
    data_2.timeToActivateTemperature = 8
    self.basilisk_audio_general_data.vehicleTemperatureSettings = data_2
end

--- Exchange Sound Resource
function Sound:ChangeSoundResource()
    local depot = Game.GetResourceDepot()
    local token = depot:LoadResource("base\\sound\\metadata\\cooked_metadata.audio_metadata")
    local metadata_list = token:GetResource()
    local aerondight_audio_metadata
    for _, metadata in pairs(metadata_list.entries) do
        if metadata.name.value == self.av_audio_resource_model then
            self.av_audio_metadata = metadata
        end
        if metadata.name.value == "v_car_rayfield_aerondight" then
            aerondight_audio_metadata = metadata
        end
    end

    local general_data = audioVehicleGeneralData.new()

    general_data = aerondight_audio_metadata.generalData
    general_data.ignitionStartEvent = CName.new("None")
    general_data.ignitionEndEvent = CName.new("None")

    self.av_audio_metadata.collisionCooldown = 0.5
    self.av_audio_metadata.hasRadioReceiver = true
    self.av_audio_metadata.radioReceiverType = CName.new("radio_car_hyper_player")
    self.av_audio_metadata.vehicleCollisionSettings = CName.new("v_car_default_collision")
    self.av_audio_metadata.vehicleGridDestructionSettings = CName.new("v_grid_dst_car_default")
    self.av_audio_metadata.vehiclePartSettings = CName.new("v_car_damage_default")
    self.av_audio_metadata.generalData = general_data
end

--- Change Default Sound Resource
function Sound:ResetSoundResource()
    self.av_audio_metadata.generalData = self.basilisk_audio_general_data
    self.av_audio_metadata.collisionCooldown = 0.2
    self.av_audio_metadata.hasRadioReceiver = false
    self.av_audio_metadata.radioReceiverType = CName.new("radio_car")
    self.av_audio_metadata.vehicleCollisionSettings = CName.new("v_military_panzer_collision")
    self.av_audio_metadata.vehicleGridDestructionSettings = CName.new("None")
    self.av_audio_metadata.vehiclePartSettings = CName.new("None")
end

--- Play Sound
---@param sound_name string
function Sound:PlaySound(sound_name)
    -- Game.GetPlayer():PlaySoundEvent(self.sound_data[sound_name])
end

--- Stop Sound
---@param sound_name string
function Sound:StopSound(sound_name)
    Game.GetPlayer():StopSoundEvent(self.sound_data[sound_name])
end

--- Mute all sounds
function Sound:Mute()
    for _, sound_name in pairs(self.sound_data) do
        Game.GetPlayer():StopSoundEvent(sound_name)
    end
end

--- Get Identification Number of Sound
--- @param name string Sound Name
--- @return number | nil
function Sound:GetIdentificationNumber(name)
    local three_words = string.sub(name, 1, 3)
    return tonumber(three_words)
end

--- Mute pertial sounds
---@param num_min number
---@param num_max number
function Sound:PartialMute(num_min, num_max)
    for sound_id, sound_name in pairs(self.sound_data) do
        local num = self:GetIdentificationNumber(sound_id)
        if num >= num_min and num < num_max then
            Game.GetPlayer():StopSoundEvent(sound_name)
        end
    end
end

return Sound