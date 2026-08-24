-- a (vibe-coded) VBAN listener for ComputerCraft
-- This script connects to a VBAN bridge (Python script) and plays audio and video streams on ComputerCraft peripherals.
-- Stereo audio is supported if two speakers are attached (right has to be adjacent to computer, left has to be connected through networking cables). 
--Video is displayed on a monitor if one is attached.

local HOST = "http://192.168.1.32:8765"
local AUDIO_STREAM = "Stream2"
local VIDEO_STREAM = "VIDEO1"

local PLAY_SAMPLES = 4096
local FETCH_BYTES = math.floor(PLAY_SAMPLES / 8)

local dfpwm = require("cc.audio.dfpwm")

local decoder_left = dfpwm.make_decoder()
local decoder_right = dfpwm.make_decoder()

local last_video_frame = -1
local last_palette = nil

local speaker_left = nil
local speaker_right = nil
local stereo = false

local monitor = peripheral.find("monitor")

local function find_speakers()
    local speakers = {}

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "speaker" then
            speakers[#speakers + 1] = peripheral.wrap(name)

            if #speakers >= 2 then
                break
            end
        end
    end

    if #speakers >= 2 then
        return speakers[1], speakers[2], true
    elseif #speakers == 1 then
        return speakers[1], nil, false
    end

    return nil, nil, false
end

speaker_left, speaker_right, stereo = find_speakers()

if not speaker_left then
    error(
        "No speaker found. Attach a ComputerCraft speaker and retry.",
        0
    )
end

local function detect_audio_channels()
    local ok, response = pcall(function()
        return http.get(
            HOST
                .. "/audio_info?stream="
                .. AUDIO_STREAM
        )
    end)

    if not ok or not response then
        return 1
    end

    local body = response.readAll()
    response.close()

    if not body or body == "" then
        return 1
    end

    local ok_json, data = pcall(function()
        return textutils.unserializeJSON(body)
    end)

    if not ok_json or not data then
        return 1
    end

    return tonumber(data.channels) or 1
end

local input_channels = detect_audio_channels()

if input_channels < 2 then
    stereo = false
end

local function init_monitor()
    if not monitor then
        return
    end

    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
end

local function update_palette(palette)
    if not monitor or type(palette) ~= "table" then
        return
    end

    local changed = false

    if not last_palette then
        changed = true
    else
        for i = 1, 16 do
            local a = palette[i]
            local b = last_palette[i]

            if not a or not b
                or a[1] ~= b[1]
                or a[2] ~= b[2]
                or a[3] ~= b[3] then
                changed = true
                break
            end
        end
    end

    if not changed then
        return
    end

    for i = 1, 16 do
        local rgb = palette[i]

        if rgb then
            monitor.setPaletteColor(
                2 ^ (i - 1),
                (rgb[1] or 0) / 255,
                (rgb[2] or 0) / 255,
                (rgb[3] or 0) / 255
            )
        end
    end

    last_palette = {}

    for i = 1, 16 do
        if palette[i] then
            last_palette[i] = {
                palette[i][1],
                palette[i][2],
                palette[i][3]
            }
        end
    end
end

local function fetch_video_frame()
    if not monitor then
        return nil
    end

    local video_w, video_h = monitor.getSize()

    local url = HOST
        .. "/video?stream="
        .. VIDEO_STREAM
        .. "&w="
        .. video_w
        .. "&h="
        .. video_h

    local ok, response = pcall(function()
        return http.get(url)
    end)

    if not ok or not response then
        return nil
    end

    local body = response.readAll()
    response.close()

    if not body or body == "" then
        return nil
    end

    local ok_json, data = pcall(function()
        return textutils.unserializeJSON(body)
    end)

    if not ok_json or not data or not data.ok then
        return nil
    end

    if not data.rows then
        return nil
    end

    return data
end

local function render_video(frame)
    if not monitor or not frame then
        return
    end

    if frame.frame == last_video_frame then
        return
    end

    last_video_frame = frame.frame

    update_palette(frame.palette)

    local monitor_w, monitor_h = monitor.getSize()

    local video_w = tonumber(frame.w) or monitor_w
    local video_h = tonumber(frame.h) or monitor_h

    local offset_x = math.floor(
        (monitor_w - video_w) / 2
    )

    local offset_y = math.floor(
        (monitor_h - video_h) / 2
    )

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local text = string.rep(" ", video_w)
    local foreground = string.rep("0", video_w)

    for y = 1, video_h do
        local row = frame.rows[y] or ""

        if #row < video_w then
            row = row .. string.rep(
                "0",
                video_w - #row
            )
        elseif #row > video_w then
            row = row:sub(1, video_w)
        end

        monitor.setCursorPos(
            offset_x + 1,
            offset_y + y
        )

        monitor.blit(
            text,
            foreground,
            row
        )
    end
end

local function http_get_dfpwm(channel)
    local ok, response = pcall(function()
        return http.get(
            HOST
                .. "/dfpwm?stream="
                .. AUDIO_STREAM
                .. "&channel="
                .. channel
                .. "&max="
                .. FETCH_BYTES,
            nil,
            true
        )
    end)

    if not ok or not response then
        return nil
    end

    local data = response.readAll()
    response.close()

    if data and #data > 0 then
        return data
    end

    return nil
end

local function fetch_stereo()
    local result_left = nil
    local result_right = nil

    parallel.waitForAll(
        function()
            result_left = http_get_dfpwm(0)
        end,
        function()
            result_right = http_get_dfpwm(1)
        end
    )

    return result_left, result_right
end

local function play_speaker_sync(left_samples, right_samples)
    if not left_samples or not right_samples then
        return false
    end

    if #left_samples == 0 or #right_samples == 0 then
        return false
    end

    local left_done = false
    local right_done = false

    while not left_done or not right_done do
        parallel.waitForAll(
            function()
                if not left_done then
                    left_done =
                        speaker_left.playAudio(left_samples)
                end
            end,
            function()
                if not right_done then
                    right_done =
                        speaker_right.playAudio(right_samples)
                end
            end
        )

        if not left_done or not right_done then
            os.pullEvent("speaker_audio_empty")
        end
    end

    return true
end

local function audio_loop_stereo()
    while true do
        local chunk_left, chunk_right =
            fetch_stereo()

        if chunk_left and chunk_right then
            local samples_left =
                decoder_left(chunk_left)

            local samples_right =
                decoder_right(chunk_right)

            if samples_left
                and samples_right
                and #samples_left > 0
                and #samples_right > 0 then

                play_speaker_sync(
                    samples_left,
                    samples_right
                )
            end
        else
            sleep(0.005)
        end
    end
end

local function audio_loop_mono()
    while true do
        local chunk =
            http_get_dfpwm(0)

        if chunk then
            local samples =
                decoder_left(chunk)

            if samples and #samples > 0 then
                while not speaker_left.playAudio(samples) do
                    os.pullEvent("speaker_audio_empty")
                end
            end
        else
            sleep(0.005)
        end
    end
end

local function audio_loop()
    if stereo then
        audio_loop_stereo()
    else
        audio_loop_mono()
    end
end

local function video_loop()
    while true do
        local frame = fetch_video_frame()

        if frame then
            render_video(frame)
        end

        sleep(0.05)
    end
end

print("VBAN listener started")

print(
    "Speaker L:",
    peripheral.getName(speaker_left)
)

if stereo then
    print(
        "Speaker R:",
        peripheral.getName(speaker_right)
    )

    print("Audio: STEREO")
else
    print("Audio: MONO")
end

print("Input channels:", input_channels)
print("Audio stream:", AUDIO_STREAM)
print("Video stream:", VIDEO_STREAM)
print("Bridge host:", HOST)
print("Audio fetch:", FETCH_BYTES, "bytes")
print("Audio playback:", PLAY_SAMPLES, "samples")

if monitor then
    print(
        "Monitor:",
        peripheral.getName(monitor),
        "(video enabled)"
    )
else
    print("Monitor: not found (audio only)")
end

init_monitor()

local function main()
    parallel.waitForAny(
        audio_loop,
        video_loop
    )
end

return {
    audio_loop = audio_loop,
    video_loop = video_loop,
    main = main
}