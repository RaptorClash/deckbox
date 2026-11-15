"""Unit tests for translate_all.py.

Validates MD5 caching in .translation_cache.json, preventing duplicate translation
requests, placeholder masking and unmasking ({name}, {0}, %s, plural ICU constructs, newlines),
markdown link rewriting, header navigation generation, and document path resolution.
"""

import os
import sys
import unittest
import tempfile
import time
from pathlib import Path

# Module discovery paths:
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PLUGIN_TOOL = Path(r"C:\Users\marvi\.gemini\config\plugins\pokevault-dev-standard\skills\workflow-bootstrap\resources\tool")
POKEVAULT_TOOL = Path(r"C:\Marvin\Projekte\Code\pokevault\tool")

for candidate in [POKEVAULT_TOOL, PLUGIN_TOOL, REPO_ROOT / "tool"]:
    if candidate.exists() and str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

try:
    import translate_all
    from translate_all import (
        compute_text_hash,
        mask_placeholders,
        unmask_placeholders,
        rewrite_markdown_links,
        generate_header_language_nav,
        collect_uncached_strings,
        get_target_doc_path,
        get_source_doc_path,
        auto_detect_source_lang,
    )
except ImportError:
    translate_all = None
    compute_text_hash = None
    mask_placeholders = None
    unmask_placeholders = None
    rewrite_markdown_links = None
    generate_header_language_nav = None
    collect_uncached_strings = None
    get_target_doc_path = None
    get_source_doc_path = None
    auto_detect_source_lang = None


class TestMD5TextHashing(unittest.TestCase):
    """Tier 1 & Tier 2: MD5 caching text hash computation."""

    def setUp(self):
        if compute_text_hash is None:
            self.skipTest("translate_all.compute_text_hash is not available")

    def test_compute_text_hash_consistency(self):
        h1 = compute_text_hash("Welcome to DeckBox!")
        h2 = compute_text_hash("Welcome to DeckBox!")
        self.assertEqual(h1, h2)
        self.assertEqual(len(h1), 32)  # MD5 hex digest length

    def test_compute_text_hash_different_inputs(self):
        h1 = compute_text_hash("DeckBox UNO")
        h2 = compute_text_hash("DeckBox Poker")
        self.assertNotEqual(h1, h2)

    def test_compute_text_hash_empty_string(self):
        h = compute_text_hash("")
        self.assertIsInstance(h, str)
        self.assertEqual(len(h), 32)

    def test_compute_text_hash_whitespace_trimming(self):
        # compute_text_hash strips whitespace before hashing
        h1 = compute_text_hash("  Draw Two Cards  \n")
        h2 = compute_text_hash("Draw Two Cards")
        self.assertEqual(h1, h2)

    def test_compute_text_hash_multilingual_and_emojis(self):
        h_de = compute_text_hash("Kartenspiel für bis zu 8 Spieler")
        h_ja = compute_text_hash("最大8人用のカードゲーム")
        h_emoji = compute_text_hash("🃏 DeckBox Table v0.1.0 🚀")
        self.assertEqual(len(h_de), 32)
        self.assertEqual(len(h_ja), 32)
        self.assertEqual(len(h_emoji), 32)
        self.assertNotEqual(h_de, h_ja)


class TestPlaceholderProtection(unittest.TestCase):
    """Tier 1: Placeholder protection for ICU, Slang, positional, and format specifiers."""

    def setUp(self):
        if mask_placeholders is None or unmask_placeholders is None:
            self.skipTest("translate_all placeholder utilities are not available")

    def test_mask_and_unmask_named_placeholders(self):
        original = "Hello {playerName}, it is your turn to draw {cardCount} cards!"
        masked, tokens = mask_placeholders(original)

        self.assertNotIn("{playerName}", masked)
        self.assertNotIn("{cardCount}", masked)

        # Simulate translation of English into German surrounding tokens
        simulated = masked.replace("Hello", "Hallo").replace("it is your turn to draw", "du bist dran und ziehst").replace("cards!", "Karten!")
        restored = unmask_placeholders(simulated, tokens)

        self.assertEqual(restored, "Hallo {playerName}, du bist dran und ziehst {cardCount} Karten!")

    def test_mask_and_unmask_positional_placeholders(self):
        original = "Player {0} played {1} on top of {2}."
        masked, tokens = mask_placeholders(original)

        self.assertNotIn("{0}", masked)
        self.assertNotIn("{1}", masked)
        self.assertNotIn("{2}", masked)

        restored = unmask_placeholders(masked, tokens)
        self.assertEqual(restored, original)

    def test_mask_and_unmask_plural_icu_constructs(self):
        original = "Match result: {count, plural, =1{1 point scored} other{# points scored}}."
        masked, tokens = mask_placeholders(original)

        self.assertNotIn("{count, plural", masked)
        restored = unmask_placeholders(masked, tokens)
        self.assertEqual(restored, original)

    def test_mask_and_unmask_preserves_newlines(self):
        original = "Line 1: Room Code\nLine 2: PIN 4912\r\nLine 3: Connected"
        masked, tokens = mask_placeholders(original)

        self.assertNotIn("\n", masked)
        self.assertNotIn("\r\n", masked)

        restored = unmask_placeholders(masked, tokens)
        self.assertEqual(restored, original)

    def test_placeholder_printf_specifiers(self):
        # Format specifiers like %s, %d common in Godot GDScript and Python
        original = "Connected %s players with ping %d ms"
        masked, tokens = mask_placeholders(original)
        # Check if printf specifiers are masked or preserved cleanly
        restored = unmask_placeholders(masked, tokens)
        self.assertIn("%s", restored)
        self.assertIn("%d", restored)


class TestPlaceholderEdgeCases(unittest.TestCase):
    """Tier 2: Boundary cases for placeholder masking."""

    def setUp(self):
        if mask_placeholders is None or unmask_placeholders is None:
            self.skipTest("translate_all placeholder utilities are not available")

    def test_mask_unmask_idempotency_when_no_placeholders(self):
        plain_text = "Standard Card Deck with 108 cards."
        masked, tokens = mask_placeholders(plain_text)
        self.assertEqual(len(tokens), 0)
        self.assertEqual(masked, plain_text)
        restored = unmask_placeholders(masked, tokens)
        self.assertEqual(restored, plain_text)

    def test_multiple_adjacent_placeholders(self):
        original = "{prefix}{name}{suffix}"
        masked, tokens = mask_placeholders(original)
        self.assertNotIn("{name}", masked)
        restored = unmask_placeholders(masked, tokens)
        self.assertEqual(restored, original)

    def test_empty_string_masking(self):
        masked, tokens = mask_placeholders("")
        self.assertEqual(masked, "")
        self.assertEqual(len(tokens), 0)
        self.assertEqual(unmask_placeholders("", tokens), "")


class TestCacheManagement(unittest.TestCase):
    """Tier 1 & Tier 2: MD5 cache operations and avoiding duplicate translations."""

    def setUp(self):
        if collect_uncached_strings is None:
            self.skipTest("translate_all.collect_uncached_strings is not available")

    def test_collect_uncached_populates_cache_from_existing_translations(self):
        source = {
            "title": "Main Menu",
            "start": "Start Game",
            "options": "Settings",
        }
        target = {
            "title": "Hauptmenü",       # Genuine translation
            "start": "Start Game",       # Identical to source (untranslated)
            # "options" is missing
        }
        cache = {}
        uncached = set()

        collect_uncached_strings(source, target, "de", cache, uncached)

        # "title" should be cached
        h_title = compute_text_hash("Main Menu")
        self.assertIn("de", cache)
        self.assertEqual(cache["de"][h_title], "Hauptmenü")

        # "start" (untranslated) and "options" (missing) should be in uncached set
        self.assertIn("Start Game", uncached)
        self.assertIn("Settings", uncached)
        self.assertNotIn("Main Menu", uncached)

    def test_cache_hit_prevents_api_request(self):
        source = {"play": "Play Online"}
        h_play = compute_text_hash("Play Online")
        cache = {"fr": {h_play: "Jouer en ligne"}}
        target = {}
        uncached = set()

        collect_uncached_strings(source, target, "fr", cache, uncached)
        # Because cache["fr"] already contains the translation, it must not be uncached
        self.assertNotIn("Play Online", uncached)


class TestMarkdownLinkRewriting(unittest.TestCase):
    """Tier 1 & Tier 2: Markdown link rewriting and header navigation."""

    def setUp(self):
        if rewrite_markdown_links is None:
            self.skipTest("translate_all.rewrite_markdown_links is not available")

    def test_rewrite_links_from_root_to_locale(self):
        doc = "See [Architecture](ARCHITECTURE.md) and [Guides](docs/GIT_WORKFLOW_AND_RELEASES.md)."
        rewritten = rewrite_markdown_links(doc, target_lang="de", is_target_in_locales=False)

        self.assertIn("locales/ARCHITECTURE.de.md", rewritten)
        self.assertIn("docs/locales/GIT_WORKFLOW_AND_RELEASES.de.md", rewritten)

    def test_rewrite_links_prevents_double_parent_traversal(self):
        doc = "See [Architecture](../ARCHITECTURE.md) and [Docs](../docs/README.md)."
        rewritten = rewrite_markdown_links(doc, target_lang="de", is_target_in_locales=True)

        self.assertNotIn("../../", rewritten)
        self.assertIn("ARCHITECTURE.de.md", rewritten)

    def test_generate_header_language_nav(self):
        if generate_header_language_nav is None:
            self.skipTest("generate_header_language_nav is not available")
        languages = [
            {"code": "en", "flag": "🇬🇧", "nameNative": "English"},
            {"code": "de", "flag": "🇩🇪", "nameNative": "Deutsch"},
        ]
        nav = generate_header_language_nav("README.md", languages, current_lang="en", is_in_locales=False)
        self.assertIn("**[🇬🇧 English](README.md)**", nav)
        self.assertIn("[🇩🇪 Deutsch](locales/README.de.md)", nav)


class TestDocumentPathResolution(unittest.TestCase):
    """Tier 1: Target and source document path resolution."""

    def setUp(self):
        if get_target_doc_path is None or get_source_doc_path is None:
            self.skipTest("doc path resolution utilities are not available")

    def test_target_doc_path_english_is_canonical(self):
        canonical = Path("docs/ARCHITECTURE.md")
        en_target = get_target_doc_path(canonical, "en")
        self.assertEqual(en_target, Path("docs/ARCHITECTURE.md"))

    def test_target_doc_path_non_english_in_locales(self):
        canonical = Path("docs/ARCHITECTURE.md")
        de_target = get_target_doc_path(canonical, "de")
        self.assertEqual(de_target, Path("docs/locales/ARCHITECTURE.de.md"))
        fr_target = get_target_doc_path(canonical, "fr")
        self.assertEqual(fr_target, Path("docs/locales/ARCHITECTURE.fr.md"))

    def test_auto_detect_source_lang_by_mtime(self):
        if auto_detect_source_lang is None:
            self.skipTest("auto_detect_source_lang is not available")
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            canonical = tmppath / "README.md"
            locales_dir = tmppath / "locales"
            locales_dir.mkdir()
            de_file = locales_dir / "README.de.md"

            # German older, English newer
            de_file.write_text("Deutsch", encoding="utf-8")
            time.sleep(0.05)
            canonical.write_text("English", encoding="utf-8")

            detected = auto_detect_source_lang(canonical)
            self.assertEqual(detected, "en")


if __name__ == "__main__":
    unittest.main()
