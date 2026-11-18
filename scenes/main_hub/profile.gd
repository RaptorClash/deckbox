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
@onready var import_path_edit: LineEdit = $VBoxContainer/TabContainer/Backup/VBox/ImportRow/ImportPathEdit
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
		quality_picker.set_item_metadata(0, "high")
		quality_picker.add_item("Medium", 1)
		quality_picker.set_item_metadata(1, "medium")
		quality_picker.add_item("Low", 2)
		quality_picker.set_item_metadata(2, "low")

	if card_back_picker:
		card_back_picker.clear()
		card_back_picker.add_item("Classic Blue", 0)
		card_back_picker.set_item_metadata(0, "classic_blue")
		card_back_picker.add_item("Crimson Red", 1)
		card_back_picker.set_item_metadata(1, "crimson_red")
		card_back_picker.add_item("Cyber Neon", 2)
		card_back_picker.set_item_metadata(2, "cyber_neon")

func _select_meta(opt: OptionButton, val: String) -> void:
	if opt == null:
		return
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == val:
			opt.select(i)
			return

func load_current_profile() -> void:
	var prof = _profile_svc.get_profile()
	if name_input:
		name_input.text = prof.get("display_name", "Player")

	_select_meta(theme_picker, str(prof.get("theme_preset", "arcade_ps5")))
	_select_meta(quality_picker, str(prof.get("quality_preset", "high")))
	_select_meta(card_back_picker, str(prof.get("preferred_card_back", "classic_blue")))

	if colorblind_check:
		colorblind_check.button_pressed = prof.get("colorblind_mode", false)

	var m_vol := float(prof.get("master_volume", 1.0))
	var mu_vol := float(prof.get("music_volume", 0.8))
	var s_vol := float(prof.get("sfx_volume", 0.9))
	var a_spd := float(prof.get("animation_speed", 1.0))
	if _audio_controls:
		_audio_controls.set_bus_volume("Master", m_vol)
		_audio_controls.set_bus_volume("Music", mu_vol)
		_audio_controls.set_bus_volume("SFX", s_vol)
		_audio_controls.set_animation_speed(a_spd)
	if master_slider:
		master_slider.value = m_vol * 100.0
	if music_slider:
		music_slider.value = mu_vol * 100.0
	if sfx_slider:
		sfx_slider.value = s_vol * 100.0
	if anim_slider:
		anim_slider.value = a_spd

func save_current_profile() -> void:
	var new_name = name_input.text.strip_edges() if name_input else "Player"
	if new_name.is_empty():
		new_name = "Player"
	var selected_theme = str(theme_picker.get_item_metadata(theme_picker.selected)) if (theme_picker and theme_picker.selected >= 0) else "arcade_ps5"
	var selected_quality = str(quality_picker.get_item_metadata(quality_picker.selected)) if (quality_picker and quality_picker.selected >= 0) else "high"
	var selected_back = str(card_back_picker.get_item_metadata(card_back_picker.selected)) if (card_back_picker and card_back_picker.selected >= 0) else "classic_blue"
	var cb_mode = colorblind_check.button_pressed if colorblind_check else false
	var m_vol := (master_slider.value / 100.0) if master_slider else 1.0
	var mu_vol := (music_slider.value / 100.0) if music_slider else 0.8
	var s_vol := (sfx_slider.value / 100.0) if sfx_slider else 0.9
	var a_spd := anim_slider.value if anim_slider else 1.0

	var ok = _profile_svc.update_profile({
		"display_name": new_name,
		"theme_preset": selected_theme,
		"quality_preset": selected_quality,
		"preferred_card_back": selected_back,
		"colorblind_mode": cb_mode,
		"master_volume": m_vol,
		"music_volume": mu_vol,
		"sfx_volume": s_vol,
		"animation_speed": a_spd
	})

	if _audio_controls:
		_audio_controls.set_bus_volume("Master", m_vol)
		_audio_controls.set_bus_volume("Music", mu_vol)
		_audio_controls.set_bus_volume("SFX", s_vol)
		_audio_controls.set_animation_speed(a_spd)

	if ok:
		_set_status("Profil & alle Einstellungen gespeichert!", Color.GREEN)
		profile_saved.emit(_profile_svc.get_profile())
	else:
		_set_status("Fehler beim Speichern des Profils.", Color.RED)

func export_backup() -> void:
	save_current_profile()
	var path = "user://deckbox_backup_%d.deckbox-backup.zip" % int(Time.get_unix_time_from_system())
	var res = _backup_svc.export_backup(path)
	if res.get("success", false):
		var full_p := ProjectSettings.globalize_path(path)
		if import_path_edit:
			import_path_edit.text = full_p
		_set_status("Backup exportiert: %s" % full_p, Color.GREEN)
	else:
		_set_status("Backup export failed: %s" % str(res.get("error")), Color.RED)

func import_backup_from_path(source_path: String) -> Dictionary:
	var clean_p := source_path.strip_edges()
	if clean_p.is_empty():
		return { "success": false, "error": "Pfad ist leer" }
	var res: Dictionary = _backup_svc.import_backup(clean_p, "MERGE_OVERWRITE")
	if res.get("success", false):
		_profile_svc.load_profile()
		load_current_profile()
		_set_status("Backup erfolgreich importiert!", Color.GREEN)
		profile_saved.emit(_profile_svc.get_profile())
	else:
		_set_status("Backup-Import fehlgeschlagen: %s" % str(res.get("error", "")), Color.RED)
	return res

func _on_import_backup_pressed() -> void:
	var p := import_path_edit.text.strip_edges() if import_path_edit else ""
	if p.ends_with(".json"):
		if _profile_svc.import_settings_json(p):
			load_current_profile()
			_set_status("Einstellungen (.json) importiert!", Color.GREEN)
			profile_saved.emit(_profile_svc.get_profile())
		else:
			_set_status("JSON-Import fehlgeschlagen.", Color.RED)
		return
	import_backup_from_path(p)

func _on_export_settings_json_pressed() -> void:
	save_current_profile()
	var p := "user://deckbox_settings_export.json"
	if _profile_svc.export_settings_json(p):
		var full_p := ProjectSettings.globalize_path(p)
		if import_path_edit:
			import_path_edit.text = full_p
		_set_status("Einstellungen exportiert: %s" % full_p, Color.GREEN)

func _on_import_settings_json_pressed() -> void:
	var p := import_path_edit.text.strip_edges() if import_path_edit and not import_path_edit.text.strip_edges().is_empty() else "user://deckbox_settings_export.json"
	if _profile_svc.import_settings_json(p):
		load_current_profile()
		_set_status("Einstellungen importiert!", Color.GREEN)
		profile_saved.emit(_profile_svc.get_profile())
	else:
		_set_status("Keine gültige Einstellungs-JSON gefunden: %s" % p, Color.RED)

func _set_status(msg: String, col: Color) -> void:
	if status_label:
		status_label.text = msg
		status_label.modulate = col

func _on_back_pressed() -> void:
	back_requested.emit()

func _on_save_pressed() -> void:
	save_current_profile()
