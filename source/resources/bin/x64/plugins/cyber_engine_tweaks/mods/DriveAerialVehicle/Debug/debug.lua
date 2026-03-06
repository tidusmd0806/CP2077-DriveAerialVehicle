local Utils = require("Etc/utils.lua")
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
    obj.is_im_gui_engine_info = false
    obj.is_im_gui_sound_check = false
    obj.is_im_gui_mappin_position = false
    obj.is_im_gui_model_type_status = false
    obj.is_im_gui_auto_pilot_info = false
    obj.is_im_gui_obstacle_map = false
    obj.selected_sound = "100_call_vehicle"
    obj.fade_time = 1.5
    obj.manual_block_points = {}
    obj.manual_block_marker_entities = {}
    obj.last_manual_block_result = ""
    obj.last_manual_block_ok = nil

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
    self:ImGuiEngineInfo()
    self:ImGuiSoundCheck()
    self:ImGuiModelTypeStatus()
    self:ImGuiMappinPosition()
    self:ImGuiAutoPilotInfo()
    self:ImGuiObstacleMap()
    self:ImGuiExcuteFunction()

    ImGui.End()

end

function Debug:ClearManualBlockMarkers()
    for _, entity in ipairs(self.manual_block_marker_entities) do
        exEntitySpawner.Despawn(entity)
    end
    self.manual_block_marker_entities = {}
end

function Debug:SpawnManualBlockMarkerAt(position)
    if not position then return end
    local entity_path = "ep1\\worlds\\03_night_city\\sectors\\c_pacifica\\combat_zone\\container_zone\\loc_q305_bunker\\loc_q305_bunker_lighting\\device\\bunker_storage_ceiling_lamp.ent"
    local transform = WorldTransform.new()
    local pos = WorldPosition.new()
    pos:SetXYZ(position.x, position.y, position.z)
    transform.Position = pos

    local entity_id = exEntitySpawner.Spawn(entity_path, transform, '')
    if entity_id == nil then return end

    Cron.Every(0.01, {tick = 1}, function(timer)
        local entity = Game.FindEntityByID(entity_id)
        if entity ~= nil then
            table.insert(self.manual_block_marker_entities, entity)
            Cron.Halt(timer)
            return
        end
        timer.tick = timer.tick + 1
        if timer.tick > 300 then
            Cron.Halt(timer)
        end
    end)
end

function Debug:RefreshManualBlockMarkers()
    self:ClearManualBlockMarkers()
    for i = 1, 8 do
        local p = self.manual_block_points[i]
        if p and p.pos then
            self:SpawnManualBlockMarkerAt(p.pos)
        end
    end
end

function Debug:RecordManualBlockPoint(index)
    local av_obj = self.core_obj and self.core_obj.av_obj
    local nav = av_obj and av_obj.navigation_obj
    if not nav then
        self.last_manual_block_ok = false
        self.last_manual_block_result = "Navigation object is not available"
        return
    end

    local player = Game.GetPlayer()
    if not player then
        self.last_manual_block_ok = false
        self.last_manual_block_result = "Player is not available"
        return
    end

    local pos = player:GetWorldPosition()
    local key = nav:PositionToSectorKey(pos)
    if not key then
        self.last_manual_block_ok = false
        self.last_manual_block_result = "Failed to detect current sector"
        return
    end

    local center = nav:SectorKeyToPosition(key)
    if not center then
        self.last_manual_block_ok = false
        self.last_manual_block_result = "Failed to resolve sector center"
        return
    end

    self.manual_block_points[index] = { key = key, pos = center }
    self:RefreshManualBlockMarkers()
    self.last_manual_block_ok = true
    self.last_manual_block_result = string.format("P%d recorded: %s", index, key)
end

function Debug:ResetManualBlockPoints()
    self.manual_block_points = {}
    self:ClearManualBlockMarkers()
end

function Debug:CreateManualBlockHexahedron()
    local av_obj = self.core_obj and self.core_obj.av_obj
    local nav = av_obj and av_obj.navigation_obj
    if not nav then
        self.last_manual_block_ok = false
        self.last_manual_block_result = "Navigation object is not available"
        return
    end

    for i = 1, 8 do
        if not self.manual_block_points[i] then
            self.last_manual_block_ok = false
            self.last_manual_block_result = "Record all 8 points first"
            return
        end
    end

    local ok, msg = nav:CreateObstacleConvexHexahedronFromPoints(self.manual_block_points)
    self.last_manual_block_ok = ok
    self.last_manual_block_result = msg or ""
    if ok then
        self:ResetManualBlockPoints()
    end
end

function Debug:SetObserver()

    if not self.is_set_observer then
        -- reserved
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
        if self.core_obj.event_obj.hud_obj.is_keyboard_input then
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
        local is_in_menu_or_popup_photo = self.core_obj.event_obj:IsInMenuOrPopupOrPhoto()
        if is_in_menu_or_popup_photo then
            ImGui.Text("In Menu or Popup or Photo : On")
        else
            ImGui.Text("In Menu or Popup or Photo : Off")
        end
    end
end

function Debug:ImGuiPlayerPosition()
    self.is_im_gui_player_position = ImGui.Checkbox("[ImGui] Player Position And Angle", self.is_im_gui_player_position)
    if self.is_im_gui_player_position then
        local x = string.format("%.2f", Game.GetPlayer():GetWorldPosition().x)
        local y = string.format("%.2f", Game.GetPlayer():GetWorldPosition().y)
        local z = string.format("%.2f", Game.GetPlayer():GetWorldPosition().z)
        ImGui.Text("[world]X:" .. x .. ", Y:" .. y .. ", Z:" .. z)
        local roll = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().roll)
        local pitch = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().pitch)
        local yaw = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().yaw)
        ImGui.Text("[world]Roll:" .. roll .. ", Pitch:" .. pitch .. ", Yaw:" .. yaw)
        -- Calculate distance between player and AV
        local av_obj = self.core_obj.av_obj
        if av_obj and av_obj.GetPosition then
            local player_pos = Game.GetPlayer():GetWorldPosition()
            local av_pos = av_obj:GetPosition()
            if player_pos and av_pos then
                local dx = player_pos.x - av_pos.x
                local dy = player_pos.y - av_pos.y
                local dz = player_pos.z - av_pos.z
                local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                ImGui.Text(string.format("Distance to AV: %.2f m", distance))
            else
                ImGui.Text("Distance to AV: N/A")
            end
        else
            ImGui.Text("Distance to AV: N/A")
        end
    end
end

function Debug:ImGuiAVPosition()
    self.is_im_gui_av_position = ImGui.Checkbox("[ImGui] AV Position Angle", self.is_im_gui_av_position)
    if self.is_im_gui_av_position then
        local entity = Game.FindEntityByID(self.core_obj.av_obj.entity_id)
        if entity == nil then
            return
        end
        local x = string.format("%.2f", self.core_obj.av_obj:GetPosition().x)
        local y = string.format("%.2f", self.core_obj.av_obj:GetPosition().y)
        local z = string.format("%.2f", self.core_obj.av_obj:GetPosition().z)
        local roll = string.format("%.2f", self.core_obj.av_obj:GetEulerAngles().roll)
        local pitch = string.format("%.2f", self.core_obj.av_obj:GetEulerAngles().pitch)
        local yaw = string.format("%.2f", self.core_obj.av_obj:GetEulerAngles().yaw)
        ImGui.Text("X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
        ImGui.Text("Roll:" .. roll .. ", Pitch:" .. pitch .. ", Yaw:" .. yaw)
        ImGui.Text("Height : " .. tostring(DAV.core_obj.av_obj.navigation_obj:GetHeight()))
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
        if DAV.core_obj.av_obj:IsEngineOn() then
            ImGui.Text("Engine : On")
        else
            ImGui.Text("Engine : Off")
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
        if DAV.core_obj.av_obj.engine_obj:IsOnGround() then
            ImGui.Text("On Ground")
        else
            ImGui.Text("In Air")
        end
        ImGui.Text("Phy State: " .. tostring(self.core_obj.av_obj.engine_obj:GetPhysicsState()))
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
        local angular_velocity = DAV.core_obj.av_obj.engine_obj.fly_av_system:GetAngularVelocity()
        local angular_velocity_x = string.format("%.2f", angular_velocity.x)
        local angular_velocity_y = string.format("%.2f", angular_velocity.y)
        local angular_velocity_z = string.format("%.2f", angular_velocity.z)
        ImGui.Text("Angular Velocity : X:" .. angular_velocity_x .. ", Y:" .. angular_velocity_y .. ", Z:" .. angular_velocity_z)
    end
end

function Debug:ImGuiEngineInfo()
    self.is_im_gui_engine_info = ImGui.Checkbox("[ImGui] Engine Info", self.is_im_gui_engine_info)
    if self.is_im_gui_engine_info then
        if DAV.core_obj.av_obj == nil then
            return
        end
        local engine_obj = self.core_obj.av_obj.engine_obj
        if engine_obj.fly_av_system == nil then
            return
        end
        local force = engine_obj.force
        local torque = engine_obj.torque
        local direction_velocity = engine_obj.direction_velocity
        local angular_velocity = engine_obj.angular_velocity
        local control_type = engine_obj.engine_control_type
        ImGui.Text("Force : X:" .. force.x .. ", Y:" .. force.y .. ", Z:" .. force.z)
        ImGui.Text("Torque : X:" .. torque.x .. ", Y:" .. torque.y .. ", Z:" .. torque.z)
        ImGui.Text("Direction Velocity : X:" .. direction_velocity.x .. ", Y:" .. direction_velocity.y .. ", Z:" .. direction_velocity.z)
        ImGui.Text("Angular Velocity : X:" .. angular_velocity.x .. ", Y:" .. angular_velocity.y .. ", Z:" .. angular_velocity.z)
        ImGui.Text("Control Type : " .. control_type)
    end
end

function Debug:ImGuiSoundCheck()
    self.is_im_gui_sound_check = ImGui.Checkbox("[ImGui] Sound Check", self.is_im_gui_sound_check)
    if self.is_im_gui_sound_check then
        if ImGui.BeginCombo("##Sound List", self.selected_sound) then
            for key, _ in pairs(self.core_obj.event_obj.sound_obj.game_sound_data) do
                if (ImGui.Selectable(key, (self.selected_sound==key))) then
                    self.selected_sound = key
                end
            end
            ImGui.EndCombo()
        end

        if ImGui.Button("Play", 150, 60) then
            self.core_obj.event_obj.sound_obj:PlayGameSound(self.selected_sound)
        end
        ImGui.SameLine()
        if ImGui.Button("Stop", 150, 60) then
            self.core_obj.event_obj.sound_obj:StopGameSound(self.selected_sound)
        end
        ImGui.Text("Engine Sound")
        local fade_time, _ = ImGui.InputFloat("Fade time", self.fade_time)
        self.fade_time = fade_time
        if ImGui.Button("Idle Start", 150, 60) then
            if self.core_obj.av_obj.flight_mode == Def.FlightMode.AV then
                self.core_obj.event_obj.sound_obj:StartEngineSound(Def.FlightMode.AV, fade_time)
            elseif self.core_obj.av_obj.flight_mode == Def.FlightMode.Helicopter then
                self.core_obj.event_obj.sound_obj:StartEngineSound(Def.FlightMode.Helicopter, fade_time)
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Idle Stop", 150, 60) then
            if self.core_obj.av_obj.flight_mode == Def.FlightMode.AV then
                self.core_obj.event_obj.sound_obj:StopEngineSound(Def.FlightMode.AV, fade_time)
            elseif self.core_obj.av_obj.flight_mode == Def.FlightMode.Helicopter then
                self.core_obj.event_obj.sound_obj:StopEngineSound(Def.FlightMode.Helicopter, fade_time)
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Acceleration start", 150, 60) then
            if self.core_obj.av_obj.flight_mode == Def.FlightMode.AV then
                self.core_obj.event_obj.sound_obj:StartAccelerationSound(Def.FlightMode.AV, fade_time)
            elseif self.core_obj.av_obj.flight_mode == Def.FlightMode.Helicopter then
                self.core_obj.event_obj.sound_obj:StartAccelerationSound(Def.FlightMode.Helicopter, fade_time)
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Acceleration stop", 150, 60) then
            if self.core_obj.av_obj.flight_mode == Def.FlightMode.AV then
                self.core_obj.event_obj.sound_obj:StopAccelerationSound(Def.FlightMode.AV, fade_time)
            elseif self.core_obj.av_obj.flight_mode == Def.FlightMode.Helicopter then
                self.core_obj.event_obj.sound_obj:StopAccelerationSound(Def.FlightMode.Helicopter, fade_time)
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Thruster Start", 150, 60) then
            if self.core_obj.av_obj.flight_mode == Def.FlightMode.AV then
                -- reserve
            elseif self.core_obj.av_obj.flight_mode == Def.FlightMode.Helicopter then
                self.core_obj.event_obj.sound_obj:StartThrusterSound(Def.FlightMode.Helicopter, fade_time)
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Thruster Stop", 150, 60) then
            if self.core_obj.av_obj.flight_mode == Def.FlightMode.AV then
                -- reserve
            elseif self.core_obj.av_obj.flight_mode == Def.FlightMode.Helicopter then
                self.core_obj.event_obj.sound_obj:StopThrusterSound(Def.FlightMode.Helicopter, fade_time)
            end
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

function Debug:ImGuiAutoPilotInfo()
    self.is_im_gui_auto_pilot_info = ImGui.Checkbox("[ImGui] Auto Pilot Info", self.is_im_gui_auto_pilot_info)
    if not self.is_im_gui_auto_pilot_info then return end

    local av_obj = self.core_obj.av_obj
    if not av_obj then
        ImGui.Text("AV object not available")
        return
    end

    local function table_count(t)
        if type(t) ~= "table" then return 0 end
        local n = 0
        for _, _ in pairs(t) do
            n = n + 1
        end
        return n
    end

    local function format_vec3(v)
        if not v then return "nil" end
        return string.format("(%.1f, %.1f, %.1f)", v.x or 0, v.y or 0, v.z or 0)
    end

    local phase = tostring(av_obj.autopilot_phase or "unknown")
    local route_len = (type(av_obj.current_global_route) == "table") and #av_obj.current_global_route or 0
    local route_idx = tonumber(av_obj.current_route_index) or 0
    local route_wp_key = "-"
    if route_len > 0 and route_idx >= 1 and route_idx <= route_len then
        route_wp_key = tostring(av_obj.current_global_route[route_idx])
    end

    ImGui.Text("=== Auto Pilot Runtime ===")
    ImGui.Text("Active: " .. tostring(av_obj.is_auto_pilot))
    ImGui.Text("Phase: " .. phase)
    ImGui.Text("Dest Unknown Sector: " .. tostring(av_obj.autopilot_dest_is_unknown))
    ImGui.Text("Exception Bypass Active: " .. tostring(av_obj.is_exception_area_bypassed))
    if av_obj.is_deadend_escape_active then
        ImGui.TextColored(1, 0.6, 0.0, 1.0, "Dead-end Escape: ACTIVE")
    else
        ImGui.TextColored(0.0, 1.0, 0.0, 1.0, "Dead-end Escape: inactive")
    end

    ImGui.Separator()
    ImGui.Text("=== Route / Target ===")
    ImGui.Text(string.format("Route Progress: %d / %d", route_idx, route_len))
    ImGui.Text("Current Waypoint Key: " .. route_wp_key)
    ImGui.Text("A* Partial Route: " .. tostring(av_obj.astar_is_partial_route))
    ImGui.Text("Local Target: " .. format_vec3(av_obj.autopilot_local_target))
    ImGui.Text("Distance to Nav Target: " .. string.format("%.1f m", tonumber(av_obj.dest_dir_vector_norm) or 0))
    ImGui.Text("Distance to Final Dest: " .. string.format("%.1f m", tonumber(av_obj.dest_remaining_to_final) or 0))

    ImGui.Separator()
    ImGui.Text("=== Movement / Control ===")
    ImGui.Text("Autopilot Speed: " .. string.format("%.2f", tonumber(av_obj.autopilot_speed) or 0))
    ImGui.Text("Speed Reduce Rate: " .. string.format("%.2f", tonumber(av_obj.auto_speed_reduce_rate) or 0))
    ImGui.Text("Effective Speed: " .. string.format("%.2f", (tonumber(av_obj.autopilot_speed) or 0) * (tonumber(av_obj.auto_speed_reduce_rate) or 0)))
    ImGui.Text("Search Range: " .. string.format("%.2f / %.2f", tonumber(av_obj.search_range) or 0, tonumber(av_obj.autopilot_searching_range) or 0))
    ImGui.Text("Auto Angle: " .. tostring(av_obj.autopilot_angle) .. " deg")
    ImGui.Text("H Sign / V Sign: " .. tostring(av_obj.autopilot_horizontal_sign) .. " / " .. tostring(av_obj.autopilot_vertical_sign))

    ImGui.Separator()
    ImGui.Text("=== Map / Scan ===")
    ImGui.Text("Obstacle Recording: " .. tostring(av_obj.is_obstacle_map_recording))
    ImGui.Text("Record Interval: " .. string.format("%.2f s", tonumber(av_obj.obstacle_record_interval) or 0))
    ImGui.Text("Record Range: " .. string.format("%.1f m", tonumber(av_obj.obstacle_record_range) or 0))
    ImGui.Text("Dirty Scan Count: " .. tostring(av_obj.autopilot_scan_dirty_count) .. " / " .. tostring(av_obj.autopilot_scan_dirty_threshold))
    ImGui.Text("Cached Obstacle Cells: " .. tostring(table_count(av_obj.obstacle_map)))
end

function Debug:ImGuiObstacleMap()
    self.is_im_gui_obstacle_map = ImGui.Checkbox("[ImGui] 3D Obstacle Map", self.is_im_gui_obstacle_map)
    if not self.is_im_gui_obstacle_map then return end

    local av_obj = self.core_obj.av_obj
    if not av_obj then
        ImGui.Text("AV object not available")
        return
    end

    ImGui.Text("=== 3D Obstacle Map ===")
    ImGui.Text("Records raycast hits during ANY driving (manual or autopilot).")
    ImGui.Text("Data is used by A* route planner to avoid known obstacle areas.")
    ImGui.Separator()

    -- Stats (ternary map: true=obstacle / "danger"=adjacent / false=clear / nil=unknown)
    local obstacle_count = 0
    local danger_count   = 0
    local clear_count    = 0
    for _, v in pairs(av_obj.obstacle_map) do
        if v == true then
            obstacle_count = obstacle_count + 1
        elseif v == "danger" then
            danger_count = danger_count + 1
        else
            clear_count = clear_count + 1
        end
    end
    ImGui.Text(string.format("Obstacle cells : %d", obstacle_count))
    ImGui.Text(string.format("Danger cells   : %d  (adjacent to obstacle)", danger_count))
    ImGui.Text(string.format("Clear cells    : %d", clear_count))
    ImGui.Text(string.format("Total cells    : %d", obstacle_count + danger_count + clear_count))
    ImGui.Text(string.format("Cell size           : %.0f m", av_obj.obstacle_cell_size))
    ImGui.Text(string.format("Record range        : %.0f m", av_obj.obstacle_record_range))
    ImGui.Text(string.format("Record interval     : %.2f s", av_obj.obstacle_record_interval))
    ImGui.Separator()

    -- Recording toggle (synced with NativeSettings is_enable_scan_during_autopilot)
    if av_obj.is_obstacle_map_recording then
        ImGui.PushStyleColor(ImGuiCol.Button, 0.7, 0.1, 0.1, 1.0)
        if ImGui.Button("STOP Recording") then
            av_obj.navigation_obj:StopObstacleRecording()
            DAV.user_setting_table.is_enable_scan_during_autopilot = false
            Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
        end
        ImGui.PopStyleColor(1)
        ImGui.SameLine()
        ImGui.Text("<< Recording active >>")
    else
        ImGui.PushStyleColor(ImGuiCol.Button, 0.1, 0.5, 0.1, 1.0)
        if ImGui.Button("START Recording") then
            av_obj.navigation_obj:StartObstacleRecording()
            DAV.user_setting_table.is_enable_scan_during_autopilot = true
            Utils:WriteJson(DAV.user_setting_path, DAV.user_setting_table)
        end
        ImGui.PopStyleColor(1)
    end

    ImGui.SameLine()
    if ImGui.Button("Integrate Diff -> Base") then
        self.last_obstacle_diff_integrate_ok = av_obj.navigation_obj:IntegrateObstacleMapDiff()
    end

    if self.last_obstacle_diff_integrate_ok == true then
        ImGui.TextDisabled("Diff integration: success")
    elseif self.last_obstacle_diff_integrate_ok == false then
        ImGui.TextDisabled("Diff integration: failed (see CET log)")
    end

    ImGui.Separator()

    ImGui.Text("=== Manual No-Go Convex Hexahedron ===")
    ImGui.TextDisabled("Record any 8 corner points of a convex hexahedron (point order is free).")
    ImGui.TextDisabled("If points are non-convex, duplicated, or nearly coplanar, creation will fail.")

    if ImGui.Button("Record P1") then self:RecordManualBlockPoint(1) end
    ImGui.SameLine()
    if ImGui.Button("Record P2") then self:RecordManualBlockPoint(2) end
    ImGui.SameLine()
    if ImGui.Button("Record P3") then self:RecordManualBlockPoint(3) end
    ImGui.SameLine()
    if ImGui.Button("Record P4") then self:RecordManualBlockPoint(4) end

    if ImGui.Button("Record P5") then self:RecordManualBlockPoint(5) end
    ImGui.SameLine()
    if ImGui.Button("Record P6") then self:RecordManualBlockPoint(6) end
    ImGui.SameLine()
    if ImGui.Button("Record P7") then self:RecordManualBlockPoint(7) end
    ImGui.SameLine()
    if ImGui.Button("Record P8") then self:RecordManualBlockPoint(8) end

    if ImGui.Button("Create Obstacle Convex Hexahedron") then
        self:CreateManualBlockHexahedron()
    end

    for i = 1, 8 do
        local p = self.manual_block_points[i]
        if p then
            ImGui.Text(string.format("P%d: %s", i, p.key))
        else
            ImGui.Text(string.format("P%d: (not set)", i))
        end
    end

    if self.last_manual_block_result and self.last_manual_block_result ~= "" then
        if self.last_manual_block_ok == true then
            ImGui.TextDisabled("Manual block: " .. self.last_manual_block_result)
        elseif self.last_manual_block_ok == false then
            ImGui.TextColored(1.0, 0.4, 0.4, 1.0, "Manual block: " .. self.last_manual_block_result)
        end
    end

    ImGui.Separator()

    -- Min hits slider removed (binary map: any single hit = obstacle)
    local changed
    av_obj.obstacle_record_range, changed = ImGui.SliderFloat(
        "Record range (m)", av_obj.obstacle_record_range, 10.0, 60.0)
    ImGui.Separator()
    ImGui.TextDisabled("Tip: drive around the city with recording ON.")
    ImGui.TextDisabled("A* autopilot will avoid confirmed obstacle sectors.")
    ImGui.TextDisabled("Use visualize_obstacle_map.py to view 3D map.")
end

function Debug:ImGuiExcuteFunction()
    if ImGui.Button("TF1") then
        print("Force Unmount Test")
        local player = Game.GetPlayer()
        local entity = player:GetMountedVehicle()
        local ent_id = entity:GetEntityID()
        local seat = DAV.core_obj.av_obj.active_seat[1]

        local data = MountEventData.new()
        data.isInstant = false
        data.slotName = seat
        data.mountParentEntityId = ent_id
        data.entryAnimName = "forcedTransition"

        local slotID = MountingSlotId.new()
        slotID.id = seat

        local mounting_info = MountingInfo.new()
        mounting_info.childId = player:GetEntityID()
        mounting_info.parentId = ent_id
        mounting_info.slotId = slotID

        local mount_event = UnmountingRequest.new()
        mount_event.lowLevelMountingInfo = mounting_info
        mount_event.mountData = data

        Game.GetMountingFacility():Unmount(mount_event)
        print("Excute Test Function 1")
    end
    ImGui.SameLine()
    if ImGui.Button("TF2") then
        print("Toggle Block Operation")
        if self.core_obj.av_obj.is_blocking_operation then
            self.core_obj.av_obj:BlockOperation(false)
            print("Unblock Operation")
        else
            self.core_obj.av_obj:BlockOperation(true)
            print("Block Operation")
        end

        print("Excute Test Function 2")
    end
    ImGui.SameLine()
    if ImGui.Button("TF3") then
        print("Get SpeedMeter Type")
        local GameSettings = require('External/GameSettings.lua')
        local speedometer_units = GameSettings.Get("/interface/SpeedometerUnits")
        print(speedometer_units)
        print("Excute Test Function 3")
    end
end

return Debug
