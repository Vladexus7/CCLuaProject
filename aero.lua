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

local redstone_outputs = nil
local gimbal_sensor = peripheral.find("gimbal_sensor") or nil

-- Variables
local gimbal = {0, 0}

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
        if kp[key] ~= nil then
            kp = new_kp
        else
            print("Invalid kp key: " .. key .. ". Valid keys are: alt, pitch, yaw.")
        end
    end
end

local function set_redstone_outputs(outputs)
    expect(1, outputs, "table")
    for key, value in pairs(outputs) do
        expect(2, key, "string")
        expect(2, value, "table")
        if #value ~= 2 then
            error("Invalid output format for aero.set_redstone_outputs. Expected a table with two elements: {peripheral, side}.")
        end
    end
    redstone_outputs = outputs
end

local function get_gimbal()
    if gimbal_sensor ~= nil then
        gimbal = gimbal_sensor.getAngles()
        return gimbal[1], gimbal[2]
    else
        print("Gimbal sensor not found for aero.get_gimbal.")
        return nil
    end
end

local function get_pitch()
    local pitch, yaw = get_gimbal()
    if pitch ~= nil then
        return pitch
    else
        return nil
    end
end

local function get_yaw()
    local pitch, yaw = get_gimbal()
    if yaw ~= nil then
        return yaw
    else
        return nil
    end
end

local function get_altitude()
    local x,y,z = lino.get_xyz()
    if y ~= nil then
        return y
    else
        return nil
    end
end

-- Control Functions
local function move_up(power)
    expect(1, power, "number")
    if redstone_outputs and redstone_outputs.moveUp then
        if type(redstone_outputs.moveUp) == "table" then
            local peripheral, side = table.unpack(redstone_outputs.moveUp)
            peripheral.setAnalogOutput(side, power)
        elseif type(redstone_outputs.moveUp) == "string" then
            redstone.setAnalogOutput(redstone_outputs.moveUp, power)
        end
    else
        print("Redstone output for moveUp is not set.")
    end
end

local function aim_altitude(altitude)
    expect(1, altitude, "number")
    expect(2, kp, "table")
    local current_altitude = get_altitude()
    if current_altitude ~= nil then
        if current_altitude < altitude then
            move_up(math.min(15, kp.alt*math.round(altitude - current_altitude))) -- Increase power to ascend
        elseif current_altitude > altitude then
            move_up(0) -- Decrease power to descend
        end
    else
        print("Unable to retrieve current altitude.")
    end
end

return {
    set_vehicule_types = set_vehicule_types,
    set_kp = set_kp,
    set_redstone_outputs = set_redstone_outputs,
    get_gimbal = get_gimbal,
    get_pitch = get_pitch,
    get_yaw = get_yaw,
    get_altitude = get_altitude,
    move_up = move_up,
    aim_altitude = aim_altitude
}