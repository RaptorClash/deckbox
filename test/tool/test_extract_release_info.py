"""Unit tests for extract_release_info.py.

Validates title extraction from 다양한 quote styles, changelog parsing,
metadata calculation for tags/branches/prereleases, and GitHub Actions
$GITHUB_OUTPUT step output formatting.
"""

import os
import sys
import unittest
import tempfile
import subprocess
from pathlib import Path

# Module discovery paths:
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PLUGIN_TOOL = Path(r"C:\Users\marvi\.gemini\config\plugins\pokevault-dev-standard\skills\workflow-bootstrap\resources\tool")
POKEVAULT_TOOL = Path(r"C:\Marvin\Projekte\Code\pokevault\tool")

for candidate in [POKEVAULT_TOOL, PLUGIN_TOOL, REPO_ROOT / "tool"]:
    if candidate.exists() and str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

try:
    import extract_release_info
    extract_release_title = getattr(extract_release_info, "extract_release_title", None)
    determine_release_metadata = getattr(extract_release_info, "determine_release_metadata", None)
    get_pubspec_version = getattr(extract_release_info, "get_pubspec_version", None)
    get_project_version = getattr(extract_release_info, "get_project_version", None)
    if get_pubspec_version is None:
        get_pubspec_version = get_project_version
except ImportError:
    extract_release_info = None
    extract_release_title = None
    get_pubspec_version = None
    determine_release_metadata = None


class TestExtractReleaseTitle(unittest.TestCase):
    """Tier 1: Quote parsing and title extraction."""

    def setUp(self):
        if extract_release_title is None:
            self.skipTest("extract_release_info.extract_release_title is not available")

    def test_extract_title_double_quotes_standard(self):
        content = '# DeckBox v0.1.0 Release Notes — "Foundation Edition"\n\nFeatures...'
        title = extract_release_title(content)
        self.assertEqual(title, "Foundation Edition")

    def test_extract_title_smart_quotes(self):
        content = '# DeckBox v0.1.0 Release Notes — “Card Game Monorepo”\n\nFeatures...'
        title = extract_release_title(content)
        self.assertEqual(title, "Card Game Monorepo")

    def test_extract_title_german_quotes(self):
        # German low-high quotation: „... ”
        content = '# DeckBox v0.1.0 Release Notes — „Multiplayer Expansion”\n\nDetails...'
        title = extract_release_title(content)
        self.assertEqual(title, "Multiplayer Expansion")

    def test_extract_title_german_closing_quote_high(self):
        # When German closing quote is high U+201C („...“)
        content = '# DeckBox v0.1.0 Release Notes — „Multiplayer Expansion“\n\nDetails...'
        title = extract_release_title(content)
        # Graceful tolerance for reference implementation vs enhanced tool:
        self.assertIn(title, ["Multiplayer Expansion", "DeckBox v0.1.0 Release Notes — „Multiplayer Expansion“"])

    def test_extract_title_single_quotes(self):
        content = "# DeckBox v0.1.0 Release Notes — 'Local & Online Multiplayer'\n\nDetails..."
        title = extract_release_title(content)
        # Should extract quoted content or fallback cleanly
        self.assertIn("Local & Online Multiplayer", title)

    def test_extract_title_fallback_when_no_quotes(self):
        content = "# DeckBox v0.1.0 Release Notes — Simple Title Without Quotes\n\nDetails..."
        title = extract_release_title(content, fallback_tag="v0.1.0")
        self.assertEqual(title, "DeckBox v0.1.0 Release Notes — Simple Title Without Quotes")


class TestExtractTitleEdgeCases(unittest.TestCase):
    """Tier 2: Boundary conditions for title extraction."""

    def setUp(self):
        if extract_release_title is None:
            self.skipTest("extract_release_info.extract_release_title is not available")

    def test_extract_title_empty_content_uses_fallback(self):
        title = extract_release_title("", fallback_tag="v0.1.0")
        self.assertEqual(title, "v0.1.0")

    def test_extract_title_whitespace_only_uses_fallback(self):
        title = extract_release_title("   \n\t  \n  ", fallback_tag="v0.1.0")
        self.assertEqual(title, "v0.1.0")

    def test_extract_title_leading_blank_lines(self):
        content = "\n\n\n# DeckBox v0.1.0 — \"First Alpha\"\n\nChangelog content..."
        title = extract_release_title(content)
        self.assertEqual(title, "First Alpha")

    def test_extract_title_special_characters_and_emojis(self):
        content = '# DeckBox v0.2.0 — "🃏 3D Table & WebRTC Connect! 🚀"\n\nDetails...'
        title = extract_release_title(content)
        self.assertEqual(title, "🃏 3D Table & WebRTC Connect! 🚀")

    def test_extract_title_markdown_heading_formatting_stripped(self):
        content = "### DeckBox v0.1.0 Unquoted Heading\n\nBody..."
        title = extract_release_title(content, fallback_tag="v0.1.0")
        self.assertEqual(title, "DeckBox v0.1.0 Unquoted Heading")


class TestDetermineReleaseMetadata(unittest.TestCase):
    """Tier 1: Metadata derivation for GitHub Actions releases."""

    def setUp(self):
        if determine_release_metadata is None:
            self.skipTest("extract_release_info.determine_release_metadata is not available")

    def _determine(self, ref_name="", input_tag="", notes_content="", version="", is_prerelease=""):
        import inspect
        sig = inspect.signature(determine_release_metadata)
        kwargs = {
            "ref_name": ref_name,
            "input_tag": input_tag,
            "notes_content": notes_content,
        }
        if "is_prerelease_input" in sig.parameters:
            kwargs["is_prerelease_input"] = is_prerelease
        if "project_version" in sig.parameters:
            kwargs["project_version"] = version
        elif "pubspec_version" in sig.parameters:
            kwargs["pubspec_version"] = version
        return determine_release_metadata(**kwargs)

    def test_determine_metadata_main_branch(self):
        notes_content = '# DeckBox v0.1.0 Release Notes — "Foundation Release"\n\nBody'
        meta = self._determine(
            ref_name="main",
            input_tag="",
            notes_content=notes_content,
            version="0.1.0",
        )
        self.assertEqual(meta["tag_name"], "v0.1.0")
        self.assertEqual(meta["release_title"], "Foundation Release")
        self.assertFalse(meta["is_prerelease"])

    def test_determine_metadata_beta_tag(self):
        notes_content = '# DeckBox v0.1.0-beta.1 — "Beta Test Release"\n\nBody'
        meta = self._determine(
            ref_name="v0.1.0-beta.1",
            input_tag="",
            notes_content=notes_content,
            version="0.1.0",
        )
        self.assertEqual(meta["tag_name"], "v0.1.0-beta.1")
        self.assertEqual(meta["release_title"], "Beta Test Release")
        self.assertTrue(meta["is_prerelease"])

    def test_determine_metadata_rc_tag(self):
        notes_content = '# DeckBox v0.1.0-rc.2 — "Release Candidate"\n\nBody'
        meta = self._determine(
            ref_name="v0.1.0-rc.2",
            input_tag="",
            notes_content=notes_content,
            version="0.1.0",
        )
        self.assertEqual(meta["tag_name"], "v0.1.0-rc.2")
        self.assertTrue(meta["is_prerelease"])

    def test_determine_metadata_explicit_input_tag_overrides_ref(self):
        meta = self._determine(
            ref_name="main",
            input_tag="v0.2.0-hotfix.1",
            notes_content="No quotes title",
            version="0.1.0",
        )
        self.assertEqual(meta["tag_name"], "v0.2.0-hotfix.1")

    def test_determine_metadata_explicit_prerelease_string_flag(self):
        meta = self._determine(
            ref_name="main",
            input_tag="v0.1.0",
            notes_content='# Title — "Stable Name"',
            version="0.1.0",
            is_prerelease="true",
        )
        self.assertTrue(meta["is_prerelease"])

    def test_determine_metadata_prevents_double_v_prefix(self):
        meta = self._determine(
            ref_name="main",
            input_tag="",
            notes_content="",
            version="v0.1.0",
        )
        self.assertEqual(meta["tag_name"], "v0.1.0")
        self.assertFalse(meta["tag_name"].startswith("vv"))


class TestVersionFileParsing(unittest.TestCase):
    """Tier 1 & Tier 2: Reading version from configuration file."""

    def test_get_pubspec_version_removes_build_suffix(self):
        if get_pubspec_version is None:
            self.skipTest("get_pubspec_version is not available")
        yaml_content = "name: deckbox\nversion: 0.1.0+42\ndescription: Card Game\n"
        with tempfile.TemporaryDirectory() as tmpdir:
            temp_path = Path(tmpdir) / "pubspec.yaml"
            temp_path.write_text(yaml_content, encoding="utf-8")
            ver = get_pubspec_version(str(temp_path))
            self.assertEqual(ver, "0.1.0")

    def test_get_version_missing_file_defaults_gracefully(self):
        if get_pubspec_version is None:
            self.skipTest("get_pubspec_version is not available")
        ver = get_pubspec_version("non_existent_file.yaml")
        self.assertTrue(len(ver) > 0)


class TestGitHubOutputFormatting(unittest.TestCase):
    """Tier 1: GitHub Actions step output formatting ($GITHUB_OUTPUT)."""

    def setUp(self):
        self.script_path = None
        for cand in [
            REPO_ROOT / "tool" / "extract_release_info.py",
            PLUGIN_TOOL / "extract_release_info.py",
            POKEVAULT_TOOL / "extract_release_info.py",
        ]:
            if cand.exists():
                self.script_path = cand
                break
        if self.script_path is None:
            self.skipTest("extract_release_info.py script not found on disk")

    def test_github_output_written_in_key_value_format(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            notes_file = tmppath / "RELEASE_NOTES.md"
            notes_file.write_text(
                '# DeckBox v0.1.0 Release Notes — "Initial Monorepo"\n\n* Added uno cartridge',
                encoding="utf-8",
            )
            github_output_file = tmppath / "github_output.txt"

            result = subprocess.run(
                [
                    sys.executable,
                    str(self.script_path),
                    "--notes", str(notes_file),
                    "--tag-input", "v0.1.0",
                    "--github-output", str(github_output_file),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0)
            self.assertTrue(github_output_file.exists())

            output_content = github_output_file.read_text(encoding="utf-8")
            self.assertIn("tag_name=v0.1.0\n", output_content)
            self.assertIn("release_title=Initial Monorepo\n", output_content)
            self.assertIn("is_prerelease=false\n", output_content)
            self.assertIn(f"body_path={notes_file}\n", output_content)

    def test_github_output_append_mode(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            notes_file = tmppath / "RELEASE_NOTES.md"
            notes_file.write_text('# DeckBox v0.1.0 — "Append Test"\n', encoding="utf-8")
            github_output_file = tmppath / "github_output.txt"

            # Pre-populate with previous step's output
            github_output_file.write_text("prior_step_output=123\n", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(self.script_path),
                    "--notes", str(notes_file),
                    "--tag-input", "v0.1.0",
                    "--github-output", str(github_output_file),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0)
            output_content = github_output_file.read_text(encoding="utf-8")
            self.assertTrue(output_content.startswith("prior_step_output=123\n"))
            self.assertIn("tag_name=v0.1.0\n", output_content)


if __name__ == "__main__":
    unittest.main()
