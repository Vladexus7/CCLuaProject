-- Template *describe the purpose of this file*
-- Rename to startup.lua to run on computer startup
-- Dependencies 

-- Sides

-- Constants

-- Functions

local function initialize()
    -- Initializes computer
    term.clear()
    term.setCursorPos(1,1) 
    print("Initializing...")
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

