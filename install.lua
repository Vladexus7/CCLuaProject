-- Pastebin install script for CCLuaProject
-- Constants
dir_name = "libraries"
update_url = "https://raw.githubusercontent.com/Vladexus7/CCLuaProject/main/update.lua"

-- Functions

local function check_install()
    -- Check if the CCLuaProject is installed
    if fs.exists(dir_name) then
        return true
    else
        return false
    end
end

local function install()
    update = http.get(update_url).readAll()
    local update_file = fs.open(dir_name .. "/update.lua", "w")
    update_file.write(update)
    print("Fresh install of CCLuaProject...")
    shell.run(dir_name .. "/update.lua", "update")
end

local function main()
    if not check_install() then
        install()
    else
        print("CCLuaProject is already installed.")
    end
end
main()
