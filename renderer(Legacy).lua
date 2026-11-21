-- cube3d.lua
local lgi = require("lgi")
local Gtk = lgi.require("Gtk", "3.0")
local GLib = lgi.GLib

-- Math helper for rotating vertices
local function rotate_point(x, y, z, pitch, roll)
  local cos_p, sin_p = math.cos(pitch), math.sin(pitch)
  local y1 = y * cos_p - z * sin_p
  local z1 = y * sin_p + z * cos_p

  local cos_r, sin_r = math.cos(roll), math.sin(roll)
  local x2 = x * cos_r - y1 * sin_r
  local y2 = x * sin_r + y1 * cos_r

  return x2, y2, z1
end

local function add_drawing()
  local drawing = Gtk.DrawingArea { width_request = 800, height_request = 600 }
  drawing:set_can_focus(true)
  drawing:grab_focus()

  local grass_blades = {}
  for i = 1, 500 do
    local gx = (math.random() * 30) - 15
    local gz = (math.random() * 30) - 15
    local gh = math.random() * 0.6 + 0.2
    local gw = math.random() * 0.15 + 0.05
    table.insert(grass_blades, {x=gx, z=gz, h=gh, w=gw})
  end

  local world = {
    active_camera = { x = 0, y = -1.5, z = -7, rot_x = 0.2, rot_y = 0 },
    grass_blades = grass_blades,
    colliders = {
      { x = 0, y = 3.5, z = 0, w = 30, h = 3, d = 30, r = 0.1, g = 0.3, b = 0.1 },
      { x = 5, y = -1.0, z = 5, w = 6, h = 2, d = 6, r = 0.3, g = 0.3, b = 0.35 }
    },
    entities = {},
    custom_draws = {},
    engine_render_list = {}
  }

  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, function()
    -- Dynamic Physics Loop
    for i = #world.colliders, 2, -1 do
      local box = world.colliders[i]

      -- If it has a vy, it's a spawned dynamic box
      if box.vy ~= nil then
        -- Gravity Accelerates
        box.vy = box.vy + 0.04

        -- Apply Velocity
        box.x = box.x + box.vx
        box.z = box.z + box.vz
        box.y = box.y + box.vy

        -- Apply Rotation (Torque)
        box.pitch = box.pitch + box.vp
        box.roll = box.roll + box.vr

        -- Friction (Slide and spin slows down)
        box.vx = box.vx * 0.90
        box.vz = box.vz * 0.90
        box.vp = box.vp * 0.85
        box.vr = box.vr * 0.85

        -- Collision with floor
        local is_over_floor = math.abs(box.x) <= 15 and math.abs(box.z) <= 15
        if is_over_floor then
          if box.y + box.h/2 >= 2.0 then
            box.y = 2.0 - box.h/2
            box.vy = 0

            -- Snapping: Settle flat on the ground
            local pi2 = math.pi / 2
            if math.abs(box.vp) < 0.02 then
              box.pitch = box.pitch + (math.floor(box.pitch / pi2 + 0.5) * pi2 - box.pitch) * 0.2
            end
            if math.abs(box.vr) < 0.02 then
              box.roll = box.roll + (math.floor(box.roll / pi2 + 0.5) * pi2 - box.roll) * 0.2
            end
          end
        else
          -- Fall off the edge
          if box.y > 50 then
            table.remove(world.colliders, i)
          end
        end
      end
    end

    drawing:queue_draw()
    return true
  end)

  drawing.on_draw = function(widget, cr)
    local W, H = widget:get_allocated_width(), widget:get_allocated_height()
    local cam = world.active_camera

    local function project(x, y, z)
      local dx = x - cam.x; local dy = y - cam.y; local dz = z - cam.z
      local cos_y, sin_y = math.cos(cam.rot_y), math.sin(cam.rot_y)
      local x1 = dx * cos_y - dz * sin_y; local z1 = dx * sin_y + dz * cos_y
      local cos_x, sin_x = math.cos(cam.rot_x), math.sin(cam.rot_x)
      local y1 = dy * cos_x - z1 * sin_x; local z2 = dy * sin_x + z1 * cos_x
      if z2 < 0.1 then z2 = 0.1 end
      local fov = 400
      return (x1 * fov) / z2 + (W / 2), (y1 * fov) / z2 + (H / 2), z2
    end

    local sky_grad = lgi.cairo.Pattern.create_linear(0, 0, 0, H)
    sky_grad:add_color_stop_rgb(0, 0.2, 0.5, 0.8)
    sky_grad:add_color_stop_rgb(1, 0.6, 0.8, 1.0)
    cr:set_source(sky_grad); cr:paint()

    local render_list = {}
    world.engine_render_list = render_list

    local function add_box_to_render(box)
      local bx, by, bz = box.x, box.y, box.z
      local bw, bh, bd = box.w, box.h, box.d
      local col_r, col_g, col_b = box.r, box.g, box.b

      local max_size = 5
      local steps_x = 1
      local steps_z = 1

      -- Only subdivide the static floor
      if bw > max_size and box.vy == nil then
        steps_x = math.max(1, math.ceil(bw / max_size))
        steps_z = math.max(1, math.ceil(bd / max_size))
      end

      local step_w = bw / steps_x
      local step_d = bd / steps_z

      for i = 0, steps_x - 1 do
        for j = 0, steps_z - 1 do
          local ox = bx - bw/2 + step_w/2 + i * step_w
          local oz = bz - bd/2 + step_d/2 + j * step_d
          local hw, hh, hd = step_w / 2, bh / 2, step_d / 2

          local v = {
            { ox - hw, by - hh, oz - hd }, { ox + hw, by - hh, oz - hd },
            { ox + hw, by + hh, oz - hd }, { ox - hw, by + hh, oz - hd },
            { ox - hw, by - hh, oz + hd }, { ox + hw, by - hh, oz + hd },
            { ox + hw, by + hh, oz + hd }, { ox - hw, by + hh, oz + hd }
          }
          local f = {
            {1, 2, 3, 4}, {5, 6, 7, 8}, {1, 5, 8, 4},
            {2, 6, 7, 3}, {4, 3, 7, 8}, {1, 5, 6, 2}
          }

          -- NEW: Apply rotation if the box is tipping over
          if box.pitch and box.roll then
            for k, vert in ipairs(v) do
              local lx = vert[1] - ox
              local ly = vert[2] - by
              local lz = vert[3] - oz
              local rx, ry, rz = rotate_point(lx, ly, lz, box.pitch, box.roll)
              v[k] = { ox + rx, by + ry, oz + rz }
            end
          end

          local proj_v = {}
          for k, vert in ipairs(v) do
            local px, py, pz = project(vert[1], vert[2], vert[3])
            proj_v[k] = { x = px, y = py, z = pz }
          end

          for k, face in ipairs(f) do
            local avg_z = (proj_v[face[1]].z + proj_v[face[2]].z + proj_v[face[3]].z + proj_v[face[4]].z) / 4
            table.insert(render_list, {
              points = { proj_v[face[1]], proj_v[face[2]], proj_v[face[3]], proj_v[face[4]] },
              z = avg_z,
              color = { col_r, col_g, col_b }
            })
          end
        end
      end
    end

    for _, box in ipairs(world.colliders) do
      add_box_to_render(box)
    end

    for _, blade in ipairs(world.grass_blades) do
      local p1x, p1y, p1z = project(blade.x - blade.w/2, 2.0, blade.z)
      local p2x, p2y, p2z = project(blade.x + blade.w/2, 2.0, blade.z)
      local p3x, p3y, p3z = project(blade.x, 2.0 - blade.h, blade.z)
      local avg_z = (p1z + p2z + p3z) / 3
      table.insert(render_list, {
        points = { {x=p1x, y=p1y}, {x=p2x, y=p2y}, {x=p3x, y=p3y}, {x=p3x, y=p3y} },
        z = avg_z,
        color = { 0.15, 0.5 + (blade.h * 0.2), 0.1 }
      })
    end

    for _, draw_func in ipairs(world.custom_draws) do
      draw_func(render_list, project)
    end

    table.sort(render_list, function(a, b) return a.z > b.z end)

    for _, face in ipairs(render_list) do
      cr:set_source_rgb(face.color[1], face.color[2], face.color[3])
      cr:move_to(face.points[1].x, face.points[1].y)
      cr:line_to(face.points[2].x, face.points[2].y)
      cr:line_to(face.points[3].x, face.points[3].y)
      cr:line_to(face.points[4].x, face.points[4].y)
      cr:close_path()
      cr:fill_preserve()
      if face.color[1] ~= 0.15 or face.color[2] < 0.5 then
        cr:set_source_rgb(0.1, 0.1, 0.1)
        cr:set_line_width(1)
        cr:stroke()
      end
    end
    return true
  end
  return drawing, world
end
return { add_drawing = add_drawing }
