local lgi = require("lgi")
local GLib = lgi.GLib
local audio = require("audio")

local function attach_player(drawing, world)
  local player = {
    x = 0, y = -1.0, z = 0,
    vy = 0, is_grounded = false,
    walk_cycle = 0,
    yaw = 0
  }

  table.insert(world.entities, player)

  local cam = { yaw = 0, pitch = 0.3, dist = 12.0, height = 2.0 }
  local keys = {}
  local is_dragging = false
  local last_mouse_x, last_mouse_y = 0, 0

  local last_time = GLib.get_monotonic_time()

  audio.init()

  drawing:add_events(lgi.Gdk.EventMask.BUTTON_PRESS_MASK + lgi.Gdk.EventMask.BUTTON_RELEASE_MASK +
                     lgi.Gdk.EventMask.POINTER_MOTION_MASK + lgi.Gdk.EventMask.KEY_PRESS_MASK +
                     lgi.Gdk.EventMask.KEY_RELEASE_MASK)

  drawing.on_key_press_event = function(widget, event) keys[event.keyval] = true; return true end
  drawing.on_key_release_event = function(widget, event) keys[event.keyval] = false; return true end
  drawing.on_button_press_event = function(widget, event) if event.button == 1 then is_dragging = true; last_mouse_x, last_mouse_y = event.x, event.y end; return true end
  drawing.on_button_release_event = function(widget, event) if event.button == 1 then is_dragging = false end; return true end

  drawing.on_motion_notify_event = function(widget, event)
    if is_dragging then
      cam.yaw = cam.yaw + (event.x - last_mouse_x) * 0.005
      cam.pitch = cam.pitch + (event.y - last_mouse_y) * 0.005
      if cam.pitch > math.pi / 2 - 0.1 then cam.pitch = math.pi / 2 - 0.1 end
      if cam.pitch < -0.2 then cam.pitch = -0.2 end
      last_mouse_x, last_mouse_y = event.x, event.y
      widget:queue_draw()
    end
    return true
  end

  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, function()
    local current_time = GLib.get_monotonic_time()
    local dt = (current_time - last_time) / 1000000.0
    last_time = current_time
    if dt > 0.1 then dt = 0.1 end
    local dt_scale = dt * 60.0

    local speed = 0.15
    local sin_y, cos_y = math.sin(cam.yaw), math.cos(cam.yaw)

    if keys[105] then cam.dist = math.max(4.0, cam.dist - (0.2 * dt_scale)) end
    if keys[111] then cam.dist = math.min(30.0, cam.dist + (0.2 * dt_scale)) end

    local nx, ny, nz = player.x, player.y, player.z
    local is_moving = false

    if keys[32] and player.is_grounded then
      player.vy = -0.7
      player.is_grounded = false
      keys[32] = false
    end

    if keys[119] or keys[87] then nx = nx + sin_y * speed * dt_scale; nz = nz + cos_y * speed * dt_scale; is_moving = true end
    if keys[115] or keys[83] then nx = nx - sin_y * speed * dt_scale; nz = nz - cos_y * speed * dt_scale; is_moving = true end
    if keys[97] or keys[65] then nx = nx - cos_y * speed * dt_scale; nz = nz + sin_y * speed * dt_scale; is_moving = true end
    if keys[100] or keys[68] then nx = nx + cos_y * speed * dt_scale; nz = nz - sin_y * speed * dt_scale; is_moving = true end

    player.vy = player.vy + (0.03 * dt_scale)
    if player.vy > 1.5 then player.vy = 1.5 end
    ny = ny + (player.vy * dt_scale)
    player.is_grounded = false

    local pw, ph, pd = 0.4, 0.9, 0.4
    local p_min_y, p_max_y = ny - ph, ny + ph

    for _, box in ipairs(world.colliders) do
      local bw, bh, bd = box.w / 2, box.h / 2, box.d / 2
      local b_min_x, b_max_x = box.x - bw, box.x + bw
      local b_min_y, b_max_y = box.y - bh, box.y + bh
      local b_min_z, b_max_z = box.z - bd, box.z + bd

      if (nx - pw < b_max_x and nx + pw > b_min_x) and (nz - pd < b_max_z and nz + pd > b_min_z) then
        if player.vy > 0 and p_max_y > b_min_y and p_min_y < b_min_y then
          ny = b_min_y - ph; player.vy = 0; player.is_grounded = true
        elseif player.vy < 0 and p_min_y < b_max_y and p_max_y > b_max_y then
          ny = b_max_y + ph; player.vy = 0
        end
      end
    end

    p_min_y, p_max_y = ny - ph, ny + ph
    for _, box in ipairs(world.colliders) do
      local bw, bh, bd = box.w / 2, box.h / 2, box.d / 2
      local b_min_x, b_max_x = box.x - bw, box.x + bw
      local b_min_y, b_max_y = box.y - bh, box.y + bh
      local b_min_z, b_max_z = box.z - bd, box.z + bd

      if (p_min_y < b_max_y and p_max_y > b_min_y) and (nz - pd < b_max_z and nz + pd > b_min_z) then
        if nx + pw > b_min_x and nx - pw < b_min_x then

          if box.w < 30 then box.x = box.x + (nx + pw - b_min_x) * 1.1 end
          nx = b_min_x - pw
        elseif nx - pw < b_max_x and nx + pw > b_max_x then
          if box.w < 30 then box.x = box.x - (b_max_x - (nx - pw)) * 1.1 end
          nx = b_max_x + pw
        end
      end
    end

    for _, box in ipairs(world.colliders) do
      local bw, bh, bd = box.w / 2, box.h / 2, box.d / 2
      local b_min_x, b_max_x = box.x - bw, box.x + bw
      local b_min_y, b_max_y = box.y - bh, box.y + bh
      local b_min_z, b_max_z = box.z - bd, box.z + bd

      if (p_min_y < b_max_y and p_max_y > b_min_y) and (nx - pw < b_max_x and nx + pw > b_min_x) then
        if nz + pd > b_min_z and nz - pd < b_min_z then
          if box.d < 30 then box.z = box.z + (nz + pd - b_min_z) * 1.1 end
          nz = b_min_z - pd
        elseif nz - pd < b_max_z and nz + pd > b_max_z then
          if box.d < 30 then box.z = box.z - (b_max_z - (nz - pd)) * 1.1 end
          nz = b_max_z + pd
        end
      end
    end

    if ny > 50 then nx, ny, nz = 0, -1.0, 0; player.vy = 0 end

    player.x, player.y, player.z = nx, ny, nz

    if is_moving then
      local move_dx = nx - player.x
      local move_dz = nz - player.z
      if move_dx ~= 0 or move_dz ~= 0 then player.yaw = math.atan2(move_dx, move_dz) end
    end

    if is_moving and player.is_grounded then
      player.walk_cycle = player.walk_cycle + (0.2 * dt_scale)
    else
      player.walk_cycle = player.walk_cycle * (0.8 ^ dt_scale)
    end

    audio.update(player.x, player.y, player.z, cam.yaw, 5, -1, 5)

    world.active_camera.x = player.x - math.sin(cam.yaw) * cam.dist * math.cos(cam.pitch)
    world.active_camera.y = player.y - math.sin(cam.pitch) * cam.dist - cam.height
    world.active_camera.z = player.z - math.cos(cam.yaw) * cam.dist * math.cos(cam.pitch)
    world.active_camera.rot_y = cam.yaw
    world.active_camera.rot_x = cam.pitch

    drawing:queue_draw()
    return true
  end)

  table.insert(world.custom_draws, function(render_list, project)
    local sin_y, cos_y = math.sin(player.yaw), math.cos(player.yaw)
    local function rp(lx, ly, lz)
      local x1 = lx * cos_y - lz * sin_y
      local z1 = lx * sin_y + lz * cos_y
      return { player.x + x1, player.y + ly, player.z + z1 }
    end

    local swing_angle = math.sin(player.walk_cycle) * 0.5
    local arm_angle_l = swing_angle
    local arm_angle_r = -swing_angle
    local leg_angle_l = -swing_angle
    local leg_angle_r = swing_angle

    local function add_limb(pivot_ly, is_arm, angle, side)
      local limb_len = is_arm and 0.5 or 0.6
      local limb_w = 0.15
      local limb_d = 0.15
      local offset_y = limb_len / 2
      local offset_z = 0
      local rot_y = offset_y * math.cos(angle) - offset_z * math.sin(angle)
      local rot_z = offset_y * math.sin(angle) + offset_z * math.cos(angle)
      local center = rp(side, pivot_ly + rot_y, rot_z)
      local hw, hh, hd = limb_w/2, limb_len/2, limb_d/2
      local v = {
        { center[1]-hw, center[2]-hh, center[3]-hd }, { center[1]+hw, center[2]-hh, center[3]-hd },
        { center[1]+hw, center[2]+hh, center[3]-hd }, { center[1]-hw, center[2]+hh, center[3]-hd },
        { center[1]-hw, center[2]-hh, center[3]+hd }, { center[1]+hw, center[2]-hh, center[3]+hd },
        { center[1]+hw, center[2]+hh, center[3]+hd }, { center[1]-hw, center[2]+hh, center[3]+hd }
      }
      local f = { {1, 2, 3, 4}, {5, 6, 7, 8}, {1, 5, 8, 4}, {2, 6, 7, 3}, {4, 3, 7, 8}, {1, 5, 6, 2} }
      local proj_v = {}
      for i, vert in ipairs(v) do
        local px, py, pz = project(vert[1], vert[2], vert[3])
        proj_v[i] = { x = px, y = py, z = pz }
      end
      for i, face in ipairs(f) do
        local avg_z = (proj_v[face[1]].z + proj_v[face[2]].z + proj_v[face[3]].z + proj_v[face[4]].z) / 4
        table.insert(render_list, { points = { proj_v[face[1]], proj_v[face[2]], proj_v[face[3]], proj_v[face[4]] }, z = avg_z, color = { 0.2, 0.4, 0.8 } })
      end
    end

    local head_center = rp(0, -0.7, 0)
    local hw, hh, hd = 0.35/2, 0.35/2, 0.35/2
    local v_head = {
        { head_center[1]-hw, head_center[2]-hh, head_center[3]-hd }, { head_center[1]+hw, head_center[2]-hh, head_center[3]-hd },
        { head_center[1]+hw, head_center[2]+hh, head_center[3]-hd }, { head_center[1]-hw, head_center[2]+hh, head_center[3]-hd },
        { head_center[1]-hw, head_center[2]-hh, head_center[3]+hd }, { head_center[1]+hw, head_center[2]-hh, head_center[3]+hd },
        { head_center[1]+hw, head_center[2]+hh, head_center[3]+hd }, { head_center[1]-hw, head_center[2]+hh, head_center[3]+hd }
    }
    local f_head = {{1, 2, 3, 4}, {5, 6, 7, 8}, {1, 5, 8, 4}, {2, 6, 7, 3}, {4, 3, 7, 8}, {1, 5, 6, 2}}
    local proj_head = {}
    for i, vert in ipairs(v_head) do
        local px, py, pz = project(vert[1], vert[2], vert[3])
        proj_head[i] = { x = px, y = py, z = pz }
    end
    for i, face in ipairs(f_head) do
        local avg_z = (proj_head[face[1]].z + proj_head[face[2]].z + proj_head[face[3]].z + proj_head[face[4]].z) / 4
        table.insert(render_list, { points = { proj_head[face[1]], proj_head[face[2]], proj_head[face[3]], proj_head[face[4]] }, z = avg_z, color = { 0.2, 0.4, 0.8 } })
    end

    local torso_center = rp(0, 0, 0)
    local tw, th, td = 0.5/2, 0.6/2, 0.3/2
    local v_torso = {
        { torso_center[1]-tw, torso_center[2]-th, torso_center[3]-td }, { torso_center[1]+tw, torso_center[2]-th, torso_center[3]-td },
        { torso_center[1]+tw, torso_center[2]+th, torso_center[3]-td }, { torso_center[1]-tw, torso_center[2]+th, torso_center[3]-td },
        { torso_center[1]-tw, torso_center[2]-th, torso_center[3]+td }, { torso_center[1]+tw, torso_center[2]-th, torso_center[3]+td },
        { torso_center[1]+tw, torso_center[2]+th, torso_center[3]+td }, { torso_center[1]-tw, torso_center[2]+th, torso_center[3]+td }
    }
    local f_torso = {{1, 2, 3, 4}, {5, 6, 7, 8}, {1, 5, 8, 4}, {2, 6, 7, 3}, {4, 3, 7, 8}, {1, 5, 6, 2}}
    local proj_torso = {}
    for i, vert in ipairs(v_torso) do
        local px, py, pz = project(vert[1], vert[2], vert[3])
        proj_torso[i] = { x = px, y = py, z = pz }
    end
    for i, face in ipairs(f_torso) do
        local avg_z = (proj_torso[face[1]].z + proj_torso[face[2]].z + proj_torso[face[3]].z + proj_torso[face[4]].z) / 4
        table.insert(render_list, { points = { proj_torso[face[1]], proj_torso[face[2]], proj_torso[face[3]], proj_torso[face[4]] }, z = avg_z, color = { 0.1, 0.2, 0.5 } })
    end

    add_limb(-0.1, true, arm_angle_l, -0.35)
    add_limb(-0.1, true, arm_angle_r, 0.35)
    add_limb(0.3, false, leg_angle_l, -0.15)
    add_limb(0.3, false, leg_angle_r, 0.15)
  end)
end

return { attach_player = attach_player }
