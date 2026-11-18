# scenes/main_hub/profile.gd
# User profile configuration screen integrating ProfileService, AudioControls, and BackupService.
class_name ProfileScreen extends Control

signal back_requested
signal profile_saved(profile: Dictionary)

const ProfileServiceScript = preload("res://core/profile/profile_service.gd")
const AudioControlsScript = preload("res://core/qol/audio_controls.gd")
const BackupServiceScript = preload("res://core/profile/backup_service.gd")
const UIThemeScript = preload("res://core/visuals/deckbox_ui_theme.gd")
const I18nServiceScript = preload("res://core/i18n/i18n_service.gd")

var _profile_svc: RefCounted
var _audio_controls: RefCounted
var _backup_svc: RefCounted

@onready var name_input: LineEdit = $VBoxContainer/TabContainer/Identity/Grid/NameEdit
@onready var theme_picker: OptionButton = $VBoxContainer/TabContainer/Identity/Grid/ThemeOption
@onready var quality_picker: OptionButton = $VBoxContainer/TabContainer/Identity/Grid/QualityOption
@onready var card_back_picker: OptionButton = $VBoxContainer/TabContainer/Identity/Grid/CardBackOption
@onready var colorblind_check: CheckButton = $VBoxContainer/TabContainer/Accessibility/Grid/ColorblindCheck
@onready var master_slider: HSlider = $VBoxContainer/TabContainer/Accessibility/Grid/MasterSlider
@onready var music_slider: HSlider = $VBoxContainer/TabContainer/Accessibility/Grid/MusicSlider
@onready var sfx_slider: HSlider = $VBoxContainer/TabContainer/Accessibility/Grid/SfxSlider
@onready var anim_slider: HSlider = $VBoxContainer/TabContainer/Accessibility/Grid/AnimSlider
@onready var status_label: Label = $VBoxContainer/Footer/StatusLabel

func _ready() -> void:
	theme = UIThemeScript.create_theme()
	_profile_svc = ProfileServiceScript.new()
	_audio_controls = AudioControlsScript.new()
	_backup_svc = BackupServiceScript.new()

	_init_pickers()
	load_current_profile()
	apply_language()

func apply_language() -> void:
	var title_lbl = get_node_or_null("VBoxContainer/Header/Title")
	if title_lbl != null and "text" in title_lbl:
		title_lbl.text = I18nServiceScript.t("profile.title")
	var back_btn = get_node_or_null("VBoxContainer/Header/BackButton")
	if back_btn != null and "text" in back_btn:
		back_btn.text = I18nServiceScript.t("profile.back")
	var save_btn = get_node_or_null("VBoxContainer/Header/SaveButton")
	if save_btn != null and "text" in save_btn:
		save_btn.text = I18nServiceScript.t("profile.save")

func _init_pickers() -> void:
	if theme_picker:
		theme_picker.clear()
		theme_picker.add_item("Arcade PS5", 0)
		theme_picker.set_item_metadata(0, "arcade_ps5")
		theme_picker.add_item("Cozy Wood", 1)
		theme_picker.set_item_metadata(1, "cozy_wood")
		theme_picker.add_item("Clean 2.5D", 2)
		theme_picker.set_item_metadata(2, "clean_25d")

	if quality_picker:
		quality_picker.clear()
		quality_picker.add_item("High", 0)
		quality_picker.add_item("Medium", 1)
		quality_picker.add_item("Low", 2)

	if card_back_picker:
		card_back_picker.clear()
		card_back_picker.add_item("Classic Blue", 0)
		card_back_picker.add_item("Crimson Red", 1)
		card_back_picker.add_item("Cyber Neon", 2)

func load_current_profile() -> void:
	var prof = _profile_svc.get_profile()
	if name_input:
		name_input.text = prof.get("display_name", "Player")

	var th = prof.get("theme_preset", "arcade_ps5")
	if theme_picker:
		for i in range(theme_picker.item_count):
			if theme_picker.get_item_metadata(i) == th:
				theme_picker.select(i)
				break

	if colorblind_check:
		colorblind_check.button_pressed = prof.get("colorblind_mode", false)

	if master_slider and _audio_controls:
		master_slider.value = _audio_controls.get_bus_volume("Master") * 100.0
	if music_slider and _audio_controls:
		music_slider.value = _audio_controls.get_bus_volume("Music") * 100.0
	if sfx_slider and _audio_controls:
		sfx_slider.value = _audio_controls.get_bus_volume("SFX") * 100.0
	if anim_slider and _audio_controls:
		anim_slider.value = _audio_controls.get_animation_speed()

func save_current_profile() -> void:
	var new_name = name_input.text.strip_edges() if name_input else "Player"
	var selected_theme = theme_picker.get_item_metadata(theme_picker.selected) if theme_picker else "arcade_ps5"
	var cb_mode = colorblind_check.button_pressed if colorblind_check else false

	var ok = _profile_svc.update_profile({
		"display_name": new_name,
		"theme_preset": selected_theme,
		"colorblind_mode": cb_mode
	})

	if _audio_controls:
		if master_slider:
			_audio_controls.set_bus_volume("Master", master_slider.value / 100.0)
		if music_slider:
			_audio_controls.set_bus_volume("Music", music_slider.value / 100.0)
		if sfx_slider:
			_audio_controls.set_bus_volume("SFX", sfx_slider.value / 100.0)
		if anim_slider:
			_audio_controls.set_animation_speed(anim_slider.value)

	if ok:
		_set_status("Profile saved successfully!", Color.GREEN)
		profile_saved.emit(_profile_svc.get_profile())
	else:
		_set_status("Failed to save profile.", Color.RED)

func export_backup() -> void:
	var path = "user://deckbox_backup_%d.deckbox-backup.zip" % int(Time.get_unix_time_from_system())
	var res = _backup_svc.export_backup(path)
	if res.get("success", false):
		_set_status("Backup exported: %s" % path.get_file(), Color.GREEN)
	else:
		_set_status("Backup export failed: %s" % str(res.get("error")), Color.RED)

func _set_status(msg: String, col: Color) -> void:
	if status_label:
		status_label.text = msg
		status_label.modulate = col

func _on_back_pressed() -> void:
	back_requested.emit()

func _on_save_pressed() -> void:
	save_current_profile()
