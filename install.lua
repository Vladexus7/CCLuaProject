-- Pastebin install script for CCLuaProject
-- Constants
update_url = "https://raw.githubusercontent.com/Vladexus7/CCLuaProject/main/update.lua"

-- Functions

local function check_install()
    -- Check if the CCLuaProject is installed
    if fs.exists("update.lua") then
        return true
    else
        return false
    end
end

local function install()
    update = http.get(update_url).readAll()
    local update_file = fs.open("update.lua", "w")
    update_file.write(update)
    print("Fresh install of CCLuaProject...")
    local update_module = require("update")
    update_module.update()
end

local function main()
    if not check_install() then
        install()
    else
        print("CCLuaProject is already installed.")
    end
    shell.run("delete install.lua")
end
main()
