# core/updater/release_updater.gd
# GitHub Releases integration, multi-platform artifact resolution, downgrade fallback, and Windows self-update script.
class_name ReleaseUpdater extends RefCounted

const REPO_URL: String = "https://api.github.com/repos/RaptorClash/deckbox/releases"
const LATEST_URL: String = "https://api.github.com/repos/RaptorClash/deckbox/releases/latest"

func compare_versions(v1: String, v2: String) -> int:
	var clean_v1 = _clean_semver(v1)
	var clean_v2 = _clean_semver(v2)

	var p1 = clean_v1.split(".")
	var p2 = clean_v2.split(".")

	var max_len = maxi(p1.size(), p2.size())
	for i in range(max_len):
		var n1 = int(p1[i]) if i < p1.size() else 0
		var n2 = int(p2[i]) if i < p2.size() else 0
		if n1 > n2:
			return 1
		elif n1 < n2:
			return -1

	return 0

func is_downgrade(current_ver: String, target_ver: String) -> bool:
	return compare_versions(target_ver, current_ver) < 0

func resolve_asset(assets: Array, platform: String) -> Dictionary:
	var plat = platform.to_lower()
	var candidates: Array[String] = []

	if plat.contains("win"):
		candidates = [".zip"]
	elif plat.contains("linux") or plat.contains("x11"):
		candidates = [".tar.gz", ".appimage"]
	elif plat.contains("android"):
		candidates = [".apk"]
	elif plat.contains("web") or plat.contains("html"):
		candidates = [".zip"]
	else:
		return {}

	for asset in assets:
		if not asset is Dictionary:
			continue
		var name = str(asset.get("name", "")).to_lower()
		for ext in candidates:
			if name.ends_with(ext) and (plat.contains("win") == (name.contains("win") or name.contains("windows") or not (name.contains("linux") or name.contains("android") or name.contains("web")))):
				return {
					"name": asset.get("name", ""),
					"download_url": asset.get("browser_download_url", ""),
					"size": asset.get("size", 0),
					"content_type": asset.get("content_type", "")
				}

	return {}

func generate_downgrade_prompt(current_ver: String, host_ver: String, room_url: String) -> Dictionary:
	return {
		"is_downgrade": true,
		"current_version": current_ver,
		"host_version": host_ver,
		"title": "Version Mismatch — Fallback Available",
		"message": "Host is running DeckBox version %s (Your installed client is %s)." % [host_ver, current_ver],
		"action_prompt": "Play immediately via Lightweight Web Client",
		"web_fallback_url": room_url,
		"auto_downgrade_supported": false
	}

func generate_windows_updater_script(pid: int, src_dir: String, dst_dir: String, exe_name: String) -> String:
	return """@echo off
setlocal enabledelayedexpansion
title DeckBox Auto-Updater

set TARGET_PID=%d
set SRC_DIR=%s
set DST_DIR=%s
set EXE_NAME=%s

echo [DeckBox Updater] Waiting for DeckBox (PID %%TARGET_PID%%) to exit...
:WAIT_LOOP
tasklist /fi "PID eq %%TARGET_PID%%" 2>NUL | find /I /N "%%TARGET_PID%%">NUL
if "%%ERRORLEVEL%%"=="0" (
    timeout /t 1 /nobreak >nul
    goto WAIT_LOOP
)

echo [DeckBox Updater] Copying updated release files...
robocopy "%%SRC_DIR%%" "%%DST_DIR%%" /E /IS /IT /NP /NJH /NJS

echo [DeckBox Updater] Launching updated application...
start "" "%%DST_DIR%%\\%%EXE_NAME%%"

echo [DeckBox Updater] Cleaning up staging directory...
rmdir /S /Q "%%SRC_DIR%%"

echo [DeckBox Updater] Update completed successfully!
exit /b 0
""" % [pid, src_dir, dst_dir, exe_name]

func write_windows_updater_script(path: String, content: String = "") -> bool:
	var global_path = ProjectSettings.globalize_path(path)
	var dir_path = global_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var script_text = content
	if script_text.is_empty():
		script_text = generate_windows_updater_script(OS.get_process_id(), "staged", ".", "deckbox.exe")

	var f = FileAccess.open(global_path, FileAccess.WRITE)
	if f != null:
		f.store_string(script_text)
		f.close()
		return true
	return false

func _clean_semver(v: String) -> String:
	var clean = v.strip_edges()
	if clean.begins_with("v") or clean.begins_with("V"):
		clean = clean.substr(1)
	if clean.contains("-"):
		clean = clean.split("-")[0]
	return clean
