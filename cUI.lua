local lgi = require("lgi")
local Gtk = lgi.require("Gtk", "3.0")
local GLib = lgi.GLib

local M = {}

local PHI = (1 + math.sqrt(5)) / 2
local sphere_vertices = {
    {-1,  PHI,  0},
    { 1,  PHI,  0},
    {-1, -PHI,  0},
    { 1, -PHI,  0},
    { 0, -1,  PHI},
    { 0,  1,  PHI},
    { 0, -1, -PHI},
    { 0,  1, -PHI},
    { PHI, 0, -1},
    { PHI, 0,  1},
    {-PHI, 0, -1},
    {-PHI, 0,  1}
}

local sphere_faces = {
    {1, 12, 6}, {1, 6, 2}, {1, 2, 8}, {1, 8, 11}, {1, 11, 12},
    {2, 6, 10}, {6, 12, 5}, {12, 11, 3}, {11, 8, 7}, {8, 2, 9},
    {4, 10, 5}, {4, 5, 3}, {4, 3, 7}, {4, 7, 9}, {4, 9, 10},
    {5, 10, 6}, {3, 5, 12}, {7, 3, 11}, {9, 7, 8}, {10, 9, 2}
}

for _, vertex in ipairs(sphere_vertices) do
    local length = math.sqrt(
        vertex[1] * vertex[1] +
        vertex[2] * vertex[2] +
        vertex[3] * vertex[3]
    )

    vertex[1] = vertex[1] / length
    vertex[2] = vertex[2] / length
    vertex[3] = vertex[3] / length
end

local function register_sphere_renderer(world)
    world.spawned_spheres = world.spawned_spheres or {}
    world.custom_draws = world.custom_draws or {}

    if world._cui_sphere_draw_registered then
        return
    end

    world._cui_sphere_draw_registered = true

    table.insert(world.custom_draws, function(render_list, project)
        for _, sphere in ipairs(world.spawned_spheres) do
            local radius = sphere.radius or 0.75
            local positions = {}

            for index, vertex in ipairs(sphere_vertices) do
                positions[index] = {
                    sphere.x + vertex[1] * radius,
                    sphere.y + vertex[2] * radius,
                    sphere.z + vertex[3] * radius
                }
            end

            for _, face in ipairs(sphere_faces) do
                local a = positions[face[1]]
                local b = positions[face[2]]
                local c = positions[face[3]]

                local abx, aby, abz =
                    b[1] - a[1], b[2] - a[2], b[3] - a[3]
                local acx, acy, acz =
                    c[1] - a[1], c[2] - a[2], c[3] - a[3]

                local nx = aby * acz - abz * acy
                local ny = abz * acx - abx * acz
                local nz = abx * acy - aby * acx

                local normal_length = math.sqrt(nx * nx + ny * ny + nz * nz)

                if normal_length > 0 then
                    nx, ny, nz =
                        nx / normal_length,
                        ny / normal_length,
                        nz / normal_length
                end

                local cx = (a[1] + b[1] + c[1]) / 3 - sphere.x
                local cy = (a[2] + b[2] + c[2]) / 3 - sphere.y
                local cz = (a[3] + b[3] + c[3]) / 3 - sphere.z

                if nx * cx + ny * cy + nz * cz < 0 then
                    nx, ny, nz = -nx, -ny, -nz
                end

                local light_dot =
                    nx * -0.35 + ny * -0.80 + nz * -0.48
                local brightness = 0.38 + 0.62 * math.max(0, light_dot)

                local pa_x, pa_y, pa_z = project(a[1], a[2], a[3])
                local pb_x, pb_y, pb_z = project(b[1], b[2], b[3])
                local pc_x, pc_y, pc_z = project(c[1], c[2], c[3])

                local points = {
                    {x = pa_x, y = pa_y, z = pa_z},
                    {x = pb_x, y = pb_y, z = pb_z},
                    {x = pc_x, y = pc_y, z = pc_z}
                }

                render_list[#render_list + 1] = {
                    points = points,
                    z = (pa_z + pb_z + pc_z) / 3,
                    color = {
                        math.min(1, sphere.r * brightness),
                        math.min(1, sphere.g * brightness),
                        math.min(1, sphere.b * brightness)
                    }
                }
            end
        end
    end)
end

local function start_sphere_physics(world, drawing_area)
    if world._cui_sphere_physics_started then
        return
    end

    world._cui_sphere_physics_started = true
    world.spawned_spheres = world.spawned_spheres or {}

    local PHYSICS_STEP = 0.016
    local MAX_CATCHUP_STEPS = 8
    local MAX_FRAME_DELTA = PHYSICS_STEP * MAX_CATCHUP_STEPS
    local accumulator = 0
    local last_time = GLib.get_monotonic_time()

    local function update_spheres()
        for i = #world.spawned_spheres, 1, -1 do
            local sphere = world.spawned_spheres[i]

            sphere.vy = sphere.vy + 0.04

            sphere.x = sphere.x + sphere.vx
            sphere.y = sphere.y + sphere.vy
            sphere.z = sphere.z + sphere.vz

            sphere.vx = sphere.vx * 0.90
            sphere.vz = sphere.vz * 0.90

            local is_over_floor =
                math.abs(sphere.x) <= 15 and
                math.abs(sphere.z) <= 15

            if is_over_floor then
                if sphere.y + sphere.radius >= 2.0 then
                    sphere.y = 2.0 - sphere.radius
                    sphere.vy = 0
                end
            elseif sphere.y > 50 then
                table.remove(world.spawned_spheres, i)
            end
        end
    end

    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, function()
        local now = GLib.get_monotonic_time()
        local elapsed = (now - last_time) / 1000000
        last_time = now

        if elapsed < 0 then
            elapsed = 0
        elseif elapsed > MAX_FRAME_DELTA then
            elapsed = MAX_FRAME_DELTA
        end

        accumulator = math.min(accumulator + elapsed, MAX_FRAME_DELTA)

        local steps = 0
        while accumulator >= PHYSICS_STEP and steps < MAX_CATCHUP_STEPS do
            update_spheres()
            accumulator = accumulator - PHYSICS_STEP
            steps = steps + 1
        end

        drawing_area:queue_draw()
        return true
    end)
end

local function get_spawn_position(world)
    local player = world.entities and world.entities[1]
    local camera = world.active_camera or {}

    local x = (player and tonumber(player.x)) or tonumber(camera.x) or 0
    local z = (player and tonumber(player.z)) or tonumber(camera.z) or 0
    local yaw = (player and tonumber(player.yaw)) or tonumber(camera.rot_y) or 0

    local spawn_dist = 3.0

    return
        x + math.sin(yaw) * spawn_dist,
        -3.0,
        z + math.cos(yaw) * spawn_dist
end

function M.add_ui(win, drawing_area, world)
    register_sphere_renderer(world)

    local overlay = Gtk.Overlay()
    overlay:set_hexpand(true)
    overlay:set_vexpand(true)
    drawing_area:set_hexpand(true)
    drawing_area:set_vexpand(true)
    overlay:add(drawing_area)

    local ui_box = Gtk.Box()
    ui_box:set_orientation(Gtk.Orientation.VERTICAL)
    ui_box:set_halign(Gtk.Align.CENTER)
    ui_box:set_valign(Gtk.Align.END)
    ui_box:set_margin_bottom(30)
    ui_box:set_spacing(10)

    local creator_btn = Gtk.Button()
    creator_btn:set_label("Creator Panel")

    local btn_css = Gtk.CssProvider()
    btn_css:load_from_data([[
        button {
            background-color: rgba(60, 60, 60, 0.85);
            color: rgba(255, 255, 255, 1.0);
            font-weight: bold;
            font-size: 16px;
            letter-spacing: 2px;
            border-radius: 20px;
            padding: 8px 24px;
            border: 2px solid rgba(255, 255, 255, 0.2);
            text-shadow: 1px 1px 2px black;
            box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.5);
        }
        button:hover {
            background-color: rgba(80, 80, 80, 0.9);
            border: 2px solid rgba(255, 255, 255, 0.5);
        }
        button:active {
            background-color: rgba(40, 40, 40, 1.0);
        }
    ]])
    creator_btn:get_style_context():add_provider(
        btn_css,
        Gtk.STYLE_PROVIDER_PRIORITY_USER
    )

    creator_btn.on_clicked = function()
        local dialog = Gtk.Window()
        dialog:set_title("Creator Menu")
        dialog:set_default_size(320, 260)
        dialog:set_transient_for(win)
        dialog:set_modal(true)
        dialog:set_position(Gtk.WindowPosition.CENTER_ON_PARENT)

        local dlg_box = Gtk.Box()
        dlg_box:set_orientation(Gtk.Orientation.VERTICAL)
        dlg_box:set_spacing(15)
        dlg_box:set_margin_top(20)
        dlg_box:set_margin_bottom(20)
        dlg_box:set_margin_start(20)
        dlg_box:set_margin_end(20)

        local function close_dialog()
            dialog:destroy()
            drawing_area:grab_focus()
        end

        local spawn_cube_btn = Gtk.Button()
        spawn_cube_btn:set_label("Spawn Cube")

        spawn_cube_btn.on_clicked = function()
            local spawn_x, spawn_y, spawn_z = get_spawn_position(world)

            world.colliders = world.colliders or {}
            table.insert(world.colliders, {
                x = spawn_x,
                y = spawn_y,
                z = spawn_z,
                w = 1.5,
                h = 1.5,
                d = 1.5,
                r = math.random(),
                g = math.random(),
                b = math.random(),
                vx = 0,
                vy = 0,
                vz = 0,
                pitch = 0,
                roll = 0,
                vp = 0,
                vr = 0
            })

            close_dialog()
        end

        local spawn_sphere_btn = Gtk.Button()
        spawn_sphere_btn:set_label("Spawn Sphere")

        spawn_sphere_btn.on_clicked = function()
            local spawn_x, spawn_y, spawn_z = get_spawn_position(world)

            world.spawned_spheres = world.spawned_spheres or {}
            table.insert(world.spawned_spheres, {
                x = spawn_x,
                y = spawn_y,
                z = spawn_z,
                radius = 0.85,
                r = math.random(),
                g = math.random(),
                b = math.random(),
                vx = 0,
                vy = 0,
                vz = 0
            })

            start_sphere_physics(world, drawing_area)
            drawing_area:queue_draw()
            close_dialog()
        end

        local close_btn = Gtk.Button()
        close_btn:set_label("Close")
        close_btn.on_clicked = close_dialog

        dlg_box:pack_start(spawn_cube_btn, false, false, 0)
        dlg_box:pack_start(spawn_sphere_btn, false, false, 0)
        dlg_box:pack_start(close_btn, false, false, 0)

        dialog:add(dlg_box)
        dialog:show_all()
    end

    ui_box:pack_start(creator_btn, false, false, 0)
    overlay:add_overlay(ui_box)

    for _, child in ipairs(win:get_children()) do
        win:remove(child)
    end
    win:add(overlay)

    drawing_area:set_can_focus(true)
    drawing_area:grab_focus()
end

return M
