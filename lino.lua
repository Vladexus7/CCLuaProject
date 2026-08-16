-- Library Initialized Not Original ©Bresch
-- Dependencies
local expect = require "cc.expect"
local expect, field = expect.expect, expect.field

-- Variables
local cursor_y = 1
status = "Nil"
self_computer_id = os.getComputerID()

-- Time Functions
-- Constants
local days = {"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"}
local month = {"January","February","March","April","May","June","July","August","September","October","November","December"}
local monthLength = {31,28,31,30,31,30,31,31,30,31,30,31}

--- Returns the current time in hours, minutes, and seconds based on the local UTC offset.
--@return number hour The current hour (0-23).
--@return number minute The current minute (0-59).
--@return number second The current second (0-59).
local function time()
    local date = os.date("*t", epoch)
    return date.hour, date.min, date.sec
end

--- Returns the current date in day, month, and year based on the local UTC offset.
--@return number day The current day of the month (1-31).
--@return number month The current month (1-12).
--@return number year The current year (e.g., 2024).
local function date()
    local date = os.date("*t", epoch)
    return date.day, date.month, date.year
end

--- Returns the name of the current day of the week based on the local UTC offset.
--@return string The name of the current day of the week.
local function day_name()
    local date = os.date("*t", epoch)
    return days[date.wday]
end

--- Returns the name of the current month based on the local UTC offset.
--@return string The name of the current month.
local function month_name()
    local date = os.date("*t", epoch)
    return month[date.month]
end

-- Redstone functions 

--- Repeats a 1 tick redstone signal infinitely.
--@param side The side to which to send the redstone signal ("up", "bottom", "left", "right", "front", or "back").
--@param duration The duration (in seconds) for which to send the redstone signal.
local function redstone_clock(side, period)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (default to front)
    expect(2, period, "number", "nil") -- expects a period (number) or nil (default 1 second)
    if side == nil then
        side = "front"
    end
    if period == nil then
        period = 1
    end
    while true do
        redstone.setOutput(side, true)
        os.sleep(0.05) -- 1 tick
        redstone.setOutput(side, false)
        os.sleep(period - 0.05)
    end
end

-- Term functions

--- Clears the terminal and resets the cursor position to the top-left corner.
local function clear_term()
    term.clear()
    cursor_y = 1
    term.setCursorPos(1,cursor_y)
end

--- Prints a line of text to the terminal and moves the cursor to the next line.
--@param text The text to print to the terminal.
local function print_line(text)
    expect(1, text, "string")
    term.setCursorPos(1,cursor_y)
    term.clearLine()
    print(text)
    cursor_y = cursor_y + 1
end

--- Prints the date and time in the format "HH:MM:SS Day DD Month YYYY" to the terminal.
local function print_date()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.blue)
    local h, m, s = time()
    local d, mo, y = date()
    local day = day_name()
    local month = month_name()
    print_line(string.format("%02d:%02d:%02d %s %02d %s %04d", h, m, s, day, d, month, y))
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

--- Prints the current status of the computer/turtle
local function print_status()
    print_line(status)
end

--- Loop for displaying date and status
local function info_loop()
    while true do
        local last_cursor_x, last_cursor_y = term.getCursorPos()
        local last_info_cursor_y = cursor_y
        cursor_y = 1
        term.setCursorPos(1,1)
        print_date()
        print_status()
        term.clearLine()
        cursor_y = last_info_cursor_y
        term.setCursorPos(last_cursor_x, last_cursor_y)
        os.sleep(1)
    end
end

-- Math functions

function sign(number)
    return number > 0 and 1 or (number == 0 and 0 or -1)
end

-- GPS functions

local last_x,last_y,last_z = gps.locate() 
local max_velocity = 100 -- Used to filter invalid GPS readings

local function check_distance(last_value,value)
    --check validity of the value and if it is within the maximum allowed velocity
    if math.abs(last_value - value) > max_velocity then
        return false
    end
    return true
end

local function check_xyz(last_value,value)
    if value == nil or check_distance(last_value,value) == false then
        return false
    end
    return true
end

local function get_xyz()
    ::retry_xyz::
    x,y,z = gps.locate()

    if not check_xyz(last_x,x) or not check_xyz(last_y,y) or not check_xyz(last_z,z) then
        goto retry_xyz
    end

    last_x,last_y,last_z = x,y,z
    return x,y,z
end

local function get_velocity()
    local x,y,z = get_xyz()
    local vx = x - last_x
    local vy = y - last_y
    local vz = z - last_z
    return math.sqrt(vx^2 + vy^2 + vz^2)
end

-- Monitor functions

-- Math functions

function sign(number)
    return number > 0 and 1 or (number == 0 and 0 or -1)
end

-- GPS functions

local last_x,last_y,last_z = gps.locate() 
local max_velocity = 100 -- Used to filter invalid GPS readings

local function check_distance(last_value,value)
    --check validity of the value and if it is within the maximum allowed velocity
    if math.abs(last_value - value) > max_velocity then
        return false
    end
    return true
end

local function check_xyz(last_value,value)
    if value == nil or check_distance(last_value,value) == false then
        return false
    end
    return true
end

local function get_xyz()
    x,y,z = gps.locate()

    if not check_xyz(last_x,x) or not check_xyz(last_y,y) or not check_xyz(last_z,z) then
        return last_x,last_y,last_z
    end

    last_x,last_y,last_z = x,y,z
    return x,y,z
end

-- Modem functions

local modem_type = "modem"

--- Checks if a modem is open on the specified side.
-- If the modem is not open, it attempts to open it.
--@param name The name of the peripheral (modem) to check.
--@return boolean True if the modem is open, false otherwise.
local function open_modem(name)
    if isOpen(name) then
        return true
    else
        rednet.open(name)
        return isOpen(name)
    end
end

--- Finds any available modem peripheral and opens it for communication.
--@return string The name of the opened modem peripheral, or nil if no modem was found
local function find_modem()
    local peripherals = peripheral.getNames()
    for _, name in ipairs(peripherals) do
        if peripheral.getType(name) == modem_type then
            if open_modem(name) then
                return name
            else
                print("Failed to open modem on side " .. name)
            end
        end
    end
    return nil
end

--- Sends a message through the opened modem.
--@param id The ID of the recipient.
--@param message The message to send.
--@return boolean True if the message was sent successfully, false otherwise.
local function send_message(id, message)
    local modem_name = find_modem()
    if modem_name ~= nil then
        local modem = peripheral.wrap(modem_name)
        if rednet.send(id, message) then
            return true
        else
            print("Failed to send message to ID " .. id)
            return false
        end
    else
        print("No modem found!")
        return false
    end
end

local function receive_message(channel)
    local modem_name = find_modem()
    if modem_name ~= nil then
        local modem = peripheral.wrap(modem_name)
        while true do
            local event, side, received_channel, reply_channel, message, distance = os.pullEvent("modem_message")
            if received_channel == channel then
                return message
            end
        end
    else
        print("No modem found!")
        return nil
    end
end

-- Turtle functions
-- Constants
local last_block = nil
local last_turn = nil

--- Checks fuel level at slot 16 and refuels if necessary. 
--Returns true if fuel is sufficient, false otherwise.
--@return boolean True if fuel is sufficient, false otherwise.
local function check_fuel()
    status = "Checking fuel level..."
    if turtle.getFuelLevel() == 0 then
        turtle.select(16)
        if not turtle.refuel(1) then
            print("Out of fuel! Please refuel the turtle.")
            return false
        end
    end
    return true
end

--- Turns the turtle to face a specified side ("left", "right", "back", or "front").
--@param side The side to turn to ("left", "right", "back", or "front").
--@return boolean True if the value is valid and the turtle turned, false otherwise.
local function turn_to(side)
    status = "Turning to " .. side .. "..."
    expect(1, side, "string")
    if side == "left" then
        turtle.turnLeft()
        last_turn = side
    elseif side == "right" then
        turtle.turnRight()
        last_turn = side
    elseif side == "back" then
        turtle.turnLeft()
        turtle.turnLeft()
        last_turn = side
    elseif side ~= "front" and side ~= nil then
        return false
    end
    return true
end

---Turns the turtle to face the last turned side.
--@return boolean True if the turtle turned to the last side, false otherwise.
local function turn_back()
    status = "Turning back..."
    if last_turn == "left" then
        turtle.turnRight()
    elseif last_turn == "right" then
        turtle.turnLeft()
    elseif last_turn == "back" then
        turtle.turnLeft()
        turtle.turnLeft()
    else
        return false
    end
    last_turn = nil
    return true
end

--- Takes items from a specified side of the turtle.
--@param side The side from which to take items ("top", "bottom", "left", "right", "front", or "back").
--@param quantity The number of items to take (default is 1).
--@return boolean True if items were successfully taken, false otherwise.
local function take_from(side, quantity)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (front)
    expect(2, quantity, "number", "nil") -- expects a quantity (number) or nil
    status = "Taking items from " .. side .. "..."

    if side == "top" then
        if turtle.suckUp(quantity) then
            return true
        end
    elseif side == "bottom" then
        if turtle.suckDown(quantity) then
            return true
        end
    else
        if turn_to(side) then
            if turtle.suck(quantity) then
                return true
            end
            turn_back()
        end
    end
    print("Failed to take items from side " .. side)
    return false
end

--- Puts items to a specified side of the turtle.
--@param side The side to which to put items ("top", "bottom", "left", "right", "front", or "back").
--@param quantity The number of items to put (default is 1).
--@return boolean True if items were successfully put, false otherwise.
local function put_to(side, quantity)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (front)
    expect(2, quantity, "number", "nil") -- expects a quantity (number) or nil
    status = "Putting items to " .. side .. "..."

    if side == "top" then
        if turtle.dropUp(quantity) then
            return true
        end
    elseif side == "bottom" then
        if turtle.dropDown(quantity) then
            return true
        end
    else
        if turn_to(side) then
            if turtle.drop(quantity) then
                return true
            end
            turn_back()
        end
    end
    print("Failed to put items to side " .. side)
    return false
end

---Places a block to a specified side of the turtle.
--@param side The side to which to place the block ("top", "bottom", "left", "right", "front", or "back").
--@return boolean True if the block was successfully placed, false otherwise. 
local function place_to(side)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (front)
    status = "Placing block to " .. side .. "..."

    if turtle.getItemDetail() ~= nil then
        last_block = turtle.getItemDetail().name
        if side == "top" then
            if turtle.placeUp() then
                return true
            end
        elseif side == "bottom" then
            if turtle.placeDown() then
                return true
            end
        else
            if turn_to(side) then
                if turtle.place() then
                    return true
                end
                turn_back()
            end
        end
    end
    print("Failed to place block to side " .. side)
    return false
end

---Grabs an item from a specified side of the turtle and places it in the turtle's inventory.
--@param side The side from which to grab the item ("top", "bottom", "left", "right", "front", or "back").
--@param quantity The number of items to grab (default is 1).
--@return boolean True if the item was successfully grabbed, false otherwise.
local function suck_from(side, quantity)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (front)
    expect(2, quantity, "number", "nil") -- expects a quantity (number) or nil
    status = "Sucking items from " .. side .. "..."

    if side == "top" then
        if turtle.suckUp(quantity) then
            return true
        end
    elseif side == "bottom" then
        if turtle.suckDown(quantity) then
            return true
        end
    else
        if turn_to(side) then
            if turtle.suck(quantity) then
                return true
            end
            turn_back()
        end
    end
    print("Failed to suck items from side " .. side)
    return false
end

--- Puts items to a specified side of the turtle.
--@param side The side to which to put items ("top", "bottom", "left", "right", "front", or "back").
--@param quantity The number of items to put (default is stack).
--@return boolean True if items were successfully put, false otherwise.
local function put_to(side, quantity)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (front)
    expect(2, quantity, "number", "nil") -- expects a quantity (number) or nil
    status = "Putting items to " .. side .. "..."

    if side == "top" then
        if turtle.dropUp(quantity) then
            return true
        end
    elseif side == "bottom" then
        if turtle.dropDown(quantity) then
            return true
        end
    else
        if turn_to(side) then
            if turtle.drop(quantity) then
                return true
            end
            turn_back()
        end
    end
    print("Failed to put items to side " .. side)
    return false
end

---Digs a block from a specified side of the turtle.
--Digs only if block present.
--@param side The side from which to dig the block ("top", "bottom", "left", "right", "front", or "back").
--@return boolean True if the block was successfully dug, false otherwise.
local function dig_from(side)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (front)
    status = "Digging block from " .. side .. "..."

    if side == "top" then
        local has_block, data = turtle.inspectUp()
        if has_block then
            if turtle.digUp() then
                return true
            end
        end
    elseif side == "bottom" then
        local has_block, data = turtle.inspectDown()
        if has_block then
            if turtle.digDown() then
                return true
            end
        end
    else
        local has_block, data = turtle.inspect()
        if has_block then
            if turn_to(side) then
                if turtle.dig() then
                    turn_back()
                    return true
                end
            end
        end
    end
    print("Failed to dig block from side " .. side)
    return false
end

---Digs a block from a specified side of the turtle.
--Digs only if the block is different from the last placed block to avoid digging the same block.
--Also tries to suck the block after digging to ensure it is collected.
--@param side The side from which to dig the block ("top", "bottom", "left", "right", "front", or "back").
--@param timeout The maximum time to wait for the block to be dug (in seconds).
--@return boolean True if the block was successfully dug, false otherwise.
local function mine_from(side, timeout)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (default to front)
    expect(2, timeout, "number", "nil") -- expects a timeout (number) or nil (60 seconds)

    if side == nil then
        side = "front"
    end

    if timeout == nil then
        timeout = 60
    end

    status = "Digging block from " .. side .. " with timeout " .. timeout .. " seconds..."

    timerStart = os.clock()
    while os.clock() - timerStart < timeout do
        if side == "top" then
            local has_block, data = turtle.inspectUp()
            if has_block and data.name ~= last_block then
                if turtle.digUp() then
                    while turtle.suckUp() do
                        -- Keep sucking until no more items are available
                    end
                    return true
                end
            end
        elseif side == "bottom" then
            local has_block, data = turtle.inspectDown()
            if has_block and data.name ~= last_block then
                if turtle.digDown() then
                    while turtle.suckDown() do
                        -- Keep sucking until no more items are available
                    end
                    return true
                end
            end
        else
            local has_block, data = turtle.inspect()
            if has_block and data.name ~= last_block then
                if turn_to(side) then
                    if turtle.dig() then
                        while turtle.suck() do
                            -- Keep sucking until no more items are available
                        end
                        turn_back()
                        return true
                    end
                end
            end
        end
        os.sleep(0.1) -- wait a bit before trying again to avoid busy waiting
    end
    print("Failed to dig block from side " .. side)
    return false
end

---Empties the turtle's inventory by dropping items to a specified side.
--Doesn't drop fuel slot (16)
--@param side The side to which to drop the items ("top", "bottom", "left", "right", "front", or "back").
--@return boolean True if the inventory was successfully emptied, false otherwise.
local function empty_inventory(side)
    expect(1, side, "string", "nil") -- expects a side (string) or nil (front)
    status = "Emptying inventory to " .. side .. "..."
    if side == nil then
        side = "front"
    end
    if side == "front" or side == "back" or side == "left" or side == "right" then
        turn_to(side)
    end
    last_slot = turtle.getSelectedSlot()
    for slot = 1, 15 do
        turtle.select(slot)
        if turtle.getItemCount() > 0 then
            if side == "top" then
                if not turtle.dropUp() then 
                    print("Failed to drop items from slot " .. slot .. " to side " .. side)
                    return false
                end
            elseif side == "bottom" then
                if not turtle.dropDown() then
                    print("Failed to drop items from slot " .. slot .. " to side " .. side)
                    return false
                end
            else
                if not turtle.drop() then
                    print("Failed to drop items from slot " .. slot .. " to side " .. side)
                    return false
                end
            end
        end
    end
    turtle.select(last_slot)
    turn_back()
    return true
end

-- Advanced peripheral functions

--- Plays a DFPWM audio file through a connected speaker peripheral.
--@param musique The name of the audio file to play (without extension).
local function play(musique)
    --base name : file = "musique.dfpwm"
    local file = musique .. ".dfpwm"
    local speaker = peripheral.find("speaker")
    if not speaker then
        print("Aucun haut-parleur trouvé !")
        return
    end
    local dfpwm = require("cc.audio.dfpwm")
    local decoder = dfpwm.make_decoder()
    local h = fs.open(file, "rb")
    if not h then
        print("Fichier introuvable : " .. file)
        return
    end
    status = "Playing audio file: " .. file
    while true do
        local chunk = h.read(16 * 1024)
        if not chunk then break end
        local decoded = decoder(chunk)
        while not speaker.playAudio(decoded, 1) do
            os.pullEvent("speaker_audio_empty")
        end
    end
    h.close()
    status = "Finished playing audio file: " .. file
    print("Lecture terminée !")
end

return {
    time = time,
    date = date,
    day_name = day_name,
    month_name = month_name,
    redstone_clock = redstone_clock,
    clear_term = clear_term,
    print_line = print_line,
    print_date = print_date,
    print_status = print_status,
    info_loop = info_loop,
    check_fuel = check_fuel,
    turn_to = turn_to,
    turn_back = turn_back,
    take_from = take_from,
    put_to = put_to,
    place_to = place_to,
    suck_from = suck_from,
    dig_from = dig_from,
    mine_from = mine_from,
    empty_inventory = empty_inventory,
    play = play
}