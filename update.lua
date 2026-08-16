-- Updates and fresh installs of CCLuaProject
-- Constants

local files_list = {
    "update.lua",
    "lino.lua",
    "aero.lua"
}

git_url = "https://github.com/Vladexus7/CCLuaProject.git"
git_version_url = "https://api.github.com/repos/Vladexus7/CCLuaProject/commits/main"
git_raw_url = "https://raw.githubusercontent.com/Vladexus7/CCLuaProject/main/"

-- Functions

--- Get the latest commit number of the CCLuaProject from GitHub
--@param url string The URL to the GitHub API for the CCLuaProject
--@return string The latest short commit number of the CCLuaProject
local function get_version(url)
    return http.get(url).read(15):sub(-7)
end

--- Install the startup.lua file if it does not exist
local function install_startup()
    if not fs.exists("startup.lua") then
        local startup_content = http.get("https://raw.githubusercontent.com/Vladexus7/CCLuaProject/main/startup.lua").readAll()
        local startup_file = fs.open("startup.lua", "w")
        startup_file.write(startup_content)
        startup_file.close()
    end
end

--- Check the current version of the CCLuaProject and compare it to the latest version on GitHub
--@return boolean true if the current version is up to date, false otherwise
local function check_version()
    if fs.exists("version.txt") then
        local new_version = get_version(git_version_url)
        local old_version = fs.open("version.txt", "r").readLine()
        if new_version == old_version then
            return true
        else
            return false
        end
    else
        local version = get_version(git_version_url)
        local version_file = fs.open("version.txt", "w")
        version_file.write(version)
        version_file.close()
        install_startup()
        return false
    end
end

--- Update the CCLuaProject by downloading the latest version from GitHub
--@return boolean true if the update was successful, false otherwise
local function update()
    if check_version() then
        print("CCLuaProject is up to date.")
    else
        print("Updating CCLuaProject...")
        for _, file in ipairs(files_list) do
            local url = git_raw_url .. file
            local response = http.get(url)
            if response then
                if fs.exists(file) then
                    fs.delete(file)
                end
                local content = response.readAll()
                local file_handle = fs.open(file, "w+")
                file_handle.write(content)
                file_handle.close()
                print("Updated " .. file)
            else
                print("Failed to download " .. file)
                print("update canceled. Please check your internet connection and try again.")
                if fs.exists("version.txt") then
                    fs.delete("version.txt")
                end
                goto end_update
            end
        end
        local new_version = get_version(git_version_url)
        local version_file = fs.open("version.txt", "w")
        version_file.write(new_version)
        version_file.close()
        print("Update complete. Current version: " .. new_version)
        return true
    end
    ::end_update::
    return false
end

return {
    get_version = get_version,
    check_version = check_version,
    update = update
}