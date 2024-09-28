local Utils = require("Tools/utils.lua")
local Debug = {}
Debug.__index = Debug

function Debug:New(core_obj)
    local obj = {}
    obj.core_obj = core_obj

    -- set parameters
    obj.is_set_observer = false
    obj.is_im_gui_rw_count = false
    obj.is_im_gui_input_check = false
    obj.is_im_gui_situation = false
    obj.is_im_gui_player_position = false
    obj.is_im_gui_av_position = false
    obj.is_im_gui_vehicle_info = false
    obj.is_im_gui_sound_check = false
    obj.selected_sound = "100_call_vehicle"
    obj.is_im_gui_mappin_position = false
    obj.is_im_gui_model_type_status = false
    obj.is_im_gui_auto_pilot_status = false
    obj.is_im_gui_change_auto_setting = false
    obj.is_im_gui_auto_pilot_info = false
    obj.is_im_gui_auto_pilot_exception_area = false
    obj.exception_area_entity_list = {}
    obj.spawn_lock = false
    obj.is_im_gui_measurement = false

    return setmetatable(obj, self)
end

function Debug:ImGuiMain()

    ImGui.Begin("DAV DEBUG WINDOW")
    ImGui.Text("Version : " .. DAV.version)

    self:SetObserver()
    self:SetLogLevel()
    self:SelectPrintDebug()
    self:ImGuiShowRWCount()
    self:ImGuiInputCheck()
    self:ImGuiSituation()
    self:ImGuiPlayerPosition()
    self:ImGuiAVPosition()
    self:ImGuiVehicleInfo()
    self:ImGuiSoundCheck()
    self:ImGuiModelTypeStatus()
    self:ImGuiMappinPosition()
    self:ImGuiAutoPilotStatus()
    self:ImGuiChangeAutoPilotSetting()
    self:ImGuiAutoPilotInfo()
    self:ImGuiAutoPilotExceptionArea()
    self:ImGuiMeasurement()
    self:ImGuiExcuteFunction()

    ImGui.End()

end

function Debug:SetObserver()

    if not self.is_set_observer then
        -- reserved
        Override("AIDriveCommandsDelegate", "DoStartDriveToPointAutonomous;ScriptExecutionContext", function(this, context, wrapped_method)
            -- method has just been called with:
            -- context: ScriptExecutionContext
            -- print("DoStartDriveToPointAutonomous")
            -- local def = AIbehaviorDriveToPointTreeNodeDefinition.new()
            -- local res = context:GetMappingValue(def.useTraffic)
            -- print(FromVariant(res))
            -- context:SetMappingValue(def.useTraffic, ToVariant(true, "Bool"))
            -- res = context:GetMappingValue(def.useTraffic)
            -- print(FromVariant(res))
            -- print(context:GetArgumentBool(CName.new("useTraffi")))
            -- context:SetArgumentBool(CName.new("useTraffi"), true)
            -- print(context:GetArgumentBool(CName.new("useTraffi")))
            -- local mapping = AIArgumentMapping.new()
            -- mapping.customTypeName = CName.new("Bool")
            -- mapping.defaultValue = ToVariant(CName.new("useTraffic"), "CName")
            -- mapping.parameterizationType = AIParameterizationType.Delegate
            -- mapping.prefixValue = nil
            -- mapping.type = AIArgumentType.Bool
            -- local val = context:GetMappingValue(mapping)
            -- print(FromVariant(val))
            -- context:SetMappingValue(mapping, ToVariant(true, "Bool"))
            -- val = context:GetMappingValue(mapping)
            -- print(FromVariant(val))
            -- local mapping_2 = AIArgumentMapping.new()
            -- mapping_2.customTypeName = CName.new("Float")
            -- mapping_2.defaultValue = ToVariant(CName.new("speedInTraffic"), "CName")
            -- mapping_2.parameterizationType = AIParameterizationType.Delegate
            -- mapping_2.prefixValue = nil
            -- mapping_2.type = AIArgumentType.Float
            -- local val_2 = context:GetMappingValue(mapping_2)
            -- print(FromVariant(val_2))
            -- context:SetMappingValue(mapping_2, ToVariant(10, "Float"))
            -- val_2 = context:GetMappingValue(mapping_2)
            -- print(FromVariant(val_2))
            -- print(this.useTraffic)
            -- local mapping_3 = AIArgumentMapping.new()
            -- mapping_3.customTypeName = CName.new("Bool")
            -- mapping_3.defaultValue = ToVariant(CName.new("forceGreenLights"), "CName")
            -- mapping_3.parameterizationType = AIParameterizationType.Delegate
            -- mapping_3.prefixValue = nil
            -- mapping_3.type = AIArgumentType.Bool
            -- local val_3 = context:GetMappingValue(mapping_3)
            -- print(FromVariant(val_3))
            -- context:SetMappingValue(mapping_3, ToVariant(false, "Bool"))
            -- val_3 = context:GetMappingValue(mapping_3)
            -- print(FromVariant(val_3))
            -- local mapping_4 = AIArgumentMapping.new()
            -- mapping_4.customTypeName = CName.new("Float")
            -- mapping_4.defaultValue = ToVariant(CName.new("secureTimeOut"), "CName")
            -- mapping_4.parameterizationType = AIParameterizationType.Delegate
            -- mapping_4.prefixValue = nil
            -- mapping_4.type = AIArgumentType.Float
            -- local val_4 = context:GetMappingValue(mapping_4)
            -- print(FromVariant(val_4))
            -- context:SetMappingValue(mapping_4, ToVariant(1200, "Float"))
            -- val_4 = context:GetMappingValue(mapping_4)
            -- print(FromVariant(val_4))
            -- this.secureTimeOut = 1200
            -- this.useTraffic = true
            -- this.forceGreenLights = false
            -- this.speedInTraffic = 30
            -- this.targetPosition = Vector3.new(-59.85, -88.02, 6.97)
            -- this.portals = vehiclePortalsList
            -- this.trafficTryNeighborsForStart = false
            -- this.trafficTryNeighborsForEnd = false
            -- print(this.useTraffic)
            -- print(this.forceGreenLights)
            -- print(this.speedInTraffic)
            return wrapped_method(context)
        end)

        Override("AIDriveCommandsDelegate", "DoUpdateDriveToPointAutonomous", function(this, context, wrapped_method)
            -- rewrite method with:
            -- this: AIDriveCommandsDelegate
            -- context: ScriptExecutionContext
            -- print("DoUpdateDriveToPointAutonomous")
            -- print(this.useTraffic)
            -- print(context:GetArgumentBool("useTraffic"))
            -- print(this.forceGreenLights)
            -- print(this.speedInTraffic)
            -- this.secureTimeOut = 1200
            -- this.useTraffic = true
            -- this.forceGreenLights = false
            -- this.speedInTraffic = 30
            -- this.targetPosition = Vector3.new(-59.85, -88.02, 6.97)
            -- -- this.portals = vehiclePortalsList
            -- this.trafficTryNeighborsForStart = false
            -- this.trafficTryNeighborsForEnd = false
            -- print(this.useTraffic)
            -- print(this.forceGreenLights)
            -- print(this.speedInTraffic)
            -- local mapping = AIArgumentMapping.new()
            -- mapping.customTypeName = CName.new("Bool")
            -- mapping.defaultValue = ToVariant(CName.new("useTraffic"), "CName")
            -- mapping.parameterizationType = AIParameterizationType.Delegate
            -- mapping.prefixValue = nil
            -- mapping.type = AIArgumentType.Bool
            -- local val = context:GetMappingValue(mapping)
            -- print(FromVariant(val))
            -- context:SetMappingValue(mapping, ToVariant(true, "Bool"))
            -- val = context:GetMappingValue(mapping)
            -- print(FromVariant(val))
            -- local def = AIbehaviorDriveToPointTreeNodeDefinition.new()
            -- local res = context:GetMappingValue(def.useTraffic)
            -- print(FromVariant(res))
            -- context:SetMappingValue(def.useTraffic, ToVariant(true, "Bool"))
            -- res = context:GetMappingValue(def.useTraffic)
            -- print(FromVariant(res))
            return wrapped_method(context)
        end)

        -- Observe("ScriptExecutionContext", "SetArgumentBool", function(context, entry, value)
        --     -- method has just been called with:
        --     -- context: ScriptExecutionContext
        --     -- entry: CName
        --     -- value: Bool
        --     print("SetArgumentBool")
        --     print(entry)
        --     print(value)
        -- end)

        -- Override("AIDriveCommandsDelegate", "DoStartDriveToPoint;ScriptExecutionContext", function(this, context, wrapped_method)
        --     -- method has just been called with:
        --     -- this: AIDriveCommandsDelegate
        --     -- context: ScriptExecutionContext
        --     print("DoStartDriveToPoint")
        --     return wrapped_method(context)
        -- end)

        -- Observe("PlayerPuppet", "QueueEvent", function(this, evt)
        --     -- method has just been called with:
        --     -- this: Entity
        --     -- evt: ref<Event>
        --     if evt:ToString() == "gamemountingUnmountingEvent" then
        --         print("UnmountingEvent")
        --         print(evt.request.mountData.entryAnimName)
        --     end
        -- end)
        
        Observe("ExitFromVehicle", "Activate", function(this, context)
            -- method has just been called with:
            -- this: ExitFromVehicle
            -- context: ScriptExecutionContext
            print("Activate")
        end)
        

    end
    self.is_set_observer = true

    if self.is_set_observer then
        ImGui.Text("Observer : On")
    end

end

function Debug:SetLogLevel()
    local selected = false
    if ImGui.BeginCombo("LogLevel", Utils:GetKeyFromValue(LogLevel, MasterLogLevel)) then
		for _, key in ipairs(Utils:GetKeys(LogLevel)) do
			if Utils:GetKeyFromValue(LogLevel, MasterLogLevel) == key then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable(key, selected)) then
				MasterLogLevel = LogLevel[key]
			end
		end
		ImGui.EndCombo()
	end
end

function Debug:SelectPrintDebug()
    PrintDebugMode = ImGui.Checkbox("Print Debug Mode", PrintDebugMode)
end

function Debug:ImGuiShowRWCount()
    self.is_im_gui_rw_count = ImGui.Checkbox("[ImGui] R/W Count", self.is_im_gui_rw_count)
    if self.is_im_gui_rw_count then
        ImGui.Text("Read : " .. READ_COUNT .. ", Write : " .. WRITE_COUNT)
    end
end

function Debug:ImGuiInputCheck()
    self.is_im_gui_input_check = ImGui.Checkbox("[ImGui] Input Check", self.is_im_gui_input_check)
    if self.is_im_gui_input_check then
        if DAV.is_keyboard_input then
            ImGui.Text("Keyboard : On")
        else
            ImGui.Text("Keyboard : Off")
        end
    end
end

function Debug:ImGuiSituation()
    self.is_im_gui_situation = ImGui.Checkbox("[ImGui] Current Situation", self.is_im_gui_situation)
    if self.is_im_gui_situation then
        ImGui.Text("Current Situation : " .. self.core_obj.event_obj.current_situation)
    end
end

function Debug:ImGuiPlayerPosition()
    self.is_im_gui_player_position = ImGui.Checkbox("[ImGui] Player Position Angle", self.is_im_gui_player_position)
    if self.is_im_gui_player_position then
        local x = string.format("%.2f", Game.GetPlayer():GetWorldPosition().x)
        local y = string.format("%.2f", Game.GetPlayer():GetWorldPosition().y)
        local z = string.format("%.2f", Game.GetPlayer():GetWorldPosition().z)
        ImGui.Text("[world]X:" .. x .. ", Y:" .. y .. ", Z:" .. z)
        local roll = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().roll)
        local pitch = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().pitch)
        local yaw = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().yaw)
        ImGui.Text("[world]Roll:" .. roll .. ", Pitch:" .. pitch .. ", Yaw:" .. yaw)
    end
end

function Debug:ImGuiAVPosition()
    self.is_im_gui_av_position = ImGui.Checkbox("[ImGui] AV Position Angle", self.is_im_gui_av_position)
    if self.is_im_gui_av_position then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local x = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().x)
        local y = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().y)
        local z = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().z)
        local roll = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().roll)
        local pitch = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().pitch)
        local yaw = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().yaw)
        ImGui.Text("X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
        ImGui.Text("Roll:" .. roll .. ", Pitch:" .. pitch .. ", Yaw:" .. yaw)
        ImGui.Text("Height : " .. tostring(DAV.core_obj.av_obj.position_obj:GetHeight()))
    end
end

function Debug:ImGuiVehicleInfo()
    self.is_im_gui_vehicle_info = ImGui.Checkbox("[ImGui] Vehicle Info", self.is_im_gui_vehicle_info)
    if self.is_im_gui_vehicle_info then
        if DAV.core_obj.av_obj == nil then
            return
        end
        if DAV.core_obj.av_obj:IsDestroyed() then
            ImGui.Text("Vehicle : Destroyed")
        else
            ImGui.Text("Vehicle : Alive")
        end
        local left_door_state = DAV.core_obj.av_obj:GetDoorState(EVehicleDoor.seat_front_left)
        local right_door_state = DAV.core_obj.av_obj:GetDoorState(EVehicleDoor.seat_front_right)
        ImGui.Text("Door State : " .. tostring(left_door_state) .. ", ")
        ImGui.Text(tostring(right_door_state))
        local lock_list = DAV.core_obj.av_obj.door_input_lock_list
        ImGui.Text("Door Input Lock : " .. tostring(lock_list["seat_front_left"]) .. ", " .. tostring(lock_list["seat_front_right"]))
        if DAV.core_obj.av_obj.engine_obj.fly_av_system == nil then
            return
        end
        if DAV.core_obj.av_obj.engine_obj.fly_av_system:IsOnGround() then
            ImGui.Text("On Ground")
        else
            ImGui.Text("In Air")
        end
        ImGui.Text("Phy State: " .. tostring(DAV.core_obj.av_obj.engine_obj.fly_av_system:GetPhysicsState()))
        if DAV.core_obj.av_obj.engine_obj.fly_av_system:HasGravity() then
            ImGui.Text("Gravity : On")
        else
            ImGui.Text("Gravity : Off")
        end
        local speed = DAV.core_obj.av_obj.engine_obj.fly_av_system:GetVelocity()
        local speed_x = string.format("%.2f", speed.x)
        local speed_y = string.format("%.2f", speed.y)
        local speed_z = string.format("%.2f", speed.z)
        ImGui.Text("Speed : X:" .. speed_x .. ", Y:" .. speed_y .. ", Z:" .. speed_z)

    end
end

function Debug:ImGuiSoundCheck()
    self.is_im_gui_sound_check = ImGui.Checkbox("[ImGui] Sound Check", self.is_im_gui_sound_check)
    if self.is_im_gui_sound_check then
        if ImGui.BeginCombo("##Sound List", self.selected_sound) then
            for key, _ in pairs(self.core_obj.event_obj.sound_obj.sound_data) do
                if (ImGui.Selectable(key, (self.selected_sound==key))) then
                    self.selected_sound = key
                end
            end
            ImGui.EndCombo()
        end

        if ImGui.Button("Play", 150, 60) then
            self.core_obj.event_obj.sound_obj:PlaySound(self.selected_sound)
        end

        if ImGui.Button("Stop", 150, 60) then
            self.core_obj.event_obj.sound_obj:StopSound(self.selected_sound)
        end
    end
end

function Debug:ImGuiModelTypeStatus()
    self.is_im_gui_model_type_status = ImGui.Checkbox("[ImGui] Model Index Status", self.is_im_gui_model_type_status)
    if self.is_im_gui_model_type_status then
        local model_index = DAV.model_index
        local model_type_index = DAV.model_type_index
        ImGui.Text("Model Index : " .. model_index .. ", Model Type Index : " .. model_type_index)
        local garage_info_list = DAV.user_setting_table.garage_info_list
        for _, value in pairs(garage_info_list) do
            ImGui.Text("name : " .. value.name .. ", model_index : " .. value.model_index .. ", model_type_index : " .. value.type_index .. ", is_unlocked : " .. tostring(value.is_purchased))
        end
    end
end

function Debug:ImGuiMappinPosition()
    self.is_im_gui_mappin_position = ImGui.Checkbox("[ImGui] Custom Mappin Position", self.is_im_gui_mappin_position)
    if self.is_im_gui_mappin_position then
        local x = string.format("%.2f", self.core_obj.current_custom_mappin_position.x)
        local y = string.format("%.2f", self.core_obj.current_custom_mappin_position.y)
        local z = string.format("%.2f", self.core_obj.current_custom_mappin_position.z)
        ImGui.Text("X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
        if DAV.core_obj.is_custom_mappin then
            ImGui.Text("Custom Mappin : On")
        else
            ImGui.Text("Custom Mappin : Off")
        end
    end
end

function Debug:ImGuiAutoPilotStatus()
    self.is_im_gui_auto_pilot_status = ImGui.Checkbox("[ImGui] Auto Pilot Status", self.is_im_gui_auto_pilot_status)
    if self.is_im_gui_auto_pilot_status then
        ImGui.Text("FT Index near mappin : " .. tostring(DAV.core_obj.ft_index_nearest_mappin))
        ImGui.Text("FT Index near favorite : " .. tostring(DAV.core_obj.ft_index_nearest_favorite))
        local selected_history_index = DAV.core_obj.event_obj.ui_obj.selected_auto_pilot_history_index
        ImGui.Text("Selected History Index : " .. selected_history_index)
        ImGui.Text("-----History-----")
        local mappin_history = DAV.user_setting_table.mappin_history
        if #mappin_history ~= 0 then
            for i, value in ipairs(mappin_history) do
                ImGui.Text("[" .. i .. "] : " .. value.district[1])
                ImGui.SameLine()
                ImGui.Text("/ " .. value.location)
                ImGui.SameLine()
                ImGui.Text("/ " .. value.distance)
                if value.position ~= nil then
                    ImGui.Text("[" .. i .. "] : " .. value.position.x .. ", " .. value.position.y .. ", " .. value.position.z)
                else
                    ImGui.Text("[" .. i .. "] : nil")
                end
            end
        else
            ImGui.Text("No History")
        end
        local selected_favorite_index = DAV.core_obj.event_obj.ui_obj.selected_auto_pilot_history_index
        ImGui.Text("Selected Favorite Index : " .. selected_favorite_index)
        ImGui.Text("------Favorite Location------")
        local favorite_location_list = DAV.user_setting_table.favorite_location_list
        for i, value in ipairs(favorite_location_list) do
            ImGui.Text("[" .. i .. "] : " .. value.name)
            if value.pos ~= nil then
                ImGui.Text("[" .. i .. "] : " .. value.pos.x .. ", " .. value.pos.y .. ", " .. value.pos.z)
            else
                ImGui.Text("[" .. i .. "] : nil")
            end
        end
    end
end

function Debug:ImGuiChangeAutoPilotSetting()
    self.is_im_gui_change_auto_setting = ImGui.Checkbox("[ImGui] Change AP Profile", self.is_im_gui_change_auto_setting)
    if self.is_im_gui_change_auto_setting then
        if ImGui.Button("Update Profile") then
            DAV.core_obj.av_obj.autopilot_profile = Utils:ReadJson(DAV.core_obj.av_obj.profile_path)
            DAV.core_obj.av_obj:ReloadAutopilotProfile()
        end
        ImGui.Text("Level : " .. DAV.user_setting_table.autopilot_speed_level)
        ImGui.Text("Speed : " .. DAV.core_obj.av_obj.autopilot_speed .. ", Search Range : " .. DAV.core_obj.av_obj.autopilot_searching_range .. ", Search Step : " .. DAV.core_obj.av_obj.autopilot_searching_step)
        ImGui.Text("Increase Speed : " .. DAV.core_obj.av_obj.autopilot_increase_rate .. ", Decrease Speed : " .. DAV.core_obj.av_obj.autopilot_decrease_rate .. ", Min Speed Rate : " .. DAV.core_obj.av_obj.autopilot_min_speed_rate)
        ImGui.Text("Turn Speed : " .. DAV.core_obj.av_obj.autopilot_turn_speed .. ", Land Offset : " .. DAV.core_obj.av_obj.autopilot_land_offset .. ", Down Count : " .. DAV.core_obj.av_obj.autopilot_down_time_count)
        ImGui.Text("Leaving Height : " .. DAV.core_obj.av_obj.autopilot_leaving_height .. ", Only Horizontal : " .. tostring(DAV.core_obj.av_obj.autopilot_is_only_horizontal))
    end
end

function Debug:ImGuiAutoPilotInfo()
    self.is_im_gui_auto_pilot_info = ImGui.Checkbox("[ImGui] Auto Pilot Info", self.is_im_gui_auto_pilot_info)
    if self.is_im_gui_auto_pilot_info then
        ImGui.Text("Angle : " .. tostring(DAV.core_obj.av_obj.autopilot_angle) .. ", H Sign : " .. tostring(DAV.core_obj.av_obj.autopilot_horizontal_sign) .. ", V Sign : " .. tostring(DAV.core_obj.av_obj.autopilot_vertical_sign))
        ImGui.Text("Current Speed : " .. DAV.core_obj.av_obj.autopilot_speed * DAV.core_obj.av_obj.auto_speed_reduce_rate .. ", Serach Range : " .. DAV.core_obj.av_obj.search_range)
        ImGui.Text("Destination Destance 2D : " .. DAV.core_obj.av_obj.dest_dir_vector_norm)
    end
end

function Debug:ImGuiAutoPilotExceptionArea()
    self.is_im_gui_auto_pilot_exception_area = ImGui.Checkbox("[ImGui] Auto Pilot Exception Area", self.is_im_gui_auto_pilot_exception_area)
    if self.is_im_gui_auto_pilot_exception_area and #self.exception_area_entity_list == 0 and not self.spawn_lock then
        self.spawn_lock = true
        local entity_path = "base\\gameplay\\devices\\advertising\\digital\\entropy\\entropy_digital_billboard_1x3_3_b.ent"
        local entity_id = nil
        local entity = nil
        local entity_spawn_lock = false
        local positions = {}
        local position_index = 1
        local position_count = 1
        for _, value in ipairs(DAV.core_obj.av_obj.position_obj.autopilot_exception_area_list) do
            local position = {
                {value.min_x, value.min_y, value.min_z},
                {value.max_x, value.min_y, value.min_z},
                {value.min_x, value.max_y, value.min_z},
                {value.max_x, value.max_y, value.min_z},
                {value.min_x, value.min_y, value.max_z},
                {value.max_x, value.min_y, value.max_z},
                {value.min_x, value.max_y, value.max_z},
                {value.max_x, value.max_y, value.max_z}
            }
            table.insert(positions, position)
        end
        Cron.Every(0.01, {tick=1}, function(timer)
            if position_index > #positions then
                self.spawn_lock = false
                Cron.Halt(timer)
            elseif not entity_spawn_lock then
                local transform = WorldTransform.new()
                local pos = WorldPosition.new()
                entity_spawn_lock = true
                pos:SetXYZ(table.unpack(positions[position_index][position_count]))
                transform.Position = pos
                entity_id = exEntitySpawner.Spawn(entity_path, transform, '')
            elseif entity_id ~= nil then
                entity = Game.FindEntityByID(entity_id)
                if entity ~= nil then
                    table.insert(self.exception_area_entity_list, entity)
                    position_count = position_count + 1
                    if position_count > 8 then
                        position_index = position_index + 1
                        position_count = 1
                    end
                    entity_spawn_lock = false
                end
            end
        end)
    elseif not self.is_im_gui_auto_pilot_exception_area and #self.exception_area_entity_list ~= 0 and not self.spawn_lock then
        self.spawn_lock = true
        for _, value in ipairs(self.exception_area_entity_list) do
            exEntitySpawner.Despawn(value)
        end
        self.exception_area_entity_list = {}
        Cron.After(3, function()
            self.spawn_lock = false
        end)
    end
    if self.is_im_gui_auto_pilot_exception_area then
        local current_position = Game.GetPlayer():GetWorldPosition()
        local res, tag, z = DAV.core_obj.av_obj.position_obj:IsInExceptionArea(current_position)
        if res then
            ImGui.Text("In Exception Area : " .. tag .. ", Z : " .. z)
        else
            ImGui.Text("Not In Exception Area")
        end
        if ImGui.Button("Reload Area") then
            DAV.core_obj.av_obj.position_obj.autopilot_exception_area_list = Utils:ReadJson(DAV.core_obj.av_obj.position_obj.exception_area_path)
        end
    end
end

function Debug:ImGuiMeasurement()
    self.is_im_gui_measurement = ImGui.Checkbox("[ImGui] Measurement", self.is_im_gui_measurement)
    if self.is_im_gui_measurement then
        local look_at_pos = Game.GetTargetingSystem():GetLookAtPosition(Game.GetPlayer())
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local origin = self.core_obj.av_obj.position_obj:GetPosition()
        local right = self.core_obj.av_obj.position_obj.entity:GetWorldRight()
        local forward = self.core_obj.av_obj.position_obj.entity:GetWorldForward()
        local up = self.core_obj.av_obj.position_obj.entity:GetWorldUp()
        local relative = Vector4.new(look_at_pos.x - origin.x, look_at_pos.y - origin.y, look_at_pos.z - origin.z, 1)
        local x = Vector4.Dot(relative, right)
        local y = Vector4.Dot(relative, forward)
        local z = Vector4.Dot(relative, up)
        local absolute_position_x = string.format("%.2f", x)
        local absolute_position_y = string.format("%.2f", y)
        local absolute_position_z = string.format("%.2f", z)
        ImGui.Text("[LookAt]X:" .. absolute_position_x .. ", Y:" .. absolute_position_y .. ", Z:" .. absolute_position_z)
    end
end

function Debug:ImGuiExcuteFunction()
    if ImGui.Button("TF1") then
        print("Force Unmount Test")
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local player = Game.GetPlayer()
        local ent_id = entity:GetEntityID()
        local seat = DAV.core_obj.av_obj.active_seat[1]

        local data = NewObject('handle:gameMountEventData')
        data.isInstant = true
        data.slotName = seat
        data.mountParentEntityId = ent_id
        data.entryAnimName = "forcedTransition"

        local slotID = NewObject('gamemountingMountingSlotId')
        slotID.id = seat

        local mounting_info = NewObject('gamemountingMountingInfo')
        mounting_info.childId = player:GetEntityID()
        mounting_info.parentId = ent_id
        mounting_info.slotId = slotID

        local mount_event = NewObject('handle:gamemountingUnmountingRequest')
        mount_event.lowLevelMountingInfo = mounting_info
        mount_event.mountData = data

        Game.GetMountingFacility():Unmount(mount_event)
        print("Excute Test Function 1")
    end
    ImGui.SameLine()
    if ImGui.Button("TF2") then
        Cron.Every(1, {tick=1}, function(timer)
            timer.tick = timer.tick + 1
            if DAV.core_obj.av_obj.engine_obj.fly_av_system:IsOnGround() then
                if DAV.core_obj.av_obj.engine_obj.flight_mode == Def.FlightMode.AV then
                    DAV.core_obj.av_obj:Operate({Def.ActionList.Down})
                else
                    DAV.core_obj.av_obj:Operate({Def.ActionList.HDown})
                end
            end
            if timer.tick > 10 then
                Cron.Halt(timer)
            end
        end)
        print("Excute Test Function 2")
    end
    ImGui.SameLine()
    if ImGui.Button("TF3") then
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local door_event = VehicleDoorOpen.new()
        local door_name = "trunk"
		local vehicle_ps = entity:GetVehiclePS()
        door_event.slotID = CName.new(door_name)
        door_event.forceScene = false
        vehicle_ps:QueuePSEvent(vehicle_ps, door_event)
        print("Excute Test Function 3")
    end
    ImGui.SameLine()
    if ImGui.Button("TF4-0") then
        TweakDB:SetFlat(TweakDBID.new("Vehicle.v_mahir_mt28_coach.entityTemplatePath"), "base\\vehicles\\special\\v_mahir_mt28_coach_basic_02.ent")
        print("Excute Test Function 4")
    end
    ImGui.SameLine()
    if ImGui.Button("TF4") then
        local entity_system = Game.GetDynamicEntitySystem()
        local entity_spec = DynamicEntitySpec.new()
        local pos = Game.GetPlayer():GetWorldPosition()
        pos.x = pos.x + 5
        local rot = Game.GetPlayer():GetWorldOrientation()

        -- entity_spec.recordID = "Vehicle.v_mahir_mt28_coach"
        entity_spec.recordID = "Vehicle.cs_savable_mahir_mt28_coach"
        entity_spec.appearanceName = "mahir_mt28_basic_coach_01"
        entity_spec.position = pos
        entity_spec.orientation = rot
        entity_spec.persistState = false
        entity_spec.persistSpawn = false
        self.entity_id = entity_system:CreateEntity(entity_spec)
        print("Excute Test Function 4")
    end

    ImGui.SameLine()
    if ImGui.Button("TF5") then
        local entity = Game.FindEntityByID(self.entity_id)
        local player = Game.GetPlayer()
        local ent_id = entity:GetEntityID()
        local seat = "seat_front_right"

        local data = NewObject('handle:gameMountEventData')
        data.isInstant = false
        data.slotName = seat
        data.mountParentEntityId = ent_id
        data.entryAnimName = "forcedTransition"


        local slot_id = NewObject('gamemountingMountingSlotId')
        slot_id.id = seat

        local mounting_info = NewObject('gamemountingMountingInfo')
        mounting_info.childId = player:GetEntityID()
        mounting_info.parentId = ent_id
        mounting_info.slotId = slot_id

        local mounting_request = NewObject('handle:gamemountingMountingRequest')
        mounting_request.lowLevelMountingInfo = mounting_info
        mounting_request.mountData = data

        Game.GetMountingFacility():Mount(mounting_request)

        print("Excute Test Function 5")
    end
    ImGui.SameLine()
    if ImGui.Button("TF5-2") then
        -- local entity = Game.FindEntityByID(self.entity_id)
        local player = Game.GetPlayer()
        local vehicle = player:GetMountedVehicle()
        local ent_id = vehicle:GetEntityID()
        -- local ent_id = player:GetMountedVehicle():GetEntityID()
        local seat = "seat_front_right"

        local data = gameMountEventData.new()
        data.isInstant = false
        data.slotName = seat
        data.mountParentEntityId = ent_id
        -- data.entryAnimName = "forcedTransition"
        data.mountEventOptions = NewObject('handle:gameMountEventOptions')
        data.mountEventOptions.silentUnmount = false
        data.mountEventOptions.entityID = ent_id
        data.mountEventOptions.alive = true
        data.mountEventOptions.occupiedByNeutral = true
        data.setEntityVisibleWhenMountFinish = true
        data.removePitchRollRotationOnDismount = false
        data.ignoreHLS = false

        local slot_id = NewObject('gamemountingMountingSlotId')
        slot_id.id = seat

        local mounting_info = NewObject('gamemountingMountingInfo')
        mounting_info.childId = player:GetEntityID()
        mounting_info.parentId = ent_id
        mounting_info.slotId = slot_id

        local mounting_request = NewObject('handle:gamemountingUnmountingRequest')
        mounting_request.lowLevelMountingInfo = mounting_info
        mounting_request.mountData = data

        Game.GetMountingFacility():Unmount(mounting_request)
        -- Game.GetWorkspotSystem():UnmountFromVehicle(vehicle, player, false, "default")
        -- Game.GetWorkspotSystem():SendFastExitSignal(player, true, true)
        -- local evt = VehicleStartedMountingEvent.new()
        -- evt.slotID = seat
        -- evt.isMounting = false
        -- evt.character = player
        -- vehicle:QueueEvent(evt)
        -- local door = VehicleExternalDoorRequestEvent.new()
        -- door.slotName = vehicle:GetBoneNameFromSlot(seat)
        -- door.autoClose = true
        -- vehicle:QueueEvent(door)

        print("Excute Test Function 5")
    end
    ImGui.SameLine()
    if ImGui.Button("TF5-3") then
        local entity = Game.FindEntityByID(self.entity_id)
        local vehicle_ps = entity:GetVehiclePS()
        vehicle_ps:DisableAllVehInteractions()

        print("Excute Test Function 5")
    end
    ImGui.SameLine()
    if ImGui.Button("TF6") then
        local entity = Game.FindEntityByID(self.entity_id)
        local vehicle_ps = entity:GetVehiclePS()
        local door_name = "seat_front_right"
        local event = nil
        if vehicle_ps:GetDoorState(EVehicleDoor.seat_front_right) == VehicleDoorState.Closed then
            event = VehicleDoorOpen.new()
        elseif vehicle_ps:GetDoorState(EVehicleDoor.seat_front_right) == VehicleDoorState.Open then
            event = VehicleDoorClose.new()
        end
        event.slotID = CName.new(door_name)
        event.forceScene = false
        vehicle_ps:QueuePSEvent(vehicle_ps, event)

        print("Excute Test Function 6")
    end
    if ImGui.Button("TF7") then
        local player = Game.GetPlayer()
        local player_pos = player:GetWorldPosition()
        -- local npcs = player:GetNPCsAroundObject()
        local moveCmd = AIMoveToCommand.new()
        local positionSpec = AIPositionSpec.new()
        local worldPosition = WorldPosition.new()
	    worldPosition:SetVector4(player_pos)
        positionSpec:SetWorldPosition(worldPosition)
        local movementType = moveMovementType.Run
        local targetDistance = 1.0
        moveCmd.movementTarget = positionSpec
        moveCmd.movementType = movementType
        moveCmd.desiredDistanceFromTarget = targetDistance
        moveCmd.finishWhenDestinationReached = true
        moveCmd.ignoreNavigation = true
        moveCmd.useStart = true
        moveCmd.useStop = false
        -- if #npcs > 0 then
        --     local min_distance = 100
        --     local min_index = 0
        --     for index, npc in ipairs(npcs) do
        --         local npc_pos = npc:GetWorldPosition()
        --         local distnce = Vector4.Distance(player_pos, npc_pos)
        --         if distnce < min_distance then
        --             min_distance = distnce
        --             min_index = index
        --         end
        --     end
        --     print("Distance : " .. min_distance)
        --     print("Index : " .. min_index)
        --     print(npcs[min_index]:GetAIControllerComponent():SendCommand(moveCmd))
        -- end
        local npc = Game.FindEntityByID(self.man_id)
        npc:GetAIControllerComponent():SendCommand(moveCmd)

        print("Excute Test Function 7")
    end
    ImGui.SameLine()
    if ImGui.Button("TF8") then
        local entitySystem = Game.GetDynamicEntitySystem()
        local npcSpec = DynamicEntitySpec.new()
        local pos = Game.GetPlayer():GetWorldPosition()
        pos.x = pos.x + 3
        npcSpec.recordID = "Character.DefaultNCResidentMale"
        npcSpec.appearanceName = "random"
        npcSpec.position = pos
        npcSpec.persistState = true
        npcSpec.persistSpawn = true
        npcSpec.alwaysSpawned = true
        self.man_id = entitySystem:CreateEntity(npcSpec)
        print("Excute Test Function 8")
    end
    ImGui.SameLine()
    if ImGui.Button("TF9") then
        -- local entity = Game.FindEntityByID(self.entity_id)
        -- local comp = entity:GetVehicleComponent()
        -- comp:MountEntityToSlot(self.entity_id, self.man_id, "seat_back_right")
        local entity = Game.FindEntityByID(self.entity_id)
        local player = Game.FindEntityByID(self.man_id)
        local ent_id = entity:GetEntityID()
        local seat = "seat_back_right"

        local mountData = MountEventData.new()
        mountData.mountParentEntityId = self.entity_id
        mountData.isInstant = false
        mountData.setEntityVisibleWhenMountFinish = true
        mountData.removePitchRollRotationOnDismount = false
        mountData.ignoreHLS = false
        mountData.mountEventOptions = NewObject('handle:gameMountEventOptions')
        mountData.mountEventOptions.silentUnmount = false
        mountData.mountEventOptions.entityID = self.entity_id
        mountData.mountEventOptions.alive = true
        mountData.mountEventOptions.occupiedByNeutral = true
        mountData.slotName = seat
        local cmd = AIMountCommand.new()
        cmd.mountData = mountData
        player:GetAIControllerComponent():SendCommand(cmd)
        print("Excute Test Function 9")
    end
    ImGui.SameLine()
    if ImGui.Button("TF9-2") then
        -- local entity = Game.FindEntityByID(self.entity_id)
        -- local comp = entity:GetVehicleComponent()
        -- comp:MountEntityToSlot(self.entity_id, self.man_id, "seat_back_right")
        local entity = Game.FindEntityByID(self.entity_id)
        local player = Game.FindEntityByID(self.man_id)
        local ent_id = entity:GetEntityID()
        local seat = "seat_back_right"

        local mountData = MountEventData.new()
        mountData.mountParentEntityId = self.entity_id
        mountData.isInstant = false
        mountData.setEntityVisibleWhenMountFinish = true
        mountData.removePitchRollRotationOnDismount = false
        mountData.ignoreHLS = false
        mountData.mountEventOptions = NewObject('handle:gameMountEventOptions')
        mountData.mountEventOptions.silentUnmount = false
        mountData.mountEventOptions.entityID = self.entity_id
        mountData.mountEventOptions.alive = true
        mountData.mountEventOptions.occupiedByNeutral = true
        mountData.slotName = seat
        local cmd = AIUnmountCommand.new()
        cmd.mountData = mountData
        player:GetAIControllerComponent():SendCommand(cmd)
        print("Excute Test Function 9")
    end
    ImGui.SameLine()
    if ImGui.Button("TF10") then
        local entity = Game.FindEntityByID(self.entity_id)
        local player = Game.FindEntityByID(self.man_id)
        local ent_id = entity:GetEntityID()
        local seat = "seat_back_right"

        local data = NewObject('handle:gameMountEventData')
        data.isInstant = true
        data.slotName = seat
        data.mountParentEntityId = ent_id
        data.entryAnimName = "UpdateWorkspot"

        local slotID = NewObject('gamemountingMountingSlotId')
        slotID.id = seat

        local mounting_info = NewObject('gamemountingMountingInfo')
        mounting_info.childId = player:GetEntityID()
        mounting_info.parentId = ent_id
        mounting_info.slotId = slotID

        local mount_event = NewObject('handle:gamemountingUnmountingRequest')
        mount_event.lowLevelMountingInfo = mounting_info
        mount_event.mountData = data

		Game.GetMountingFacility():Unmount(mount_event)
        print("Excute Test Function 10")
    end
    ImGui.SameLine()
    if ImGui.Button("TF11") then
        local vehicle = Game.GetPlayer():GetMountedVehicle()
        local ai = vehicle:GetAIComponent()
        local evt = AICommandEvent.new()
        local cmd = AIVehicleDriveToPointAutonomousCommand.new()
        local player_pos = Game.GetPlayer():GetWorldPosition()
        cmd.targetPosition = Vector3.new(-59.27, -88.02, 6.97)
        cmd.driveDownTheRoadIndefinitely = false
        cmd.clearTrafficOnPath = true
        cmd.minimumDistanceToTarget = 0
        cmd.maxSpeed = 10
        cmd.minSpeed = 5
        -- local cmd = AIVehicleJoinTrafficCommand.new()
        evt.command = cmd
        -- local evt = vehicleDriveToPointEvent.new()
        -- evt.speedInTraffic = 30
        -- evt.targetPos = Vector3.new(-59.85, -88.02, 6.97)
        -- evt.useTraffic = true
        -- local evt = JoinTrafficVehicleEvent.new()
        vehicle:QueueEvent(evt)
        ai:SetInitCmd(cmd)
        print("Excute Test Function 11")
    end
    ImGui.SameLine()
    if ImGui.Button("TF12") then
        local vehicle = Game.GetPlayer():GetMountedVehicle()
        local ai = vehicle:GetAIComponent()
        local evt = AICommandEvent.new()
        -- local cmd = AIVehicleDriveToPointCommand.new()
        -- local player_pos = Game.GetPlayer():GetWorldPosition()
        -- cmd.targetPosition = Vector3.new(-59.85, -88.02, 6.97)
        -- cmd.secureTimeOut = 1200
        -- cmd.useTraffic = true
        -- cmd.forceGreenLights = false
        -- cmd.speedInTraffic = 30
        -- cmd.trafficTryNeighborsForStart = false
        -- cmd.trafficTryNeighborsForEnd = false
        -- evt.command = cmd
        -- vehicle:QueueEvent(evt)
        -- ai:SetInitCmd(cmd)
        local evt_t = vehicleJoinTrafficVehicleEvent.new()
        local cmd = AIVehicleJoinTrafficCommand.new()
        evt.command = cmd
        vehicle:QueueEvent(evt_t)
        -- ai:SetInitCmd(cmd)

        -- vehicle:ForceBrakesFor(1)

        print("Excute Test Function 12")
    end

    ImGui.SameLine()
    if ImGui.Button("TF13") then
        local vehicle = Game.GetPlayer():GetMountedVehicle()
        -- local ai = vehicle:GetAIComponent()
        -- local evt = AICommandEvent.new()
        -- -- local cmd = AIVehicleDriveToPointCommand.new()
        -- -- local player_pos = Game.GetPlayer():GetWorldPosition()
        -- -- cmd.targetPosition = Vector3.new(-59.85, -88.02, 6.97)
        -- -- cmd.secureTimeOut = 1200
        -- -- cmd.useTraffic = true
        -- -- cmd.forceGreenLights = false
        -- -- cmd.speedInTraffic = 30
        -- -- cmd.trafficTryNeighborsForStart = false
        -- -- cmd.trafficTryNeighborsForEnd = false
        -- -- evt.command = cmd
        -- -- vehicle:QueueEvent(evt)
        -- -- ai:SetInitCmd(cmd)
        -- local cmd = AIVehicleJoinTrafficCommand.new()
        -- cmd.state = AICommandState.Interrupted
        -- evt.command = cmd
        -- -- local evt_t = AIVehicleDisabledEvent.new()
        -- -- vehicle:QueueEvent(evt_t)
        -- vehicle:QueueEvent(evt)
        -- ai:CancelCommand(cmd)
        -- ai:StopExecutingCommand(cmd,true)

        local horn = VehicleQuestDelayedHornEvent.new()
        horn.honkTime = 1
        horn.delayTime = 0
        vehicle:QueueEvent(horn);

        -- vehicle:ForceBrakesFor(1)

        print("Excute Test Function 13")
    end
end

return Debug
