-- Template *describe the purpose of this file*
-- Dependencies 
if fs.exists("update.lua") then update = require("update") end
if fs.exists("lino.lua") then lino = require("lino") end
if fs.exists("aero.lua") then aero = require("aero") end
if fs.exists("streaming.lua") then stream = require("streaming") end

-- Sides

-- Constants

-- Functions

local function initialize()
    -- Initializes computer
    term.clear()
    term.setCursorPos(1, 1) 
    update.update() -- Comment this line out if you want to disable auto-update
    return true
end

-- main
local function main()
    if initialize() then
        while true do
            -- Main loop
        end
    else
        print("Initialization failed. Exiting.")
    end
end
main()

