"""Unit tests for translate_release_notes.py.

Validates parsing of draft release notes, source language detection,
13-language collapsible Markdown generation (<details><summary>),
preservation of URLs, version numbers, and markdown formatting.
"""

import os
import sys
import unittest
from pathlib import Path

# Module discovery paths:
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PLUGIN_TOOL = Path(r"C:\Users\marvi\.gemini\config\plugins\pokevault-dev-standard\skills\workflow-bootstrap\resources\tool")
POKEVAULT_TOOL = Path(r"C:\Marvin\Projekte\Code\pokevault\tool")

for candidate in [POKEVAULT_TOOL, PLUGIN_TOOL, REPO_ROOT / "tool"]:
    if candidate.exists() and str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

try:
    import translate_release_notes
    from translate_release_notes import (
        parse_draft_notes,
        detect_draft_source_lang,
        format_collapsible_release_notes,
        translate_release_body,
    )
except ImportError:
    translate_release_notes = None
    parse_draft_notes = None
    detect_draft_source_lang = None
    format_collapsible_release_notes = None
    translate_release_body = None

# The 13 standard target languages supported by DeckBox & PokéVault
STANDARD_13_LANGUAGES = [
    {"code": "en", "flag": "🇬🇧", "nameNative": "English"},
    {"code": "de", "flag": "🇩🇪", "nameNative": "Deutsch"},
    {"code": "fr", "flag": "🇫🇷", "nameNative": "Français"},
    {"code": "es", "flag": "🇪🇸", "nameNative": "Español"},
    {"code": "it", "flag": "🇮🇹", "nameNative": "Italiano"},
    {"code": "ja", "flag": "🇯🇵", "nameNative": "日本語"},
    {"code": "ko", "flag": "🇰🇷", "nameNative": "한국어"},
    {"code": "zh-Hans", "flag": "🇨🇳", "nameNative": "简体中文"},
    {"code": "zh-Hant", "flag": "🇹🇼", "nameNative": "繁體中文"},
    {"code": "pt", "flag": "🇧🇷", "nameNative": "Português"},
    {"code": "nl", "flag": "🇳🇱", "nameNative": "Nederlands"},
    {"code": "pl", "flag": "🇵🇱", "nameNative": "Polski"},
    {"code": "ru", "flag": "🇷🇺", "nameNative": "Русский"},
]


class TestParseDraftNotes(unittest.TestCase):
    """Tier 1: Parsing draft markdown files into title, body, and footer."""

    def setUp(self):
        if parse_draft_notes is None:
            self.skipTest("translate_release_notes.parse_draft_notes is not available")

    def test_parse_draft_notes_complete(self):
        draft = """# DeckBox v0.1.0 Release Notes — "Foundation"

**New Features**
* Implemented modular GameCartridge interface.
* Added pure UNO reference rules engine.

**Improvements & Fixes**
* Optimized anti-leak network filter.

**Full Changelog**: https://github.com/RaptorClash/deckbox/commits/v0.1.0
"""
        title, body, footer = parse_draft_notes(draft)
        self.assertEqual(title, '# DeckBox v0.1.0 Release Notes — "Foundation"')
        self.assertIn("**New Features**", body)
        self.assertIn("modular GameCartridge interface", body)
        self.assertIn("anti-leak network filter", body)
        self.assertNotIn("**Full Changelog**", body)
        self.assertTrue(footer.startswith("**Full Changelog**: https://github.com/RaptorClash/deckbox"))

    def test_parse_draft_notes_no_footer(self):
        draft = """# DeckBox v0.1.0 Release Notes — "Foundation"

**New Features**
* Modular 3D card game.
"""
        title, body, footer = parse_draft_notes(draft)
        self.assertEqual(title, '# DeckBox v0.1.0 Release Notes — "Foundation"')
        self.assertIn("Modular 3D card game", body)
        self.assertEqual(footer, "")

    def test_parse_draft_notes_no_title_header(self):
        draft = """**New Features**
* UNO Card Game Engine.
"""
        title, body, footer = parse_draft_notes(draft)
        self.assertEqual(title, "")
        self.assertEqual(body, "**New Features**\n* UNO Card Game Engine.")
        self.assertEqual(footer, "")


class TestParseDraftNotesBoundary(unittest.TestCase):
    """Tier 2: Boundary cases for draft parsing."""

    def setUp(self):
        if parse_draft_notes is None:
            self.skipTest("translate_release_notes.parse_draft_notes is not available")

    def test_parse_draft_notes_empty_string(self):
        title, body, footer = parse_draft_notes("")
        self.assertEqual(title, "")
        self.assertEqual(body, "")
        self.assertEqual(footer, "")

    def test_parse_draft_notes_whitespace_only(self):
        title, body, footer = parse_draft_notes("   \n\n\t\n  ")
        self.assertEqual(title, "")
        self.assertEqual(body, "")
        self.assertEqual(footer, "")

    def test_parse_draft_notes_only_title(self):
        draft = '# DeckBox v0.1.0 Release Notes — "Standalone Title"'
        title, body, footer = parse_draft_notes(draft)
        self.assertEqual(title, '# DeckBox v0.1.0 Release Notes — "Standalone Title"')
        self.assertEqual(body, "")
        self.assertEqual(footer, "")


class TestDetectDraftSourceLanguage(unittest.TestCase):
    """Tier 1 & Tier 2: Source language detection."""

    def setUp(self):
        if detect_draft_source_lang is None:
            self.skipTest("translate_release_notes.detect_draft_source_lang is not available")

    def test_detect_english_draft(self):
        draft = """# DeckBox v0.1.0
**New Features**
* Added multiplayer support and WebRTC STUN.
**Bug Fixes**
* Fixed connection issue.
"""
        self.assertEqual(detect_draft_source_lang(draft), "en")

    def test_detect_german_draft(self):
        draft = """# DeckBox v0.1.0
**Neue Funktionen**
* Multiplayer-Unterstützung mit WebRTC STUN hinzugefügt.
**Verbesserungen & Fehlerbehebungen**
* Fehler bei der Raum-Erstellung behoben.
"""
        self.assertEqual(detect_draft_source_lang(draft), "de")

    def test_detect_neutral_or_tie_defaults_to_english(self):
        draft = """# DeckBox v0.1.0
1234567890
Hello World
"""
        self.assertEqual(detect_draft_source_lang(draft), "en")


class TestFormatCollapsibleReleaseNotes(unittest.TestCase):
    """Tier 1: 13-language collapsible Markdown generation."""

    def setUp(self):
        if format_collapsible_release_notes is None:
            self.skipTest("translate_release_notes.format_collapsible_release_notes is not available")

    def test_format_13_languages_structure(self):
        title = '# DeckBox v0.1.0 — "Foundation"'
        translations = {lang["code"]: f"Content for {lang['nameNative']}" for lang in STANDARD_13_LANGUAGES}
        footer = "**Full Changelog**: https://github.com/RaptorClash/deckbox/releases/tag/v0.1.0"

        output = format_collapsible_release_notes(title, translations, STANDARD_13_LANGUAGES, footer=footer)

        self.assertTrue(output.startswith(title))
        self.assertTrue(output.strip().endswith(footer))

        # Check all 13 languages are properly wrapped in details/summary
        for lang in STANDARD_13_LANGUAGES:
            flag = lang["flag"]
            name = lang["nameNative"]
            expected_summary = f"<summary>{flag} <b>{name}</b></summary>"
            self.assertIn(expected_summary, output)
            self.assertIn(f"Content for {name}", output)
            self.assertIn("</details>", output)

    def test_format_skips_missing_or_empty_languages(self):
        title = '# DeckBox v0.1.0'
        translations = {
            "en": "English content",
            "de": "Deutscher Inhalt",
            "fr": "",  # Empty
        }
        output = format_collapsible_release_notes(title, translations, STANDARD_13_LANGUAGES)
        self.assertIn("<summary>🇬🇧 <b>English</b></summary>", output)
        self.assertIn("<summary>🇩🇪 <b>Deutsch</b></summary>", output)
        self.assertNotIn("<summary>🇫🇷 <b>Français</b></summary>", output)


class TestFormattingPreservation(unittest.TestCase):
    """Tier 2: Preservation of URLs, versions, and markdown elements."""

    def setUp(self):
        if translate_release_body is None:
            self.skipTest("translate_release_notes.translate_release_body is not available")

    def test_same_language_preserves_exact_body(self):
        body = """**New Features**
* 3D Table Theme `arcade_ps5` with shaders.
* Version v0.1.0 handshake over WebRTC.
* See documentation at https://deckbox.io/docs
"""
        cache = {}
        result = translate_release_body(body, target_lang="en", cache=cache, source_lang="en")
        self.assertEqual(result, body)

    def test_url_preservation_in_notes(self):
        body = "Release link: https://github.com/RaptorClash/deckbox/releases/tag/v0.1.0"
        cache = {}
        result = translate_release_body(body, target_lang="en", cache=cache, source_lang="en")
        self.assertIn("https://github.com/RaptorClash/deckbox/releases/tag/v0.1.0", result)

    def test_version_preservation_in_notes(self):
        body = "Version bumped from v0.1.0 to v0.2.0-beta.1"
        cache = {}
        result = translate_release_body(body, target_lang="en", cache=cache, source_lang="en")
        self.assertIn("v0.1.0", result)
        self.assertIn("v0.2.0-beta.1", result)


if __name__ == "__main__":
    unittest.main()
