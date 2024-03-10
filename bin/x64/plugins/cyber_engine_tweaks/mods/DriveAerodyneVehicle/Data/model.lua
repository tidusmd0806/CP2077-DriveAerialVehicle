--[[
        This is the diagram of the vehicle's local corners
               E-----A
              /|    /|
             / |   / |
            G-----C  |
            |  F--|--B
            | /   | /
            |/    |/       
            H-----D

            ABFE is the front face
            CDHG is the back face
            EFHG is the left face
            ABDC is the right face
            ACGE is the top face
            BDHF is the bottom face           
    ]]

return {
    Excalibur = {
        name = "Vehicle.av_rayfield_excalibur",
        type = {
            "rayfield_excalibur__basic_arasaka_01",
            "rayfield_excalibur__basic_delamain_01",
            "rayfield_excalibur__basic_premium_01",
            "rayfield_excalibur__basic_saburo_arasaka_01",
        },
        is_default_mount = true,
        active_door = {"seat_front_left"},
        active_seat = {"seat_front_left", "seat_front_right", "seat_back_left", "seat_back_right"},
        is_default_seat_position = false,
        seat_position = {
            {x = -0.35, y = -1.12, z = -0.38},
            {x = -0.35, y = -1.12, z = -0.38},
            {x = -0.35, y = -1.10, z = -0.38},
            {x = -0.35, y = -1.12, z = -0.38},
        },
        sit_pose = {
            famale = "sit_chair_lean180__2h_on_lap__01",
            male = "sit_chair_lean180__2h_on_lap__01",
        },
        roll_speed = 0.8, -- x100 degree per second
        pitch_speed = 0.8,
        yaw_speed = 0.8,
        roll_restore_speed = 0.1,
        pitch_restore_speed = 0.1,
        max_roll = 25,
        min_roll = -25,
        max_pitch = 25,
        min_pitch = -25,
        max_lift_force = 15000000, -- magnitude of force compared to gravity (Newtons)
        min_lift_force = 5000000, -- magnitude of force compared to gravity (Newtons)
        time_to_max = 5, -- seconds
        time_to_min = 5, -- seconds
        mess = 2721000, -- kg
        air_resistance_constant = 1000000, -- Newton second per meter
        rebound_constant = 0.5, -- rate of rebound
        shape = {
            A = {x= 1.5, y= 3.0, z= 1.5},
            B = {x= 1.5, y= 3.0, z=-0.5},
            C = {x= 2.0, y=-6.0, z= 2.0},
            D = {x= 2.0, y=-6.0, z=-0.5},
            E = {x=-1.5, y= 3.0, z= 1.5},
            F = {x=-1.5, y= 3.0, z=-0.5},
            G = {x=-2.0, y=-4.0, z= 2.0},
            H = {x=-2.0, y=-4.0, z=-0.5},
        },
    },
}