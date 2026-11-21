local lgi = require("lgi")
local Gtk = lgi.require("Gtk", "3.0")
local GLib = lgi.GLib

local NEAR_PLANE = 0.1
local FOV = 400


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
  local drawing = Gtk.DrawingArea {
    width_request = 800,
    height_request = 600
  }

  drawing:set_can_focus(true)
  drawing:grab_focus()


  local grass_blades = {}

  for i = 1, 500 do
    local gx = (math.random() * 30) - 15
    local gz = (math.random() * 30) - 15
    local gh = math.random() * 0.6 + 0.2
    local gw = math.random() * 0.15 + 0.05

    table.insert(grass_blades, {
      x = gx,
      z = gz,
      h = gh,
      w = gw
    })
  end

  local world = {
    active_camera = {
      x = 0,
      y = -1.5,
      z = -7,
      rot_x = 0.2,
      rot_y = 0
    },

    grass_blades = grass_blades,

    colliders = {
      {
        x = 0, y = 3.5, z = 0,
        w = 30, h = 3, d = 30,
        r = 0.1, g = 0.3, b = 0.1,
        no_outline = true
      },
      {



        x = 5, y = -0.3, z = 5,
        w = 2.8, h = 4.6, d = 1.8,
        r = 0.12, g = 0.055, b = 0.19,
        jukebox = true
      }
    },



    sun = {
      x = -24,
      y = -24,
      z = 50,
      radius = 1.55
    },

    entities = {},
    custom_draws = {},
    engine_render_list = {}
  }




--uhhh nothing here!






  local PHYSICS_STEP = 0.016
  local MAX_CATCHUP_STEPS = 8
  local MAX_FRAME_DELTA = PHYSICS_STEP * MAX_CATCHUP_STEPS

  local physics_accumulator = 0
  local last_physics_time = GLib.get_monotonic_time()




  world.spawned_spheres = world.spawned_spheres or {}
  world._cui_sphere_physics_started = true

  local function number_or(value, fallback)
    local n = tonumber(value)
    if n == nil then
      return fallback
    end
    return n
  end

  local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
  end



  local function get_box_half_extents(box, defaults)
    defaults = defaults or {}

    local hw = math.abs(number_or(box.w or box.width, defaults.w or 1)) * 0.5
    local hh = math.abs(number_or(box.h or box.height, defaults.h or 1)) * 0.5
    local hd = math.abs(number_or(box.d or box.depth, defaults.d or 1)) * 0.5

    local pitch = number_or(box.pitch, 0)
    local roll = number_or(box.roll, 0)

    local ax, ay, az = rotate_point(1, 0, 0, pitch, roll)
    local bx, by, bz = rotate_point(0, 1, 0, pitch, roll)
    local cx, cy, cz = rotate_point(0, 0, 1, pitch, roll)

    return {
      x = math.abs(ax) * hw + math.abs(bx) * hh + math.abs(cx) * hd,
      y = math.abs(ay) * hw + math.abs(by) * hh + math.abs(cy) * hd,
      z = math.abs(az) * hw + math.abs(bz) * hh + math.abs(cz) * hd
    }
  end

  local function make_box_body(box, is_dynamic, is_player)
    local extents = get_box_half_extents(box, {
      w = 1,
      h = 1,
      d = 1
    })

    local inverse_mass = 0

    if is_dynamic then
      local mass = number_or(box.mass, nil)
      if not mass or mass <= 0 then
        mass = math.max(0.1,
          math.abs(number_or(box.w, 1) *
                   number_or(box.h, 1) *
                   number_or(box.d, 1)))
      end
      inverse_mass = 1 / mass
    elseif is_player then
      local mass = number_or(box.collision_mass or box.mass, 1)
      inverse_mass = 1 / math.max(0.1, mass)
    end

    return {
      ref = box,
      shape = "box",
      extents = extents,
      inv_mass = inverse_mass,
      dynamic = is_dynamic,
      is_player = is_player or false,
      kin_vx = 0,
      kin_vy = 0,
      kin_vz = 0
    }
  end

  local function make_sphere_body(sphere)
    local radius = math.max(0.01, number_or(sphere.radius, 0.75))
    local mass = number_or(sphere.mass, (4 / 3) * math.pi * radius ^ 3)

    return {
      ref = sphere,
      shape = "sphere",
      radius = radius,
      inv_mass = 1 / math.max(0.1, mass),
      dynamic = true,
      is_player = false,
      kin_vx = 0,
      kin_vy = 0,
      kin_vz = 0
    }
  end

  local function body_velocity(body)
    local ref = body.ref

    if body.is_player then



      return
        body.kin_vx or 0,
        body.kin_vy or 0,
        body.kin_vz or 0
    end

    return
      number_or(ref.vx, body.kin_vx or 0),
      number_or(ref.vy, body.kin_vy or 0),
      number_or(ref.vz, body.kin_vz or 0)
  end

  local function set_body_velocity(body, vx, vy, vz)
    local ref = body.ref

    if body.is_player then


      return
    end

    ref.vx, ref.vy, ref.vz = vx, vy, vz
  end

  local function move_body(body, dx, dy, dz)
    body.ref.x = body.ref.x + dx
    body.ref.y = body.ref.y + dy
    body.ref.z = body.ref.z + dz
  end

  local function box_box_contact(a, b)
    local ea = a.extents
    local eb = b.extents

    local dx = b.ref.x - a.ref.x
    local dy = b.ref.y - a.ref.y
    local dz = b.ref.z - a.ref.z

    local overlap_x = ea.x + eb.x - math.abs(dx)
    local overlap_y = ea.y + eb.y - math.abs(dy)
    local overlap_z = ea.z + eb.z - math.abs(dz)

    if overlap_x <= 0 or overlap_y <= 0 or overlap_z <= 0 then
      return nil
    end

    if overlap_x <= overlap_y and overlap_x <= overlap_z then
      return dx >= 0 and 1 or -1, 0, 0, overlap_x
    elseif overlap_y <= overlap_x and overlap_y <= overlap_z then
      return 0, dy >= 0 and 1 or -1, 0, overlap_y
    else
      return 0, 0, dz >= 0 and 1 or -1, overlap_z
    end
  end


  local function sphere_box_contact(sphere_body, box_body)
    local sphere = sphere_body.ref
    local box = box_body.ref
    local e = box_body.extents

    local min_x, max_x = box.x - e.x, box.x + e.x
    local min_y, max_y = box.y - e.y, box.y + e.y
    local min_z, max_z = box.z - e.z, box.z + e.z

    local closest_x = clamp(sphere.x, min_x, max_x)
    local closest_y = clamp(sphere.y, min_y, max_y)
    local closest_z = clamp(sphere.z, min_z, max_z)

    local dx = closest_x - sphere.x
    local dy = closest_y - sphere.y
    local dz = closest_z - sphere.z
    local distance_sq = dx * dx + dy * dy + dz * dz
    local radius = sphere_body.radius

    if distance_sq > radius * radius then
      return nil
    end

    if distance_sq > 0.00000001 then
      local distance = math.sqrt(distance_sq)
      return dx / distance, dy / distance, dz / distance,
             radius - distance
    end



    local local_x = sphere.x - box.x
    local local_y = sphere.y - box.y
    local local_z = sphere.z - box.z

    local face_x = e.x - math.abs(local_x)
    local face_y = e.y - math.abs(local_y)
    local face_z = e.z - math.abs(local_z)

    if face_x <= face_y and face_x <= face_z then
      local sign = local_x >= 0 and 1 or -1
      return -sign, 0, 0, radius + face_x
    elseif face_y <= face_x and face_y <= face_z then
      local sign = local_y >= 0 and 1 or -1
      return 0, -sign, 0, radius + face_y
    else
      local sign = local_z >= 0 and 1 or -1
      return 0, 0, -sign, radius + face_z
    end
  end

  local function sphere_sphere_contact(a, b)
    local dx = b.ref.x - a.ref.x
    local dy = b.ref.y - a.ref.y
    local dz = b.ref.z - a.ref.z
    local distance_sq = dx * dx + dy * dy + dz * dz
    local radius_sum = a.radius + b.radius

    if distance_sq >= radius_sum * radius_sum then
      return nil
    end

    if distance_sq <= 0.00000001 then
      return 1, 0, 0, radius_sum
    end

    local distance = math.sqrt(distance_sq)
    return dx / distance, dy / distance, dz / distance,
           radius_sum - distance
  end



  local PLAYER_PUSH_STRENGTH = 0.35
  local PLAYER_PUSH_MAX_SPEED_PER_STEP = 0.20



  local function resolve_contact(a, b, nx, ny, nz, penetration)
    local inverse_mass_sum = a.inv_mass + b.inv_mass
    if inverse_mass_sum <= 0 then
      return
    end

    local slop = 0.001
    local correction_percent = 0.82
    local correction = math.max(penetration - slop, 0) *
                       correction_percent / inverse_mass_sum

    if a.inv_mass > 0 then
      move_body(a,
        -nx * correction * a.inv_mass,
        -ny * correction * a.inv_mass,
        -nz * correction * a.inv_mass)
    end

    if b.inv_mass > 0 then
      move_body(b,
        nx * correction * b.inv_mass,
        ny * correction * b.inv_mass,
        nz * correction * b.inv_mass)
    end

    local avx, avy, avz = body_velocity(a)
    local bvx, bvy, bvz = body_velocity(b)

    local rvx = bvx - avx
    local rvy = bvy - avy
    local rvz = bvz - avz
    local velocity_along_normal = rvx * nx + rvy * ny + rvz * nz

    if velocity_along_normal >= 0 then
      return
    end

    local is_player_contact = a.is_player or b.is_player
    local restitution = is_player_contact and 0.02 or 0.12
    local impulse_scale = is_player_contact and PLAYER_PUSH_STRENGTH or 1
    local impulse = -(1 + restitution) * velocity_along_normal /
                    inverse_mass_sum * impulse_scale

    local impulse_x = impulse * nx
    local impulse_y = impulse * ny
    local impulse_z = impulse * nz

    if a.inv_mass > 0 then
      set_body_velocity(a,
        avx - impulse_x * a.inv_mass,
        avy - impulse_y * a.inv_mass,
        avz - impulse_z * a.inv_mass)
    end

    if b.inv_mass > 0 then
      set_body_velocity(b,
        bvx + impulse_x * b.inv_mass,
        bvy + impulse_y * b.inv_mass,
        bvz + impulse_z * b.inv_mass)
    end
  end

  local function collide_bodies(a, b)
    if a.inv_mass <= 0 and b.inv_mass <= 0 then
      return
    end

    local nx, ny, nz, penetration

    if a.shape == "box" and b.shape == "box" then
      nx, ny, nz, penetration = box_box_contact(a, b)
    elseif a.shape == "sphere" and b.shape == "box" then
      nx, ny, nz, penetration = sphere_box_contact(a, b)
    elseif a.shape == "box" and b.shape == "sphere" then
      nx, ny, nz, penetration = sphere_box_contact(b, a)
      if nx then
        nx, ny, nz = -nx, -ny, -nz
      end
    else
      nx, ny, nz, penetration = sphere_sphere_contact(a, b)
    end

    if nx then
      resolve_contact(a, b, nx, ny, nz, penetration)
    end
  end

  local function update_physics_step()
    world.spawned_spheres = world.spawned_spheres or {}



    for i = #world.colliders, 2, -1 do
      local box = world.colliders[i]

      if box.vy ~= nil then
        box.vx = number_or(box.vx, 0)
        box.vy = number_or(box.vy, 0) + 0.04
        box.vz = number_or(box.vz, 0)
        box.vp = number_or(box.vp, 0)
        box.vr = number_or(box.vr, 0)

        box.x = box.x + box.vx
        box.y = box.y + box.vy
        box.z = box.z + box.vz

        box.pitch = number_or(box.pitch, 0) + box.vp
        box.roll = number_or(box.roll, 0) + box.vr

        box.vx = box.vx * 0.90
        box.vz = box.vz * 0.90
        box.vp = box.vp * 0.85
        box.vr = box.vr * 0.85

        if box.y > 50 and
           (math.abs(box.x) > 15 or math.abs(box.z) > 15) then
          table.remove(world.colliders, i)
        end
      end
    end



    for i = #world.spawned_spheres, 1, -1 do
      local sphere = world.spawned_spheres[i]
      local radius = math.max(0.01, number_or(sphere.radius, 0.75))

      sphere.vx = number_or(sphere.vx, 0)
      sphere.vy = number_or(sphere.vy, 0) + 0.04
      sphere.vz = number_or(sphere.vz, 0)

      sphere.x = sphere.x + sphere.vx
      sphere.y = sphere.y + sphere.vy
      sphere.z = sphere.z + sphere.vz

      sphere.vx = sphere.vx * 0.90
      sphere.vz = sphere.vz * 0.90

      if sphere.y > 50 and
         (math.abs(sphere.x) > 15 or math.abs(sphere.z) > 15) then
        table.remove(world.spawned_spheres, i)
      end
    end


    local box_bodies = {}
    for _, box in ipairs(world.colliders) do
      if box.x ~= nil and box.y ~= nil and box.z ~= nil and
         box.w ~= nil and box.h ~= nil and box.d ~= nil then
        box_bodies[#box_bodies + 1] =
          make_box_body(box, box.vy ~= nil, false)
      end
    end

    local sphere_bodies = {}
    for _, sphere in ipairs(world.spawned_spheres) do
      if sphere.x ~= nil and sphere.y ~= nil and sphere.z ~= nil then
        sphere_bodies[#sphere_bodies + 1] = make_sphere_body(sphere)
      end
    end




    local player = world.player or
      (world.entities and world.entities[1]) or
      world.active_camera
    local player_body = nil
    local player_start_x, player_start_y, player_start_z

    if player and player.x ~= nil and player.y ~= nil and player.z ~= nil and
       player.collision_enabled ~= false then
      player_start_x = player.x
      player_start_y = player.y
      player_start_z = player.z

      local player_size = number_or(player.collision_size or player.size, 1)
      local player_box = {
        x = player.x,
        y = player.y,
        z = player.z,
        w = number_or(player.collision_w or player.w or player.width, player_size),
        h = number_or(player.collision_h or player.h or player.height, player_size),
        d = number_or(player.collision_d or player.d or player.depth, player_size),
        pitch = number_or(player.pitch, 0),
        roll = number_or(player.roll, 0),
        collision_mass = player.collision_mass or player.mass
      }

      player_body = make_box_body(player_box, false, true)
      player_body.ref = player





      if player._collision_prev_x ~= nil then
        local dx = player.x - player._collision_prev_x
        local dy = player.y - player._collision_prev_y
        local dz = player.z - player._collision_prev_z
        local moved = math.sqrt(dx * dx + dy * dy + dz * dz)



        if moved > PLAYER_PUSH_MAX_SPEED_PER_STEP then
          local scale = PLAYER_PUSH_MAX_SPEED_PER_STEP / moved
          dx, dy, dz = dx * scale, dy * scale, dz * scale
        end

        player_body.kin_vx = dx
        player_body.kin_vy = dy
        player_body.kin_vz = dz
      end
    end



    local SOLVER_ITERATIONS = 4

    for iteration = 1, SOLVER_ITERATIONS do

      for i = 1, #box_bodies - 1 do
        for j = i + 1, #box_bodies do
          collide_bodies(box_bodies[i], box_bodies[j])
        end
      end


      for _, sphere_body in ipairs(sphere_bodies) do
        for _, box_body in ipairs(box_bodies) do
          collide_bodies(sphere_body, box_body)
        end
      end


      for i = 1, #sphere_bodies - 1 do
        for j = i + 1, #sphere_bodies do
          collide_bodies(sphere_bodies[i], sphere_bodies[j])
        end
      end



      if player_body then
        for _, box_body in ipairs(box_bodies) do
          if box_body.ref ~= player then
            collide_bodies(player_body, box_body)
          end
        end

        for _, sphere_body in ipairs(sphere_bodies) do
          collide_bodies(player_body, sphere_body)
        end
      end
    end



    if player_body then
      local camera = world.active_camera
      if camera and camera ~= player then
        local follows_player =
          math.abs(number_or(camera.x, math.huge) - player_start_x) < 0.75 and
          math.abs(number_or(camera.z, math.huge) - player_start_z) < 0.75

        if follows_player then
          camera.x = camera.x + (player.x - player_start_x)
          camera.y = camera.y + (player.y - player_start_y)
          camera.z = camera.z + (player.z - player_start_z)
        end
      end

      player._collision_prev_x = player.x
      player._collision_prev_y = player.y
      player._collision_prev_z = player.z
    end
  end



  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, function()
    local now = GLib.get_monotonic_time()
    local elapsed = (now - last_physics_time) / 1000000
    last_physics_time = now

    if elapsed < 0 then
      elapsed = 0
    elseif elapsed > MAX_FRAME_DELTA then

      elapsed = MAX_FRAME_DELTA
    end

    physics_accumulator = math.min(
      physics_accumulator + elapsed,
      MAX_FRAME_DELTA
    )

    local steps = 0

    while physics_accumulator >= PHYSICS_STEP and
          steps < MAX_CATCHUP_STEPS do
      update_physics_step()
      physics_accumulator = physics_accumulator - PHYSICS_STEP
      steps = steps + 1
    end

    drawing:queue_draw()
    return true
  end)

  drawing.on_draw = function(widget, cr)
    local W = widget:get_allocated_width()
    local H = widget:get_allocated_height()

    if W <= 0 or H <= 0 then
      return true
    end

    local cam = world.active_camera



    local function to_camera(x, y, z)
      local dx = x - cam.x
      local dy = y - cam.y
      local dz = z - cam.z

      local cos_y = math.cos(cam.rot_y)
      local sin_y = math.sin(cam.rot_y)

      local x1 = dx * cos_y - dz * sin_y
      local z1 = dx * sin_y + dz * cos_y

      local cos_x = math.cos(cam.rot_x)
      local sin_x = math.sin(cam.rot_x)

      local y1 = dy * cos_x - z1 * sin_x
      local z2 = dy * sin_x + z1 * cos_x

      return {
        x = x1,
        y = y1,
        z = z2
      }
    end



    local function project(x, y, z)
      local p = to_camera(x, y, z)

      local safe_z = math.max(p.z, NEAR_PLANE)

      return
        (p.x * FOV) / safe_z + W / 2,
        (p.y * FOV) / safe_z + H / 2,
        safe_z
    end


    local function project_camera_vertex(p)
      return {
        x = (p.x * FOV) / p.z + W / 2,
        y = (p.y * FOV) / p.z + H / 2,
        z = p.z
      }
    end



    local function clip_near_plane(vertices)
      local output = {}

      if #vertices == 0 then
        return output
      end

      for i = 1, #vertices do
        local current = vertices[i]
        local next_vertex = vertices[(i % #vertices) + 1]

        local current_inside = current.z >= NEAR_PLANE
        local next_inside = next_vertex.z >= NEAR_PLANE

        if current_inside then
          output[#output + 1] = current
        end

        if current_inside ~= next_inside then
          local t =
            (NEAR_PLANE - current.z) /
            (next_vertex.z - current.z)

          output[#output + 1] = {
            x = current.x +
              (next_vertex.x - current.x) * t,

            y = current.y +
              (next_vertex.y - current.y) * t,

            z = NEAR_PLANE
          }
        end
      end

      return output
    end



    local function project_polygon(vertices)
      local camera_vertices = {}

      for _, vertex in ipairs(vertices) do
        camera_vertices[#camera_vertices + 1] =
          to_camera(vertex[1], vertex[2], vertex[3])
      end

      local clipped = clip_near_plane(camera_vertices)
      local projected = {}

      for _, vertex in ipairs(clipped) do
        projected[#projected + 1] =
          project_camera_vertex(vertex)
      end




      return projected, clipped
    end


    local sky_grad =
      lgi.cairo.Pattern.create_linear(0, 0, 0, H)

    sky_grad:add_color_stop_rgb(0, 0.2, 0.5, 0.8)
    sky_grad:add_color_stop_rgb(1, 0.6, 0.8, 1.0)

    cr:set_source(sky_grad)
    cr:paint()



    local sun = world.sun
    if sun and sun.x and sun.y and sun.z then
      local sun_sx, sun_sy, sun_depth = project(sun.x, sun.y, sun.z)
      if sun_depth > NEAR_PLANE then
        local sun_radius_px = math.max(5, FOV * (sun.radius or 1.55) / sun_depth)
        cr:set_source_rgba(1.0, 0.64, 0.16, 0.075)
        cr:arc(sun_sx, sun_sy, sun_radius_px * 3.2, 0, math.pi * 2)
        cr:fill()
        cr:set_source_rgba(1.0, 0.78, 0.28, 0.11)
        cr:arc(sun_sx, sun_sy, sun_radius_px * 1.9, 0, math.pi * 2)
        cr:fill()
      end
    end

    local render_list = {}
    world.engine_render_list = render_list


    local function add_polygon(points, color, camera_points, no_outline)
      if #points < 3 then
        return
      end

      local total_z = 0

      for _, point in ipairs(points) do
        total_z = total_z + point.z
      end

      render_list[#render_list + 1] = {
        points = points,
        camera_points = camera_points,
        z = total_z / #points,
        color = color,
        no_outline = no_outline == true
      }
    end









    local floor_box = world.colliders[1]
    local SHADOW_FLOOR_Y = 2.0
    local FLOOR_MIN_X, FLOOR_MAX_X = -15, 15
    local FLOOR_MIN_Z, FLOOR_MAX_Z = -15, 15

    if floor_box then
      SHADOW_FLOOR_Y = floor_box.y - math.abs(floor_box.h) * 0.5
      FLOOR_MIN_X = floor_box.x - math.abs(floor_box.w) * 0.5
      FLOOR_MAX_X = floor_box.x + math.abs(floor_box.w) * 0.5
      FLOOR_MIN_Z = floor_box.z - math.abs(floor_box.d) * 0.5
      FLOOR_MAX_Z = floor_box.z + math.abs(floor_box.d) * 0.5
    end

    local SUN = world.sun or { x = -24, y = -24, z = 50, radius = 1.55 }
    local SHADOW_ALPHA = 0.34
    local SHADOW_Y_EPSILON = 0.008

    local function cross_2d(o, a, b)
      return (a.x - o.x) * (b.z - o.z) -
             (a.z - o.z) * (b.x - o.x)
    end


    local function convex_hull_2d(points)
      if #points < 3 then
        return points
      end

      table.sort(points, function(a, b)
        if math.abs(a.x - b.x) > 0.000001 then
          return a.x < b.x
        end
        return a.z < b.z
      end)

      local unique = {}
      for _, point in ipairs(points) do
        local previous = unique[#unique]
        if not previous or
           math.abs(point.x - previous.x) > 0.00001 or
           math.abs(point.z - previous.z) > 0.00001 then
          unique[#unique + 1] = point
        end
      end

      if #unique < 3 then
        return unique
      end

      local lower = {}
      for _, point in ipairs(unique) do
        while #lower >= 2 and
              cross_2d(lower[#lower - 1], lower[#lower], point) <= 0 do
          table.remove(lower)
        end
        lower[#lower + 1] = point
      end

      local upper = {}
      for i = #unique, 1, -1 do
        local point = unique[i]
        while #upper >= 2 and
              cross_2d(upper[#upper - 1], upper[#upper], point) <= 0 do
          table.remove(upper)
        end
        upper[#upper + 1] = point
      end

      table.remove(lower)
      table.remove(upper)
      for _, point in ipairs(upper) do
        lower[#lower + 1] = point
      end
      return lower
    end


    local function clip_shadow_edge(points, axis, boundary, keep_greater)
      local output = {}
      if #points == 0 then
        return output
      end

      local function inside(point)
        local value = point[axis]
        if keep_greater then
          return value >= boundary
        end
        return value <= boundary
      end

      local previous = points[#points]
      local previous_inside = inside(previous)

      for _, current in ipairs(points) do
        local current_inside = inside(current)

        if current_inside ~= previous_inside then
          local previous_value = previous[axis]
          local current_value = current[axis]
          local denominator = current_value - previous_value

          if math.abs(denominator) > 0.0000001 then
            local t = (boundary - previous_value) / denominator
            output[#output + 1] = {
              x = previous.x + (current.x - previous.x) * t,
              z = previous.z + (current.z - previous.z) * t
            }
          end
        end

        if current_inside then
          output[#output + 1] = current
        end

        previous = current
        previous_inside = current_inside
      end

      return output
    end

    local function add_point_light_shadow(world_vertices, strength)
      if not SUN or not SUN.x or not SUN.y or not SUN.z or
         SUN.y >= SHADOW_FLOOR_Y then
        return false
      end

      local projected_points = {}
      for _, vertex in ipairs(world_vertices) do

        if vertex.y >= SUN.y and vertex.y <= SHADOW_FLOOR_Y + 0.001 then
          local denominator = vertex.y - SUN.y
          if denominator > 0.000001 then
            local t = (SHADOW_FLOOR_Y - SUN.y) / denominator
            if t >= 0.999 then
              projected_points[#projected_points + 1] = {
                x = SUN.x + (vertex.x - SUN.x) * t,
                z = SUN.z + (vertex.z - SUN.z) * t
              }
            end
          end
        end
      end

      if #projected_points < 3 then
        return false
      end

      local hull = convex_hull_2d(projected_points)
      hull = clip_shadow_edge(hull, "x", FLOOR_MIN_X, true)
      hull = clip_shadow_edge(hull, "x", FLOOR_MAX_X, false)
      hull = clip_shadow_edge(hull, "z", FLOOR_MIN_Z, true)
      hull = clip_shadow_edge(hull, "z", FLOOR_MAX_Z, false)

      if #hull < 3 then
        return false
      end

      local world_polygon = {}
      for _, point in ipairs(hull) do
        world_polygon[#world_polygon + 1] = {
          point.x,
          SHADOW_FLOOR_Y - SHADOW_Y_EPSILON,
          point.z
        }
      end

      local screen_points, camera_points = project_polygon(world_polygon)
      local alpha = SHADOW_ALPHA * math.max(0, math.min(1, strength or 1))
      add_polygon(
        screen_points,
        { 0.018, 0.022, 0.032, alpha },
        camera_points,
        true
      )
      return true
    end

    local function add_box_shadow(box)
      if not box or box.x == nil or box.y == nil or box.z == nil then
        return false
      end

      local hw = math.abs(number_or(box.w or box.width, 1)) * 0.5
      local hh = math.abs(number_or(box.h or box.height, 1)) * 0.5
      local hd = math.abs(number_or(box.d or box.depth, 1)) * 0.5
      local pitch = number_or(box.pitch, 0)
      local roll = number_or(box.roll, 0)
      local vertices = {}

      for _, corner in ipairs({
        {-hw, -hh, -hd}, { hw, -hh, -hd},
        { hw,  hh, -hd}, {-hw,  hh, -hd},
        {-hw, -hh,  hd}, { hw, -hh,  hd},
        { hw,  hh,  hd}, {-hw,  hh,  hd}
      }) do
        local rx, ry, rz = rotate_point(
          corner[1], corner[2], corner[3], pitch, roll
        )
        vertices[#vertices + 1] = {
          x = box.x + rx,
          y = box.y + ry,
          z = box.z + rz
        }
      end

      return add_point_light_shadow(vertices, 1)
    end

    local function add_sphere_shadow(sphere)
      if not sphere or sphere.x == nil or sphere.y == nil or sphere.z == nil then
        return false
      end

      local radius = math.max(0.01, number_or(sphere.radius, 0.75))
      local vertices = {}
      local latitude_steps = 8
      local longitude_steps = 20


      for latitude = 0, latitude_steps do
        local phi = (latitude / latitude_steps) * math.pi
        local ring_radius = math.sin(phi) * radius
        local y_offset = math.cos(phi) * radius

        for longitude = 0, longitude_steps - 1 do
          local theta = (longitude / longitude_steps) * math.pi * 2
          vertices[#vertices + 1] = {
            x = sphere.x + math.cos(theta) * ring_radius,
            y = sphere.y + y_offset,
            z = sphere.z + math.sin(theta) * ring_radius
          }
        end
      end

      return add_point_light_shadow(vertices, 0.95)
    end



    local function camera_to_world(point)
      local cos_x = math.cos(cam.rot_x)
      local sin_x = math.sin(cam.rot_x)
      local cos_y = math.cos(cam.rot_y)
      local sin_y = math.sin(cam.rot_y)

      local y1 = point.y * cos_x + point.z * sin_x
      local z1 = -point.y * sin_x + point.z * cos_x
      local dx = point.x * cos_y + z1 * sin_y
      local dz = -point.x * sin_y + z1 * cos_y

      return cam.x + dx, cam.y + y1, cam.z + dz
    end

    local function add_custom_draw_shadow(first_face, last_face, W, H)
      local world_vertices = {}

      for face_index = first_face, last_face do
        local face = render_list[face_index]
        local camera_points = face and face.camera_points

        if face and face.points and #face.points >= 3 then
          if not camera_points or #camera_points == 0 then
            camera_points = {}
            for _, screen_point in ipairs(face.points) do
              local depth = math.max(
                tonumber(screen_point.z) or tonumber(face.z) or NEAR_PLANE,
                NEAR_PLANE
              )
              camera_points[#camera_points + 1] = {
                x = (screen_point.x - W / 2) * depth / FOV,
                y = (screen_point.y - H / 2) * depth / FOV,
                z = depth
              }
            end
          end

          for _, camera_point in ipairs(camera_points) do
            local wx, wy, wz = camera_to_world(camera_point)
            world_vertices[#world_vertices + 1] = {
              x = wx, y = wy, z = wz
            }
          end
        end
      end

      if #world_vertices < 3 then
        return false
      end


      local min_x, max_x = math.huge, -math.huge
      local min_y, max_y = math.huge, -math.huge
      local min_z, max_z = math.huge, -math.huge
      for _, vertex in ipairs(world_vertices) do
        min_x = math.min(min_x, vertex.x)
        max_x = math.max(max_x, vertex.x)
        min_y = math.min(min_y, vertex.y)
        max_y = math.max(max_y, vertex.y)
        min_z = math.min(min_z, vertex.z)
        max_z = math.max(max_z, vertex.z)
      end

      if max_x - min_x >= 20 or max_z - min_z >= 20 or
         max_y - min_y >= 20 then
        return false
      end

      return add_point_light_shadow(world_vertices, 0.95)
    end



    local function shade_box_face(points, base_color, box_center)
      if not SUN or not SUN.x or not SUN.y or not SUN.z or #points < 3 then
        return base_color
      end

      local a, b, c = points[1], points[2], points[3]
      local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
      local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
      local nx = uy * vz - uz * vy
      local ny = uz * vx - ux * vz
      local nz = ux * vy - uy * vx
      local normal_length = math.sqrt(nx * nx + ny * ny + nz * nz)
      if normal_length < 0.000001 then
        return base_color
      end
      nx, ny, nz = nx / normal_length, ny / normal_length, nz / normal_length

      local cx, cy, cz = 0, 0, 0
      for _, point in ipairs(points) do
        cx = cx + point[1]
        cy = cy + point[2]
        cz = cz + point[3]
      end
      cx, cy, cz = cx / #points, cy / #points, cz / #points



      local outward_x = cx - box_center.x
      local outward_y = cy - box_center.y
      local outward_z = cz - box_center.z
      if nx * outward_x + ny * outward_y + nz * outward_z < 0 then
        nx, ny, nz = -nx, -ny, -nz
      end

      local lx, ly, lz = SUN.x - cx, SUN.y - cy, SUN.z - cz
      local light_length = math.sqrt(lx * lx + ly * ly + lz * lz)
      if light_length < 0.000001 then
        return base_color
      end

      local diffuse = math.max(0, (nx * lx + ny * ly + nz * lz) / light_length)
      local intensity = 0.34 + 0.66 * diffuse
      return {
        base_color[1] * intensity,
        base_color[2] * intensity,
        base_color[3] * intensity
      }
    end


    local function add_box_to_render(box)
      local bx, by, bz = box.x, box.y, box.z

      local bw, bh, bd = box.w, box.h, box.d

      local col_r = box.r
      local col_g = box.g
      local col_b = box.b


      local steps_x = 1
      local steps_z = 1

      local step_w = bw / steps_x
      local step_d = bd / steps_z

      local faces = {
        {1, 2, 3, 4},
        {5, 6, 7, 8},
        {1, 5, 8, 4},
        {2, 6, 7, 3},
        {4, 3, 7, 8},
        {1, 5, 6, 2}
      }

      for i = 0, steps_x - 1 do
        for j = 0, steps_z - 1 do
          local ox =
            bx - bw / 2 + step_w / 2 + i * step_w

          local oz =
            bz - bd / 2 + step_d / 2 + j * step_d

          local hw = step_w / 2
          local hh = bh / 2
          local hd = step_d / 2

          local v = {
            {ox - hw, by - hh, oz - hd},
            {ox + hw, by - hh, oz - hd},
            {ox + hw, by + hh, oz - hd},
            {ox - hw, by + hh, oz - hd},

            {ox - hw, by - hh, oz + hd},
            {ox + hw, by - hh, oz + hd},
            {ox + hw, by + hh, oz + hd},
            {ox - hw, by + hh, oz + hd}
          }


          if box.pitch and box.roll then
            for k, vert in ipairs(v) do
              local lx = vert[1] - ox
              local ly = vert[2] - by
              local lz = vert[3] - oz

              local rx, ry, rz =
                rotate_point(
                  lx, ly, lz,
                  box.pitch,
                  box.roll
                )

              v[k] = {
                ox + rx,
                by + ry,
                oz + rz
              }
            end
          end


          for _, face in ipairs(faces) do
            local polygon = {
              v[face[1]],
              v[face[2]],
              v[face[3]],
              v[face[4]]
            }

            local projected, camera_points = project_polygon(polygon)

            local face_points = {
              v[face[1]], v[face[2]], v[face[3]], v[face[4]]
            }
            local shaded_color = shade_box_face(
              face_points,
              {col_r, col_g, col_b},
              {x = bx, y = by, z = bz}
            )

            add_polygon(
              projected,
              shaded_color,
              camera_points,
              box.no_outline
            )
          end
        end
      end




      if box.jukebox then
        local front_z = bz - bd / 2 - 0.035

        local function add_detail(points, color)
          local projected, camera_points = project_polygon(points)
          add_polygon(projected, color, camera_points)
        end

        local function add_rect(cx, y0, y1, width, z, color)
          local half = width / 2
          add_detail({
            {cx - half, y0, z},
            {cx + half, y0, z},
            {cx + half, y1, z},
            {cx - half, y1, z}
          }, color)
        end

        local function add_disc(cx, cy, radius, z, color, segments)
          local points = {}
          segments = segments or 20
          for i = 0, segments - 1 do
            local angle = (i / segments) * math.pi * 2
            points[#points + 1] = {
              cx + math.cos(angle) * radius,
              cy + math.sin(angle) * radius,
              z
            }
          end
          add_detail(points, color)
        end


        add_rect(bx, by - bh * 0.43, by + bh * 0.43,
                 bw * 0.82, front_z - 0.006,
                 {0.78, 0.48, 0.13})
        add_rect(bx, by - bh * 0.405, by + bh * 0.405,
                 bw * 0.77, front_z - 0.012,
                 {0.16, 0.045, 0.20})


        local window_w = bw * 0.59
        local window_left = bx - window_w / 2
        local window_right = bx + window_w / 2
        local window_bottom = by + bh * 0.12
        local window_top = by + bh * 0.30
        local arch_height = bh * 0.16
        local arch_points = {
          {window_left, window_bottom, front_z - 0.020},
          {window_right, window_bottom, front_z - 0.020},
          {window_right, window_top, front_z - 0.020}
        }
        for i = 0, 12 do
          local angle = (i / 12) * math.pi
          arch_points[#arch_points + 1] = {
            bx + math.cos(angle) * window_w / 2,
            window_top + math.sin(angle) * arch_height,
            front_z - 0.020
          }
        end
        add_detail(arch_points, {0.015, 0.025, 0.075})


        local bar_colors = {
          {0.05, 0.85, 1.0},
          {0.15, 0.35, 1.0},
          {0.75, 0.18, 1.0},
          {1.0, 0.18, 0.48},
          {1.0, 0.58, 0.12},
          {0.95, 0.9, 0.25}
        }
        local bar_w = window_w * 0.075
        for i, color in ipairs(bar_colors) do
          local x = window_left + window_w * (i / 7)
          add_rect(x, window_bottom + 0.06,
                   window_top + arch_height * 0.45,
                   bar_w, front_z - 0.027, color)
        end


        add_rect(bx, by + bh * 0.015, by + bh * 0.075,
                 bw * 0.60, front_z - 0.022,
                 {0.86, 0.58, 0.18})
        for i = -2, 2 do
          add_disc(bx + i * bw * 0.105, by + bh * 0.045,
                   0.055, front_z - 0.030,
                   ({
                     {0.15, 0.85, 1.0},
                     {1.0, 0.25, 0.55},
                     {1.0, 0.82, 0.2},
                     {0.35, 1.0, 0.55},
                     {0.65, 0.35, 1.0}
                   })[i + 3], 12)
        end


        for _, side in ipairs({-1, 1}) do
          local sx = bx + side * bw * 0.205
          local sy = by - bh * 0.205
          add_disc(sx, sy, bw * 0.145, front_z - 0.022,
                   {0.83, 0.57, 0.20}, 24)
          add_disc(sx, sy, bw * 0.122, front_z - 0.029,
                   {0.035, 0.025, 0.055}, 24)
          add_disc(sx, sy, bw * 0.073, front_z - 0.036,
                   {0.22, 0.13, 0.28}, 20)
          add_disc(sx, sy, bw * 0.025, front_z - 0.043,
                   {0.9, 0.62, 0.2}, 16)
        end


        for i = -3, 3 do
          add_rect(bx + i * bw * 0.075,
                   by - bh * 0.37, by - bh * 0.35,
                   bw * 0.035, front_z - 0.025,
                   {0.55, 0.34, 0.12})
        end
      end
    end



    if world.colliders[1] then
      add_box_to_render(world.colliders[1])
    end


    for i = 2, #world.colliders do
      add_box_shadow(world.colliders[i])
    end

    for _, sphere in ipairs(world.spawned_spheres or {}) do
      add_sphere_shadow(sphere)
    end


    for i = 2, #world.colliders do
      add_box_to_render(world.colliders[i])
    end


    for _, blade in ipairs(world.grass_blades) do
      local polygon = {
        {
          blade.x - blade.w / 2,
          2.0,
          blade.z
        },
        {
          blade.x + blade.w / 2,
          2.0,
          blade.z
        },
        {
          blade.x,
          2.0 - blade.h,
          blade.z
        }
      }

      local projected, camera_points = project_polygon(polygon)

      add_polygon(
        projected,
        {
          0.15,
          0.5 + (blade.h * 0.2),
          0.1
        },
        camera_points
      )
    end




    local custom_shadows_added = 0
    local has_spawned_spheres = #(world.spawned_spheres or {}) > 0

    for _, draw_func in ipairs(world.custom_draws) do
      local first_custom_face = #render_list + 1
      draw_func(render_list, project)
      local last_custom_face = #render_list





      if not has_spawned_spheres and last_custom_face >= first_custom_face then
        if add_custom_draw_shadow(first_custom_face, last_custom_face, W, H) then
          custom_shadows_added = custom_shadows_added + 1
        end
      end
    end



    if custom_shadows_added == 0 then
      local player_object = world.player or
        (world.entities and world.entities[1]) or
        world.active_camera

      if player_object and player_object.x ~= nil and
         player_object.y ~= nil and player_object.z ~= nil then
        local player_size = number_or(
          player_object.collision_size or player_object.size, 1
        )
        add_box_shadow({
          x = player_object.x,
          y = player_object.y,
          z = player_object.z,
          w = number_or(
            player_object.collision_w or player_object.w or player_object.width,
            player_size
          ),
          h = number_or(
            player_object.collision_h or player_object.h or player_object.height,
            player_size
          ),
          d = number_or(
            player_object.collision_d or player_object.d or player_object.depth,
            player_size
          ),
          pitch = number_or(player_object.pitch, 0),
          roll = number_or(player_object.roll, 0)
        })
      end
    end



    local function add_sun_to_render()
      if not SUN or not SUN.x or not SUN.y or not SUN.z then
        return
      end

      local radius = math.max(0.1, number_or(SUN.radius, 1.55))
      local latitude_steps = 7
      local longitude_steps = 18

      for latitude = 0, latitude_steps - 1 do
        local phi0 = -math.pi * 0.5 +
                     (latitude / latitude_steps) * math.pi
        local phi1 = -math.pi * 0.5 +
                     ((latitude + 1) / latitude_steps) * math.pi

        for longitude = 0, longitude_steps - 1 do
          local theta0 = (longitude / longitude_steps) * math.pi * 2
          local theta1 = ((longitude + 1) / longitude_steps) * math.pi * 2

          local function sun_vertex(phi, theta)
            local ring = math.cos(phi) * radius
            return {
              SUN.x + math.cos(theta) * ring,
              SUN.y + math.sin(phi) * radius,
              SUN.z + math.sin(theta) * ring
            }
          end

          local polygon = {
            sun_vertex(phi0, theta0),
            sun_vertex(phi0, theta1),
            sun_vertex(phi1, theta1),
            sun_vertex(phi1, theta0)
          }

          local projected, camera_points = project_polygon(polygon)
          local band = 0.92 + 0.08 * math.cos((phi0 + phi1) * 0.5)
          add_polygon(
            projected,
            { 1.0, 0.72 * band, 0.22 * band },
            camera_points,
            true
          )
        end
      end
    end

    add_sun_to_render()










    local BSP_EPSILON = 0.00001
    local BSP_MAX_DEPTH = 48
    local BSP_SPLITTER_SAMPLES = 12

    local function plane_distance(plane, point)
      return
        plane.nx * point.x +
        plane.ny * point.y +
        plane.nz * point.z +
        plane.d
    end

    local function plane_from_polygon(points)
      if not points or #points < 3 then
        return nil
      end

      local p0 = points[1]



      for i = 2, #points - 1 do
        for j = i + 1, #points do
          local a = {
            x = points[i].x - p0.x,
            y = points[i].y - p0.y,
            z = points[i].z - p0.z
          }

          local b = {
            x = points[j].x - p0.x,
            y = points[j].y - p0.y,
            z = points[j].z - p0.z
          }

          local nx = a.y * b.z - a.z * b.y
          local ny = a.z * b.x - a.x * b.z
          local nz = a.x * b.y - a.y * b.x
          local length = math.sqrt(nx * nx + ny * ny + nz * nz)

          if length > 0.0000001 then
            nx = nx / length
            ny = ny / length
            nz = nz / length

            return {
              nx = nx,
              ny = ny,
              nz = nz,
              d = -(nx * p0.x + ny * p0.y + nz * p0.z)
            }
          end
        end
      end

      return nil
    end

    local function classify_polygon(polygon, plane)
      local min_distance = math.huge
      local max_distance = -math.huge

      for _, point in ipairs(polygon.camera_points) do
        local distance = plane_distance(plane, point)

        if distance < min_distance then
          min_distance = distance
        end

        if distance > max_distance then
          max_distance = distance
        end
      end

      if min_distance >= -BSP_EPSILON and
         max_distance <= BSP_EPSILON then
        return "coplanar"
      elseif min_distance >= -BSP_EPSILON then
        return "front"
      elseif max_distance <= BSP_EPSILON then
        return "back"
      else
        return "spanning"
      end
    end

    local function choose_splitter(polygons)
      local best_index = nil
      local best_plane = nil
      local best_score = math.huge
      local sample_count = math.min(#polygons, BSP_SPLITTER_SAMPLES)

      for candidate_index = 1, sample_count do
        local candidate = polygons[candidate_index]
        local plane = plane_from_polygon(candidate.camera_points)

        if plane then
          local front_count = 0
          local back_count = 0
          local split_count = 0

          for index, polygon in ipairs(polygons) do
            if index ~= candidate_index then
              local side = classify_polygon(polygon, plane)

              if side == "front" then
                front_count = front_count + 1
              elseif side == "back" then
                back_count = back_count + 1
              elseif side == "spanning" then
                split_count = split_count + 1
              end
            end
          end



          local score =
            split_count * 12 + math.abs(front_count - back_count)

          if score < best_score then
            best_score = score
            best_index = candidate_index
            best_plane = plane
          end
        end
      end

      return best_index, best_plane
    end

    local function append_unique_vertex(list, point)
      local previous = list[#list]

      if previous then
        local dx = previous.x - point.x
        local dy = previous.y - point.y
        local dz = previous.z - point.z

        if dx * dx + dy * dy + dz * dz < 0.0000000001 then
          return
        end
      end

      list[#list + 1] = point
    end

    local function remove_closing_duplicate(points)
      if #points < 2 then
        return
      end

      local first = points[1]
      local last = points[#points]
      local dx = first.x - last.x
      local dy = first.y - last.y
      local dz = first.z - last.z

      if dx * dx + dy * dy + dz * dz < 0.0000000001 then
        table.remove(points, #points)
      end
    end

    local function split_polygon(points, plane)
      local front_points = {}
      local back_points = {}

      for i = 1, #points do
        local a = points[i]
        local b = points[(i % #points) + 1]
        local da = plane_distance(plane, a)
        local db = plane_distance(plane, b)

        if da >= -BSP_EPSILON then
          append_unique_vertex(front_points, a)
        end

        if da <= BSP_EPSILON then
          append_unique_vertex(back_points, a)
        end

        local crosses_front_to_back =
          da > BSP_EPSILON and db < -BSP_EPSILON
        local crosses_back_to_front =
          da < -BSP_EPSILON and db > BSP_EPSILON

        if crosses_front_to_back or crosses_back_to_front then
          local t = da / (da - db)
          local intersection = {
            x = a.x + (b.x - a.x) * t,
            y = a.y + (b.y - a.y) * t,
            z = a.z + (b.z - a.z) * t
          }

          append_unique_vertex(front_points, intersection)
          append_unique_vertex(back_points, intersection)
        end
      end

      remove_closing_duplicate(front_points)
      remove_closing_duplicate(back_points)

      return front_points, back_points
    end

    local function make_polygon(points, source)
      return {
        camera_points = points,
        color = source.color,
        no_outline = source.no_outline
      }
    end

    local function build_bsp(polygons, depth)
      if #polygons == 0 then
        return nil
      end

      if depth > BSP_MAX_DEPTH then
        return { leaf = polygons }
      end

      local splitter_index, splitter_plane = choose_splitter(polygons)

      if not splitter_index or not splitter_plane then
        return { leaf = polygons }
      end

      local node = {
        plane = splitter_plane,
        coplanar = {polygons[splitter_index]},
        front = nil,
        back = nil
      }

      local front_polygons = {}
      local back_polygons = {}

      for index, polygon in ipairs(polygons) do
        if index ~= splitter_index then
          local side = classify_polygon(polygon, splitter_plane)

          if side == "front" then
            front_polygons[#front_polygons + 1] = polygon
          elseif side == "back" then
            back_polygons[#back_polygons + 1] = polygon
          elseif side == "coplanar" then
            node.coplanar[#node.coplanar + 1] = polygon
          else
            local front_points, back_points =
              split_polygon(polygon.camera_points, splitter_plane)

            if #front_points >= 3 then
              front_polygons[#front_polygons + 1] =
                make_polygon(front_points, polygon)
            end

            if #back_points >= 3 then
              back_polygons[#back_polygons + 1] =
                make_polygon(back_points, polygon)
            end
          end
        end
      end

      node.front = build_bsp(front_polygons, depth + 1)
      node.back = build_bsp(back_polygons, depth + 1)

      return node
    end

    local function polygon_average_depth(polygon)
      local total = 0

      for _, point in ipairs(polygon.camera_points) do
        total = total + point.z
      end

      return total / math.max(1, #polygon.camera_points)
    end

    local function traverse_bsp(node, output)
      if not node then
        return
      end



      if node.leaf then
        table.sort(node.leaf, function(a, b)
          return polygon_average_depth(a) > polygon_average_depth(b)
        end)

        for _, polygon in ipairs(node.leaf) do
          output[#output + 1] = polygon
        end

        return
      end



      local camera_distance = node.plane.d

      if camera_distance >= 0 then

        traverse_bsp(node.back, output)
      else

        traverse_bsp(node.front, output)
      end



      for _, polygon in ipairs(node.coplanar) do
        output[#output + 1] = polygon
      end

      if camera_distance >= 0 then
        traverse_bsp(node.front, output)
      else
        traverse_bsp(node.back, output)
      end
    end




    local scene_polygons = {}

    for _, face in ipairs(render_list) do
      local points = face.points
      local color = face.color

      if points and #points >= 3 and color then
        local camera_points = face.camera_points

        if not camera_points then
          camera_points = {}

          for _, point in ipairs(points) do
            local z = math.max(tonumber(point.z) or face.z or NEAR_PLANE,
                               NEAR_PLANE)

            camera_points[#camera_points + 1] = {
              x = (point.x - W / 2) * z / FOV,
              y = (point.y - H / 2) * z / FOV,
              z = z
            }
          end
        end

        camera_points = clip_near_plane(camera_points)

        if #camera_points >= 3 then
          scene_polygons[#scene_polygons + 1] = {
            camera_points = camera_points,
            color = color,
            no_outline = face.no_outline
          }
        end
      end
    end

    local bsp_root = build_bsp(scene_polygons, 1)
    local ordered_polygons = {}
    traverse_bsp(bsp_root, ordered_polygons)



    local ordered_render_list = {}

    for _, polygon in ipairs(ordered_polygons) do
      local points = {}
      local total_z = 0

      for _, camera_point in ipairs(polygon.camera_points) do
        local projected = project_camera_vertex(camera_point)
        points[#points + 1] = projected
        total_z = total_z + camera_point.z
      end

      ordered_render_list[#ordered_render_list + 1] = {
        points = points,
        camera_points = polygon.camera_points,
        z = total_z / #polygon.camera_points,
        color = polygon.color,
        no_outline = polygon.no_outline
      }
    end

    world.engine_render_list = ordered_render_list


    for _, face in ipairs(ordered_render_list) do
      local points = face.points
      local color = face.color

      if points and #points >= 3 and color then
        cr:set_source_rgba(
          color[1],
          color[2],
          color[3],
          math.max(0, math.min(1, tonumber(color[4]) or 1))
        )

        cr:move_to(points[1].x, points[1].y)

        for i = 2, #points do
          cr:line_to(points[i].x, points[i].y)
        end

        cr:close_path()
        cr:fill_preserve()




        if not face.no_outline and
           (color[1] ~= 0.15 or color[2] < 0.5) then
          cr:set_source_rgb(0.1, 0.1, 0.1)
          cr:set_line_width(1)
          cr:stroke()
        else
          cr:new_path()
        end
      end
    end

    return true
  end

  return drawing, world
end

return {
  add_drawing = add_drawing
}
