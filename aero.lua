-- Create aeronautics library for CCLuaProject
-- Dependencies
local expect = require "cc.expect"
local expect, field = expect.expect, expect.field
local lino = require("lino")

-- Constants
local vehicule_types = {
    "airplane",
    "helicopter",
    "blimp"
}

local kp = {
    alt = 1.0,
    pitch = 1.0,
    yaw = 1.0
}

local kd = {
    alt = 1.0,
    pitch = 1.0,
    yaw = 1.0
}

local redstone_outputs = nil
local gimbal_sensor = peripheral.find("gimbal_sensor") or nil

-- Variables
local avg_speed = {0, 0, 0}
local avg_speed_mov_coef = 1
local avg_gimbal = {0, 0}
local avg_gimbal_mov_coef = 1
local last_pitch, last_yaw = 0, 0
local pitch_speed, yaw_speed = 0, 0
local last_time_gimbal_speed = os.epoch("utc")

-- Info Functions
local function set_vehicule_types(vehicule_type)
    expect(1, vehicule_type, "string")
    if vehicule_type == "airplane" or vehicule_type == "helicopter" or vehicule_type == "blimp" then
        vehicule_types = vehicule_type
    else
        print("Invalid vehicule type. Please choose from: " .. tostring(table.concat(vehicule_types, ", ")))
    end
end

local function set_kp(new_kp)
    expect(1, new_kp, "table")
    for key, value in pairs(new_kp) do
        expect(2, key, "string")
        expect(2, value, "number")
        kp = new_kp
    end
end

local function set_kd(new_kd)
    expect(1, new_kd, "table")
    for key, value in pairs(new_kd) do
        expect(2, key, "string")
        expect(2, value, "number")
        kd = new_kd
    end
end

local function set_redstone_outputs(outputs)
    expect(1, outputs, "table")
    for key, value in pairs(outputs) do
        expect(2, key, "string")
        expect(2, value, "string", "table")
    end
    redstone_outputs = outputs
end

local function set_avg_gimbal_mov_coef(coef)
    expect(1, coef, "number")
    avg_gimbal_mov_coef = coef
end

local function get_gimbal()
    if gimbal_sensor ~= nil then
        gimbal = gimbal_sensor.getAngles()
        return gimbal[2], gimbal[1]
    else
        error("Gimbal sensor not found for aero.get_gimbal.")
        return nil
    end
end

local function get_pitch()
    local pitch, _ = get_gimbal()
    return pitch
end

local function get_yaw()
    local _, yaw = get_gimbal()
    return yaw
end

local function get_altitude()
    local x,y,z = lino.get_xyz()
    return y
end

local function set_avg_speeds()
    local x, y, z = lino.get_speeds()
    avg_speed[1] = (avg_speed[1] * (avg_speed_mov_coef - 1) + x) / avg_speed_mov_coef
    avg_speed[2] = (avg_speed[2] * (avg_speed_mov_coef - 1) + y) / avg_speed_mov_coef
    avg_speed[3] = (avg_speed[3] * (avg_speed_mov_coef - 1) + z) / avg_speed_mov_coef
end

local function get_avg_speeds()
    set_avg_speeds()
    return avg_speed[1], avg_speed[2], avg_speed[3]
end

local function set_avg_gimbal()
    local pitch, yaw = get_gimbal()
    if pitch ~= nil and yaw ~= nil then
        if pitch == 0 or yaw == 0 then
            avg_gimbal = {pitch, yaw} -- initialize the average gimbal angles if they are zero
        else
            avg_gimbal[1] = (avg_gimbal[1] * (avg_gimbal_mov_coef - 1) + pitch / 1) / avg_gimbal_mov_coef
            avg_gimbal[2] = (avg_gimbal[2] * (avg_gimbal_mov_coef - 1) + yaw / 1) / avg_gimbal_mov_coef
        end
    else
        error("Unable to retrieve current gimbal angles for averaging.")
    end
end

local function get_avg_gimbal()
    return avg_gimbal[1], avg_gimbal[2]
end

local function set_gimbal_speed(new_pitch_speed, new_yaw_speed)
    pitch_speed, yaw_speed = new_pitch_speed, new_yaw_speed
end

local function calc_gimbal_speed()
    local pitch, yaw = get_gimbal()
    local time = os.epoch("utc")
    local time_delta = time - last_time_gimbal_speed
    if time_delta == 0 or last_pitch == 0 or last_yaw == 0 then
        last_pitch, last_yaw = pitch, yaw
        last_time_gimbal_speed = time
        os.sleep(0.05)
        time = os.epoch("utc")
        pitch, yaw = get_gimbal()
    end
    last_time_gimbal_speed = time
    local time_delta = time_delta / 1000 -- convert milliseconds to seconds
    local speed_pitch = (pitch - last_pitch) / time_delta
    local speed_yaw = (yaw - last_yaw) / time_delta
        if time_delta > 5 then
        print("Warning: speed readings are too slow. Speed calculations may be inaccurate.")
    end
    last_pitch, last_yaw = pitch, yaw
    set_gimbal_speed(speed_pitch, speed_yaw)
    return speed_pitch, speed_yaw
end

local function get_gimbal_speed()
    local time = os.epoch("utc")
    local time_delta = time - last_time_gimbal_speed
    if time_delta < 0.04 then
        return pitch_speed, yaw_speed
    else
        return calc_gimbal_speed()
    end
end

-- Control Functions
local function shut_down()
    if redstone_outputs then
        for key, value in pairs(redstone_outputs) do
            if type(value) == "table" then
                local peripheral, side = table.unpack(value)
                peripheral.setOutput(side, false)
            elseif type(value) == "string" then
                redstone.setOutput(value, false)
            end
        end
    else
        error("Redstone outputs not set for aero.shut_down.")
    end
end

local function set_output(output, power)
    expect(1, output, "table", "string")
    expect(2, power, "number")
    if type(output) == "table" then
        local peripheral, side = table.unpack(output)
        peripheral.setAnalogOutput(side, power)
        return true
    elseif type(output) == "string" then
        redstone.setAnalogOutput(output, power)
        return true
    end
    return false
end

local function move_up(power)
    expect(1, power, "number")
    if redstone_outputs and redstone_outputs.moveUp then
        set_output(redstone_outputs.moveUp, power)
    else
        error("Redstone output for moveUp is not set.")
    end
end

local function turn_gimbal(power, axis)
    expect(1, power, "number") -- Power from -15 to 15 where negative is down/left and positive is up/right
    expect(2, axis, "string")
    if axis == "pitch" then
        if redstone_outputs and redstone_outputs.turnFront and redstone_outputs.turnBack then
            if power > 0 then
                set_output(redstone_outputs.turnFront, power)
                set_output(redstone_outputs.turnBack, 0)
            elseif power < 0 then
                set_output(redstone_outputs.turnFront, 0)
                set_output(redstone_outputs.turnBack, -power)
            else
                set_output(redstone_outputs.turnFront, 0)
                set_output(redstone_outputs.turnBack, 0)
            end
        else
            error("Redstone outputs for turnFront and/or turnBack are not set.")
        end
    elseif axis == "yaw" then
        if redstone_outputs and redstone_outputs.turnLeft and redstone_outputs.turnRight then
            if power > 0 then
                set_output(redstone_outputs.turnRight, power)
                set_output(redstone_outputs.turnLeft, 0)
            elseif power < 0 then
                set_output(redstone_outputs.turnRight, 0)
                set_output(redstone_outputs.turnLeft, -power)
            else
                set_output(redstone_outputs.turnRight, 0)
                set_output(redstone_outputs.turnLeft, 0)
            end
        else
            error("Redstone outputs for turnLeft and/or turnRight are not set.")
        end
    end
end

local function pid_power(target, current, kp, kd, axis)
    local derivative = 0
    local error = target - current
    expect(1, target, "number")
    expect(2, current, "number")
    expect(3, kp, "number")
    expect(4, kd, "number")
    expect(5, axis, "string")
    if axis ~= "alt" and axis ~= "pitch" and axis ~= "yaw" then
        error("Invalid axis for PID control. Must be 'alt', 'pitch', or 'yaw'.")
        return 0
    elseif axis == "alt" then
        local _, derivative, _ = lino.get_speeds() -- Assuming the derivative is the current vertical speed
        local output = kp * error + kd * (derivative or 0) -- Use 0 if derivative is nil
        return math.max(0, math.min(15, output))
    elseif axis == "pitch" or axis == "yaw" then
        if axis == "pitch" then -- Assuming the derivative is the current gimbal speed
            derivative, _ = get_gimbal_speed() 
        else
            _, derivative = get_gimbal_speed() 
        end
        local output = kp * error + kd * (derivative or 0) -- Use 0 if derivative is nil
        return math.max(-15, math.min(15, output))
    end
end

local function aim_altitude(altitude)
    expect(1, altitude, "number")
    expect(2, kp, "table")
    local current_altitude = get_altitude()
    if current_altitude ~= nil then
        if current_altitude < altitude then
            move_up(pid_power(altitude, current_altitude, kp.alt, kd.alt, "alt")) -- Increase power to ascend
        elseif current_altitude > altitude then
            move_up(0) -- Decrease power to descend (but not 0 to still have gimbal control)
        end
    else
        error("Unable to retrieve current altitude.")
    end
end

local function aim_gimbal(target_pitch, target_yaw)
    expect(1, target_pitch, "number")
    expect(2, target_yaw, "number")
    expect(3, kp, "table")
    local pitch, yaw = get_gimbal()
    if pitch ~= nil and yaw ~= nil then
        local pitch_error = target_pitch - pitch
        local yaw_error = target_yaw - yaw
        turn_gimbal(pid_power(target_pitch, pitch, kp.pitch, kd.pitch, "pitch"), "pitch")
        turn_gimbal(pid_power(target_yaw, yaw, kp.yaw, kd.yaw, "yaw"), "yaw")
    else
        error("Unable to retrieve current gimbal angles.")
    end
end

return {
    set_vehicule_types = set_vehicule_types,
    set_kp = set_kp,
    set_kd = set_kd,
    set_avg_gimbal_mov_coef = set_avg_gimbal_mov_coef,
    set_redstone_outputs = set_redstone_outputs,
    shut_down = shut_down,
    get_gimbal = get_gimbal,
    get_pitch = get_pitch,
    get_yaw = get_yaw,
    get_avg_gimbal = get_avg_gimbal,
    get_altitude = get_altitude,
    move_up = move_up,
    turn_gimbal = turn_gimbal,
    get_gimbal_speed = get_gimbal_speed,
    aim_altitude = aim_altitude,
    aim_gimbal = aim_gimbal
}
