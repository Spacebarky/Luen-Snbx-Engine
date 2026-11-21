local lgi = require("lgi")
local Gtk = lgi.require("Gtk", "3.0")

local world = require("renderer")
local player = require("player")
local audio = require("audio")
local cUI = require("cUI")

local win = Gtk.Window()
win:set_title("Luen Snbx Engine")
win:set_default_size(800, 600)

win.on_destroy = function()
 audio.cleanup()
  Gtk.main_quit()
end

local drawing_area, world_state = world.add_drawing()
player.attach_player(drawing_area, world_state)
cUI.add_ui(win, drawing_area, world_state)

win:show_all()
Gtk.main()
