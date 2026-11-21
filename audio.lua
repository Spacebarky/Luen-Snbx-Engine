local lgi = require("lgi")
local Gst = lgi.Gst
local GLib = lgi.GLib

local M = {}
local pipeline = nillu
local vol_el = nil
local pan_el = nil
local bus_watch = nil

function M.init()
    local ok = pcall(Gst.init, nil)
    if not ok then return false end

    local source = debug.getinfo(1, "S").source
    local script_path = source:sub(2)
    local script_dir = script_path:match("(.*/)") or "./"

    local sound_path = GLib.canonicalize_filename(script_dir .. "sound.ogg", nil)
    local uri = GLib.filename_to_uri(sound_path, nil)


    local pipeline_str = "uridecodebin uri=" .. uri .. " ! audioconvert ! volume name=vol ! audiopanorama name=pan ! autoaudiosink"
    local ok2, p = pcall(Gst.parse_launch, pipeline_str)

    if not ok2 then
        print("Audio Error: Failed to create pipeline. Are plugins installed?")
        return false
    end

    pipeline = p
    vol_el = pipeline:get_by_name("vol")
    pan_el = pipeline:get_by_name("pan")


    local bus = pipeline:get_bus()
    bus_watch = bus:add_watch(GLib.PRIORITY_DEFAULT, function(bus, msg)
        if msg.type == Gst.MessageType.EOS then
            pipeline:seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH, 0)
            return true
        elseif msg.type == Gst.MessageType.ERROR then
            local err, dbg = msg:parse_error()
            print("GStreamer Error: " .. tostring(err.message))
            return false
        end
        return true
    end)

    pipeline:set_state("PLAYING")
    return true
end

function M.update(px, py, pz, cam_yaw, sx, sy, sz)
    if not pipeline or not vol_el then return end

    pcall(function()

        local dx = sx - px
        local dz = sz - pz
        local dist = math.sqrt(dx*dx + dz*dz)

        local max_dist = 20.0
        local vol = math.max(0, 1.0 - (dist / max_dist))

        local right_x = math.cos(cam_yaw)
        local right_z = -math.sin(cam_yaw)

        local dot = (dx * right_x + dz * right_z) / math.max(0.1, dist)
        local pan_val = math.max(-1.0, math.min(1.0, dot))

        vol_el.volume = vol
        if pan_el then
            pan_el.panorama = pan_val
        end
    end)
end

function M.cleanup()
    if pipeline then
        pipeline:set_state("NULL")
        pipeline = nil
    end
    if bus_watch then
        GLib.source_remove(bus_watch)
        bus_watch = nil
    end
    GLib.usleep(100000)
end

return M
