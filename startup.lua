-- Template *describe the purpose of this file*
-- Dependencies 
local update = require("update")
local lino = require("lino")

-- Sides

-- Constants

-- Functions

local function initialize()
    -- Initializes computer
    term.clear()
    term.setCursorPos(1,1) 
    print("Checking updates...")
    update.update()
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

