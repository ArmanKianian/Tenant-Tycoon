extends TileMapLayer

# ==================================================
# CONFIG
# ==================================================
const LINES: int = 9
const CENTER_LINE: int = 4
const CENTER_TILE: Vector2i = Vector2i(-1, 1)
const MAX_FLOORS: int = 3
const TILE_SOURCE_ID: int = 0

# --- Room Levels: just add more levels here easily ---
# Each element is a dictionary with level name (optional) and tiles
const ROOM_LEVELS: Array[Dictionary] = [
	{
		"tiles": [Vector2i(1, 1)],          # normal tile for this level
		"door_tiles": [Vector2i(1, 2)],    # special tile for first floor (door)
		"roof_tiles": [Vector2i(0, 0)]     # roof tile for this level
	},  
	{
		"tiles": [Vector2i(2, 1)],
		"door_tiles": [Vector2i(0, 2)],    # upgraded door look for level 2
		"roof_tiles": [Vector2i(0, 0)]
	}
	# add more levels if needed
]

# --- Special tiles ---
const DOOR_TILES: Array[Vector2i] = [Vector2i(1, 2)]
const ROOF_TILES: Array[Vector2i] = [Vector2i(0, 0)]

# Economy
var money: float = 500.0
const BASE_BUILD_PRICE: float = 100.0
const BASE_UPGRADE_PRICE: float = 50.0
const FLOOR_COST_GROWTH: float = 0.35
const DISTANCE_COST_GROWTH: float = 0.25
const SIDE_PRICE_MULTIPLIER: float = 1.5
const SIDE_UNLOCK_FLOORS: int = 3

# UI
var ui_hidden: bool = false
const BUTTON_TILE_OFFSET: float = 0.2
const CITIZEN_ICON_SIZE: Vector2 = Vector2(64, 64)

# Citizens
const CITIZENS: Array[Dictionary] = [
	{ "id": "worker", "icon": preload("res://icons/worker.png"), "income": 3.0 },
	{ "id": "artist", "icon": preload("res://icons/artist.png"), "income": 5.0 },
	{ "id": "rich",   "icon": preload("res://icons/rich.png"),   "income": 10.0 }
]


# ==================================================
# STATE
# ==================================================
var heights: Array[int] = []
var built: Array[bool] = []
var rooms: Array = []  # rooms[line][f] = Dictionary | null

var build_buttons: Array[Button] = []
var upgrade_buttons: Array[Button] = []

# Arrays to track citizen buttons
var room_btn_line: Array[int] = []
var room_btn_floor: Array[int] = []
var room_btn_button: Array[Button] = []

# Arrays to track room-level upgrade buttons
var room_upgrade_btn_line: Array[int] = []
var room_upgrade_btn_floor: Array[int] = []
var room_upgrade_btn_button: Array[Button] = []

var ui: Control
var money_label: Label
var camera: Camera2D
var toggle_button: Button

# ==================================================
# READY
# ==================================================
func _ready() -> void:
	clear()

	for i in range(LINES):
		heights.append(0)
		built.append(false)
		rooms.append([])

	camera = get_parent().get_node("Camera2D") as Camera2D
	camera.make_current()

	ui = get_parent().get_node("CanvasLayer/UI") as Control

	_create_money_label()
	_create_buttons()
	_create_ui_toggle()

	await get_tree().process_frame
	_update_ui()

# ==================================================
# UI CREATION (UNCHANGED)
# ==================================================
func _create_money_label() -> void:
	money_label = Label.new()
	money_label.text = "Money: $0"
	money_label.add_theme_font_size_override("font_size", 22)
	money_label.add_theme_color_override("font_color", Color(1, 1, 0.4))
	money_label.horizontal_alignment = 0 as HorizontalAlignment
	money_label.vertical_alignment   = 1 as VerticalAlignment
	money_label.position = Vector2(20, 20)
	money_label.custom_minimum_size = Vector2(200, 40)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	money_label.add_theme_stylebox_override("normal", style)

	ui.add_child(money_label)

func _create_buttons() -> void:
	for i in range(LINES):
		var build_btn = Button.new()
		build_btn.pressed.connect(func(): _on_build(i))
		ui.add_child(build_btn)
		build_buttons.append(build_btn)

		var up_btn = Button.new()
		up_btn.pressed.connect(func(): _on_upgrade(i))
		ui.add_child(up_btn)
		upgrade_buttons.append(up_btn)
		up_btn.hide()

func _create_ui_toggle() -> void:
	toggle_button = Button.new()
	toggle_button.text = "Toggle UI"
	toggle_button.custom_minimum_size = Vector2(100, 30)
	toggle_button.position = Vector2(20, 70)  # below money label
	toggle_button.pressed.connect(func(): _toggle_ui())
	ui.add_child(toggle_button)

func _toggle_ui() -> void:
	ui_hidden = not ui_hidden

	# Hide or show all UI elements except money_label and toggle_button
	for child in ui.get_children():
		if child == money_label or child == toggle_button:
			continue
		child.visible = not ui_hidden


# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
	_generate_money(delta)
	_update_ui()

# ==================================================
# MONEY
# ==================================================
func _generate_money(delta: float) -> void:
	for line in range(LINES):
		for f in range(rooms[line].size()):
			var room = rooms[line][f]
			if room != null:
				var citizen = room.get("citizen", null)
				if citizen != null:
					money += _room_income(line, f) * delta

func _room_income(line: int, floor: int) -> float:
	var room = rooms[line][floor]
	if room == null:
		return 0.0

	var citizen = room.get("citizen", null)
	if citizen == null:
		return 0.0

	var level = room.get("level", 1)
	var base_income = citizen["income"]

	# --- Calculate income multiplier ---
	# Exponential growth: each level adds ~50% more income
	# You can tweak 1.5 for a different growth factor
	var multiplier = pow(1.5, level - 1)

	return base_income * multiplier

# ==================================================
# UI UPDATE
# ==================================================
func _update_ui() -> void:
	money_label.text = "Money: $" + str(int(money))

	for i in range(LINES):
		_update_button_text(i)
		_update_button_visibility(i)
		_update_button_position(i)

	_update_room_buttons()

# ==================================================
# BUTTON TEXT
# ==================================================
func _update_button_text(line: int) -> void:
	# Build button
	var build_cost = _build_price(line)
	build_buttons[line].text = "BUILD\n$" + str(int(build_cost))
	build_buttons[line].disabled = money < build_cost or heights[line] >= MAX_FLOORS

	# Line upgrade (adds a new floor)
	if heights[line] >= MAX_FLOORS:
		upgrade_buttons[line].text = "MAX"
		upgrade_buttons[line].disabled = true
	else:
		var up_cost = _upgrade_price(line)
		upgrade_buttons[line].text = "UP\n$" + str(int(up_cost))
		upgrade_buttons[line].disabled = money < up_cost

# ==================================================
# BUILD / UPGRADE
# ==================================================
func _on_build(line: int) -> void:
	if built[line] or not _can_build(line):
		return

	var cost = _build_price(line)
	if money < cost:
		return

	money -= cost
	built[line] = true
	_add_floor(line)

	build_buttons[line].hide()
	upgrade_buttons[line].show()

func _on_upgrade(line: int) -> void:
	if not built[line] or heights[line] >= MAX_FLOORS:
		return

	var cost = _upgrade_price(line)
	if money < cost:
		return

	money -= cost
	_add_floor(line)

# ==================================================
# BUILD RULES
# ==================================================
func _can_build(line: int) -> bool:
	if line == CENTER_LINE:
		return true

	var dir = 1 if line > CENTER_LINE else -1
	var parent_line = line - dir

	return (
		parent_line >= 0
		and parent_line < LINES
		and built[parent_line]
		and heights[parent_line] >= SIDE_UNLOCK_FLOORS
	)

# ==================================================
# PRICES
# ==================================================
func _build_price(line: int) -> float:
	var distance = abs(line - CENTER_LINE)
	var price: float = BASE_BUILD_PRICE * (1.0 + distance * DISTANCE_COST_GROWTH)
	if line != CENTER_LINE:
		price *= SIDE_PRICE_MULTIPLIER
	return price

func _upgrade_price(line: int) -> float:
	var h = heights[line]
	var distance = abs(line - CENTER_LINE)
	var price: float = BASE_UPGRADE_PRICE * (1.0 + h * FLOOR_COST_GROWTH) * (1.0 + distance * DISTANCE_COST_GROWTH)
	if line != CENTER_LINE:
		price *= SIDE_PRICE_MULTIPLIER
	return price

func _room_cost(line: int, floor: int) -> float:
	var room = rooms[line][floor]
	var current_level = 1
	if room != null:
		current_level = room["level"]
	
	var distance = abs(line - CENTER_LINE)
	var cost = BASE_UPGRADE_PRICE * pow(1.35, current_level - 1)  # base growth by level
	cost *= 1.0 + floor * FLOOR_COST_GROWTH                     # grow by floor
	cost *= 1.0 + distance * DISTANCE_COST_GROWTH              # grow by distance from center

	if line != CENTER_LINE:
		cost *= SIDE_PRICE_MULTIPLIER                             # side buildings more expensive

	return cost

# ==================================================
# TILE LOGIC (DYNAMIC LEVELS)
# ==================================================
func _tile_for_line(line: int) -> Vector2i:
	return Vector2i(CENTER_TILE.x + (line - CENTER_LINE), CENTER_TILE.y)

func _add_floor(line: int) -> void:
	var base = _tile_for_line(line)
	var h = heights[line]

	var level_index: int = 1
	if h < rooms[line].size():
		# Existing room, upgrade level
		level_index = rooms[line][h]["level"] + 1

		# --- Charge cost for leveling up ---
		var cost = _room_cost(line, h)
		if money < cost:
			return  # not enough money
		money -= cost
	else:
		# New room, start at level 1
		rooms[line].append({ "level": 1, "citizen": null })

	# Limit to available levels
	if level_index > ROOM_LEVELS.size():
		level_index = ROOM_LEVELS.size()

	var level_data = ROOM_LEVELS[level_index - 1]

	# --- pick room tile ---
	var room_tile: Vector2i
	if h == 0 and level_data.has("door_tiles"):
		room_tile = level_data["door_tiles"].pick_random()
	else:
		room_tile = level_data["tiles"].pick_random()
	set_cell(Vector2i(base.x, base.y - h), TILE_SOURCE_ID, room_tile)

	# --- roof ---
	var roof_tile: Vector2i
	if level_data.has("roof_tiles"):
		roof_tile = level_data["roof_tiles"].pick_random()
	else:
		roof_tile = ROOF_TILES.pick_random()
	set_cell(Vector2i(base.x, base.y - h - 1), TILE_SOURCE_ID, roof_tile)

	# --- update room data ---
	rooms[line][h]["level"] = level_index

	# --- create room button if new ---
	if h >= heights[line]:
		_create_room_button(line, h)
		heights[line] += 1

# ==================================================
# ROOM BUTTONS (UNCHANGED)
# ==================================================
func _create_room_button(line: int, f: int) -> void:
	var base_pos = _tile_for_line(line)

	# --- Citizen assign button ---
	var btn_citizen = Button.new()
	btn_citizen.text = "+"
	btn_citizen.custom_minimum_size = Vector2(26, 26)
	btn_citizen.pressed.connect(func(): _assign_citizen(line, f))
	ui.add_child(btn_citizen)

	room_btn_line.append(line)
	room_btn_floor.append(f)
	room_btn_button.append(btn_citizen)

	# --- Upgrade button for the room (level-up) ---
	var btn_upgrade = Button.new()
	btn_upgrade.text = "UP"
	btn_upgrade.custom_minimum_size = Vector2(24, 24)
	btn_upgrade.pressed.connect(func(): _upgrade_room(line, f))
	ui.add_child(btn_upgrade)

	room_upgrade_btn_line.append(line)
	room_upgrade_btn_floor.append(f)
	room_upgrade_btn_button.append(btn_upgrade)

func _upgrade_room(line: int, f: int) -> void:
	var room = rooms[line][f]
	if room == null:
		return

	var current_level = room["level"]
	var next_level = current_level + 1

	# Limit upgrade to available levels
	if next_level > ROOM_LEVELS.size():
		return  # already max

	# Cost for upgrading this specific room level
	var cost = _room_cost(line, f)
	if money < cost:
		return  # not enough money

	money -= cost
	room["level"] = next_level

	var base = _tile_for_line(line)
	var level_data = ROOM_LEVELS[next_level - 1]

	# --- pick room tile ---
	var room_tile: Vector2i
	if f == 0 and level_data.has("door_tiles"):
		room_tile = level_data["door_tiles"].pick_random()
	else:
		room_tile = level_data["tiles"].pick_random()
	set_cell(Vector2i(base.x, base.y - f), TILE_SOURCE_ID, room_tile)

	# --- roof above topmost floor ---
	var roof_tile: Vector2i
	if level_data.has("roof_tiles"):
		roof_tile = level_data["roof_tiles"].pick_random()
	else:
		roof_tile = ROOF_TILES.pick_random()
	set_cell(Vector2i(base.x, base.y - heights[line]), TILE_SOURCE_ID, roof_tile)

func _assign_citizen(line: int, f: int) -> void:
	var room = rooms[line][f]
	if room == null:
		return  # safety check

	if room.get("citizen", null) != null:
		return  # already assigned

	var citizen = CITIZENS.pick_random()
	room["citizen"] = citizen  # assign the citizen to this room

	# Update the button UI
	for i in range(room_btn_button.size()):
		if room_btn_line[i] == line and room_btn_floor[i] == f:
			var btn = room_btn_button[i]
			btn.text = ""
			btn.disabled = true

			var img = citizen["icon"].get_image()
			var scaled = img.duplicate()
			scaled.resize(CITIZEN_ICON_SIZE.x, CITIZEN_ICON_SIZE.y)
			btn.icon = ImageTexture.create_from_image(scaled)
			btn.icon_alignment = 1
			btn.vertical_icon_alignment = 1
			return

func _update_room_buttons() -> void:
	# --- Citizen buttons ---
	for i in range(room_btn_button.size()):
		var line = room_btn_line[i]
		var f = room_btn_floor[i]
		var btn = room_btn_button[i]

		var tile = _tile_for_line(line)
		var local_pos = map_to_local(Vector2i(tile.x, tile.y - f))
		var world_pos = to_global(local_pos)
		var screen_pos = get_viewport().get_canvas_transform() * world_pos
		btn.position = screen_pos - btn.size * 0.5

	# --- Room-level upgrade buttons ---
	for i in range(room_upgrade_btn_button.size()):
		var line = room_upgrade_btn_line[i]
		var f = room_upgrade_btn_floor[i]
		var btn = room_upgrade_btn_button[i]

		var tile = _tile_for_line(line)
		var local_pos = map_to_local(Vector2i(tile.x, tile.y - f))
		var world_pos = to_global(local_pos)
		var screen_pos = get_viewport().get_canvas_transform() * world_pos
		btn.position = screen_pos - btn.size * 0.5 + Vector2(0, -28)  # slightly above

		# --- Check max level for this room ---
		var room = rooms[line][f]
		if room != null:
			var current_level = room["level"]
			if current_level >= ROOM_LEVELS.size():
				btn.text = "MAX"
				btn.disabled = true
			else:
				# Calculate the upgrade cost for this specific room
				var cost = int(_room_cost(line, f))
				btn.text = "UP\n$" + str(cost)
				btn.disabled = money < cost

# ==================================================
# BUTTON VISIBILITY & POSITION
# ==================================================
func _update_button_visibility(line: int) -> void:
	build_buttons[line].visible = not built[line] and _can_build(line)
	upgrade_buttons[line].visible = built[line]

func _update_button_position(line: int) -> void:
	var btn: Button
	var is_upgrade = false

	if build_buttons[line].visible:
		btn = build_buttons[line]
	elif upgrade_buttons[line].visible:
		btn = upgrade_buttons[line]
		is_upgrade = true
	else:
		return

	var tile = _tile_for_line(line)
	var floors = heights[line] - (1 if is_upgrade else 0)

	var local_pos = map_to_local(Vector2i(tile.x, tile.y - floors - 1))
	local_pos.y -= tile_set.tile_size.y * BUTTON_TILE_OFFSET

	var world_pos = to_global(local_pos)
	var screen_pos = get_viewport().get_canvas_transform() * world_pos
	btn.position = screen_pos - btn.size * 0.5
