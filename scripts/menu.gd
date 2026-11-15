extends Control
## Title screen and pause menu. Keeps working while the game tree is paused.

signal play_pressed
signal new_world_pressed
signal resume_pressed
signal music_pressed
signal title_pressed
signal quit_pressed

enum { HIDDEN, TITLE, PAUSE }

var mode := HIDDEN
var has_save := false
var music_on := true

var _box: VBoxContainer
var _title: Label
var _note: Label
var _confirm_new := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.10, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	centre.add_child(_box)


func show_title(saved: bool) -> void:
	has_save = saved
	_confirm_new = false
	mode = TITLE
	_rebuild()


func show_pause() -> void:
	mode = PAUSE
	_rebuild()


func hide_menu() -> void:
	mode = HIDDEN
	visible = false


func _rebuild() -> void:
	for child in _box.get_children():
		child.queue_free()
	visible = true

	_title = Label.new()
	_title.text = "KUBIYA" if mode == TITLE else "Paused"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 86 if mode == TITLE else 48)
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35) if mode == TITLE else Color.WHITE)
	_title.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.02))
	_title.add_theme_constant_override("outline_size", 14)
	_box.add_child(_title)

	if mode == TITLE:
		_note = _line("An original block world. Build, craft, survive the night.")
		_button("Continue" if has_save else "Start", func() -> void: play_pressed.emit())
		if has_save:
			_button("New world", _on_new_world)
		_button("Quit", func() -> void: quit_pressed.emit())
	else:
		_note = _line("The game is saved when you leave.")
		_button("Resume", func() -> void: resume_pressed.emit())
		_button("Music: on" if music_on else "Music: off", _on_music)
		_button("Save and go to title", func() -> void: title_pressed.emit())
		_button("Save and quit", func() -> void: quit_pressed.emit())


func _line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.modulate = Color(1, 1, 1, 0.85)
	_box.add_child(l)
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 58)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	_box.add_child(b)
	return b


## Starting a new world erases the saved one, so it takes two clicks.
func _on_new_world() -> void:
	if not _confirm_new:
		_confirm_new = true
		_note.text = "This erases the saved world. Click \"New world\" again to confirm."
		_note.modulate = Color(1.0, 0.6, 0.5)
		return
	new_world_pressed.emit()


func _on_music() -> void:
	music_pressed.emit()
	_rebuild()
