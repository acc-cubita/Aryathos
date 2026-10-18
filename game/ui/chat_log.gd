class_name ChatLog
extends PanelContainer
## WoW-style chat frame (bottom left) for system, XP, loot and quest messages.

const MAX_LINES := 60

var _text := RichTextLabel.new()


func _init() -> void:
	custom_minimum_size = Vector2(430, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_constant_override("outline_size", 3)
	_text.add_theme_color_override("font_outline_color", Color.BLACK)
	_text.get_v_scroll_bar().modulate.a = 0.0
	add_child(_text)
	Game.chat_message.connect(add_line)


func add_line(text: String, color: Color) -> void:
	_text.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text.replace("[", "[lb]")])
	if _text.get_paragraph_count() > MAX_LINES:
		_text.remove_paragraph(0)
