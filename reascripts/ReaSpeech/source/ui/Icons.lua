--[[

  Icons.lua - Drawable icons

]]--

Icons = {}

function Icons.pencil(dl, x, y, w, h, color)
  -- Tip of pencil
  ImGui.DrawList_AddTriangleFilled(
    dl,
    x,
    y + h,
    x + w * 0.1,
    y + h * 0.7,
    x + w * 0.3,
    y + h * 0.9,
    color)

  -- Body of pencil
  ImGui.DrawList_AddQuadFilled(
    dl,
    x + w * 0.15,
    y + h * 0.65,
    x + w * 0.65,
    y + h * 0.15,
    x + w * 0.85,
    y + h * 0.35,
    x + w * 0.35,
    y + h * 0.85,
    color)

  -- Eraser
  ImGui.DrawList_AddQuadFilled(
    dl,
    x + w * 0.7,
    y + h * 0.1,
    x + w * 0.8,
    y,
    x + w,
    y + h * 0.2,
    x + w * 0.9,
    y + h * 0.3,
    color)
end

function Icons.play(dl, x, y, w, h, color)
  ImGui.DrawList_AddCircle(
    dl,
    x + w * 0.5,
    y + h * 0.5,
    w * 0.5,
    color,
    20)
  ImGui.DrawList_AddTriangleFilled(
    dl,
    x + w * 0.35,
    y + h * 0.25,
    x + w * 0.75,
    y + h * 0.5,
    x + w * 0.35,
    y + h * 0.75,
    color)
end

function Icons.stop(dl, x, y, w, h, color)
  ImGui.DrawList_AddCircle(
    dl,
    x + w * 0.5,
    y + h * 0.5,
    w * 0.5,
    color,
    20)
  ImGui.DrawList_AddRectFilled(
    dl,
    x + w * 0.3,
    y + h * 0.3,
    x + w * 0.7,
    y + h * 0.7,
    color)
end

function Icons.gear(dl, x, y, w, h, color)
  local center_x = x + (w - 1) * 0.5
  local center_y = y + (h - 1) * 0.5
  local circle_radius = w * 0.15
  local inner_radius = w * 0.3
  local outer_radius = w * 0.4
  local num_teeth = 6

  local points = Icons._gear_points(center_x, center_y, inner_radius, outer_radius, num_teeth)

  ImGui.DrawList_AddCircleFilled(dl, x + w * 0.5, y + h * 0.5, circle_radius, color, 20)
  for i = 1, #points - 2, 2 do
    ImGui.DrawList_AddLine(dl, points[i], points[i + 1], points[i + 2], points[i + 3], color, 1)
  end
end

Icons._gear_points_cache = {}

function Icons._gear_points(center_x, center_y, inner_radius, outer_radius, num_teeth)
  local cache_key = table.concat({center_x, center_y, inner_radius, outer_radius, num_teeth}, ",")
  if Icons._gear_points_cache[cache_key] then
    return Icons._gear_points_cache[cache_key]
  end

  local angle_step = 2 * math.pi / num_teeth
  local angle_start = angle_step * 0.6
  local points = {}

  for i = 0, num_teeth - 1 do
    local angle = angle_start + i * angle_step
    table.insert(points, center_x + inner_radius * math.cos(angle))
    table.insert(points, center_y + inner_radius * math.sin(angle))
    table.insert(points, center_x + outer_radius * math.cos(angle + angle_step * 0.25))
    table.insert(points, center_y + outer_radius * math.sin(angle + angle_step * 0.25))
    table.insert(points, center_x + outer_radius * math.cos(angle + angle_step * 0.5))
    table.insert(points, center_y + outer_radius * math.sin(angle + angle_step * 0.5))
    table.insert(points, center_x + inner_radius * math.cos(angle + angle_step * 0.75))
    table.insert(points, center_y + inner_radius * math.sin(angle + angle_step * 0.75))
  end

  table.insert(points, points[1])
  table.insert(points, points[2])

  Icons._gear_points_cache[cache_key] = points
  return points
end

function Icons.spinner(dl, x, y, w, h, color)
  local cx = x + w * 0.5
  local cy = y + h * 0.5
  local radius = w * 0.45
  local num_dots = 8
  local time = reaper.time_precise()
  local active = math.floor(time / 0.1) % num_dots

  for i = 0, num_dots - 1 do
    local angle = (i / num_dots) * 2 * math.pi - math.pi / 2
    local dx = cx + radius * math.cos(angle)
    local dy = cy + radius * math.sin(angle)

    -- Fade dots based on distance from active dot
    local dist = (i - active) % num_dots
    local alpha = math.max(0.15, 1.0 - dist * 0.12)
    local dot_radius = w * 0.08

    -- Apply alpha to color (color is 0xRRGGBBAA)
    local base_rgb = color & 0xFFFFFF00
    local dot_color = base_rgb | math.floor(alpha * 255)

    ImGui.DrawList_AddCircleFilled(dl, dx, dy, dot_radius, dot_color, 8)
  end
end

function Icons.info(dl, x, y, w, h, color)
  ImGui.DrawList_AddCircle(
    dl,
    x + w * 0.5,
    y + h * 0.5,
    w * 0.5,
    color,
    20)
  -- Dot of the i
  ImGui.DrawList_AddRectFilled(
    dl,
    x + w * 0.46,
    y + h * 0.3,
    x + w * 0.54,
    y + h * 0.35,
    color)
  -- Body of the i
  ImGui.DrawList_AddRectFilled(
    dl,
    x + w * 0.46,
    y + h * 0.45,
    x + w * 0.54,
    y + h * 0.7,
    color)
end
