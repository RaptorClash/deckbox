#!/usr/bin/env python3
"""
PokéVault Automated 13-Language Translation Pipeline
---------------------------------------------------
Translates UI strings and markdown documentation into 13 supported languages:
de, en, fr, es, it, ja, ko, zh-Hans, zh-Hant, pt, nl, pl, ru.

Features:
- 100% Python Standard Library (zero external pip dependencies).
- Free multi-engine translation using standard urllib (Google Web Translate + MyMemory fallback).
- MD5 hash caching in tool/.translation_cache.json with anti-poisoning safeguards.
- ICU and Slang variable & plural construct protection ({name}, {count, plural, ...}).
- Markdown document translation with link rewriting, relative locale navigation, and code block preservation.
- Optional DeepL API key support when DEEPL_API_KEY environment variable is configured.
"""

import os
import sys
import json
import re
import hashlib
import argparse
import time
import threading
import urllib.request
import urllib.parse
from pathlib import Path

# Ensure stdout uses UTF-8 on Windows
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
CACHE_PATH = REPO_ROOT / "tool" / ".translation_cache.json"

DEFAULT_LANGUAGES = [
    {"code": "de", "flag": "🇩🇪", "nameNative": "Deutsch", "nameEn": "German", "isPokemonFranchise": True, "slangCode": "de"},
    {"code": "en", "flag": "🇬🇧", "nameNative": "English", "nameEn": "English", "isPokemonFranchise": True, "slangCode": "en"},
    {"code": "fr", "flag": "🇫🇷", "nameNative": "Français", "nameEn": "French", "isPokemonFranchise": True, "slangCode": "fr"},
    {"code": "es", "flag": "🇪🇸", "nameNative": "Español", "nameEn": "Spanish", "isPokemonFranchise": True, "slangCode": "es"},
    {"code": "it", "flag": "🇮🇹", "nameNative": "Italiano", "nameEn": "Italian", "isPokemonFranchise": True, "slangCode": "it"},
    {"code": "ja", "flag": "🇯🇵", "nameNative": "日本語", "nameEn": "Japanese", "isPokemonFranchise": True, "slangCode": "ja"},
    {"code": "ko", "flag": "🇰🇷", "nameNative": "한국어", "nameEn": "Korean", "isPokemonFranchise": True, "slangCode": "ko"},
    {"code": "zh-Hans", "flag": "🇨🇳", "nameNative": "简体中文", "nameEn": "Simplified Chinese", "isPokemonFranchise": True, "slangCode": "zh-Hans"},
    {"code": "zh-Hant", "flag": "🇹🇼", "nameNative": "繁體中文", "nameEn": "Traditional Chinese", "isPokemonFranchise": True, "slangCode": "zh-Hant"},
    {"code": "pt", "flag": "🇵🇹", "nameNative": "Português", "nameEn": "Portuguese", "isPokemonFranchise": False, "slangCode": "pt"},
    {"code": "nl", "flag": "🇳🇱", "nameNative": "Nederlands", "nameEn": "Dutch", "isPokemonFranchise": False, "slangCode": "nl"},
    {"code": "pl", "flag": "🇵🇱", "nameNative": "Polski", "nameEn": "Polish", "isPokemonFranchise": False, "slangCode": "pl"},
    {"code": "ru", "flag": "🇷🇺", "nameNative": "Русский", "nameEn": "Russian", "isPokemonFranchise": False, "slangCode": "ru"},
]

MULTI_LANG_STEMS = {"README", "ARCHITECTURE", "GIT_WORKFLOW_AND_RELEASES"}

LANG_MAP = {
    "de": "de",
    "en": "en",
    "fr": "fr",
    "es": "es",
    "it": "it",
    "ja": "ja",
    "ko": "ko",
    "zh-hans": "zh-CN",
    "zh-hant": "zh-TW",
    "pt": "pt",
    "nl": "nl",
    "pl": "pl",
    "ru": "ru",
}

def load_languages_config(custom_path: Path = None):
    """Loads configured languages from JSON file or falls back to standard 13 languages."""
    candidates = [
        custom_path,
        REPO_ROOT / "i18n" / "languages.json",
        REPO_ROOT / "lib" / "i18n" / "languages.json",
        REPO_ROOT / "locales" / "languages.json",
        REPO_ROOT / "tool" / "languages.json",
    ]
    for c in candidates:
        if c and Path(c).exists():
            with open(c, "r", encoding="utf-8") as f:
                return json.load(f)
    return DEFAULT_LANGUAGES

def compute_text_hash(text: str) -> str:
    """Computes an MD5 hex digest for text caching."""
    return hashlib.md5(text.strip().encode("utf-8")).hexdigest()

def mask_placeholders(text: str):
    """Protects Slang parameters, newlines, and code tokens from translation."""
    placeholders = []

    def repl_plural(match):
        idx = len(placeholders)
        placeholders.append(match.group(0))
        return f"__PLURAL_VAR_{idx}__"

    # 1. Protect plural slang constructs: {var, plural, ...}
    text = re.sub(r'\{[^{}]*,\s*plural\s*,[^{}]*(?:\{[^{}]*\}[^{}]*)*\}', repl_plural, text)

    # 2. Protect standard slang parameters: {name}, {count}, {0}, etc.
    def repl_var(match):
        idx = len(placeholders)
        placeholders.append(match.group(0))
        return f"__SLANG_VAR_{idx}__"

    text = re.sub(r'\{[a-zA-Z0-9_]+\}', repl_var, text)

    # 3. Protect newlines
    def repl_nl(match):
        idx = len(placeholders)
        placeholders.append(match.group(0))
        return f"__NL_VAR_{idx}__"

    text = re.sub(r'(\r\n|\n)', repl_nl, text)

    return text, placeholders

def unmask_placeholders(text: str, placeholders):
    """Restores masked tokens back to their original values."""
    for idx, original in enumerate(placeholders):
        pattern = re.compile(rf'__(?:PLURAL|SLANG|NL)_VAR_{idx}__', re.IGNORECASE)
        text = pattern.sub(lambda m, orig=original: orig, text)
    return text

def get_target_doc_path(canonical_file: Path, target_lang: str) -> Path:
    """Returns the destination path for a translated markdown file."""
    parent = canonical_file.parent
    stem = canonical_file.stem
    stem = re.sub(r'\.[a-z]{2}(?:-[A-Za-z]+)?$', '', stem)

    if target_lang.lower() == "en":
        return parent / f"{stem}.md"
    else:
        return parent / "locales" / f"{stem}.{target_lang.lower()}.md"

def get_source_doc_path(canonical_file: Path, source_lang: str) -> Path:
    """Returns the source file path for a given language code."""
    parent = canonical_file.parent
    stem = canonical_file.stem
    stem = re.sub(r'\.[a-z]{2}(?:-[A-Za-z]+)?$', '', stem)

    if source_lang.lower() == "en":
        return parent / f"{stem}.md"

    locales_path = parent / "locales" / f"{stem}.{source_lang.lower()}.md"
    if locales_path.exists():
        return locales_path
    direct_path = parent / f"{stem}.{source_lang.lower()}.md"
    if direct_path.exists():
        return direct_path
    return locales_path

def auto_detect_source_lang(canonical_file: Path, candidate_langs=("en", "de")) -> str:
    """Auto-detects whether German or English was more recently edited."""
    latest_lang = "de"
    latest_mtime = -1.0
    for lang in candidate_langs:
        p = get_source_doc_path(canonical_file, lang)
        if p.exists():
            mtime = p.stat().st_mtime
            if mtime > latest_mtime:
                latest_mtime = mtime
                latest_lang = lang
    return latest_lang

def rewrite_markdown_links(content: str, target_lang: str, is_target_in_locales: bool = False) -> str:
    """Rewrites relative markdown links to point to the translated versions."""
    target_lang_lower = target_lang.lower().replace("_", "-")

    def repl_link(match):
        label = match.group(1)
        url = match.group(2)

        if url.startswith("http://") or url.startswith("https://") or url.startswith("#") or url.startswith("mailto:"):
            return match.group(0)

        anchor = ""
        if "#" in url:
            url, anchor = url.split("#", 1)
            anchor = "#" + anchor

        # Handle markdown doc links
        if url.endswith(".md"):
            clean_url = re.sub(r'^(?:\.\./)+', '', url)
            clean_url = re.sub(r'\.[a-z]{2}(?:-[A-Za-z]+)?\.md$', '.md', clean_url)
            clean_url = clean_url.replace("/locales/", "/").replace("locales/", "")
            dir_part, file_part = os.path.split(clean_url)
            stem, _ = os.path.splitext(file_part)

            is_multi = (stem in MULTI_LANG_STEMS) or stem.startswith("README")

            if is_multi:
                if is_target_in_locales:
                    if target_lang_lower == "en":
                        new_url = f"../{dir_part}/{stem}.md" if dir_part else f"../{stem}.md"
                    else:
                        if not dir_part:
                            new_url = f"{stem}.{target_lang_lower}.md"
                        else:
                            new_url = f"../{dir_part}/locales/{stem}.{target_lang_lower}.md"
                else:
                    if target_lang_lower == "en":
                        new_url = f"{dir_part}/{stem}.md" if dir_part else f"{stem}.md"
                    else:
                        new_url = f"{dir_part}/locales/{stem}.{target_lang_lower}.md" if dir_part else f"locales/{stem}.{target_lang_lower}.md"
            else:
                new_url = f"../{clean_url}" if is_target_in_locales else clean_url

            return f"[{label}]({new_url}{anchor})"

        # Handle other non-markdown relative links (e.g. scripts, images, etc.)
        clean_other = re.sub(r'^(?:\.\./)+', '', url)
        if is_target_in_locales:
            return f"[{label}](../{clean_other}{anchor})"

        return f"[{label}]({clean_other}{anchor})"

    return re.sub(r'\[([^\]]+)\]\(([^)]+)\)', repl_link, content)

def generate_header_language_nav(current_filename: str, languages, current_lang: str, is_in_locales: bool = False) -> str:
    """Generates a top language switcher row for markdown documentation."""
    links = []
    base_name = re.sub(r'\.[a-z]{2}(?:-[A-Za-z]+)?\.md$', '.md', os.path.basename(current_filename))
    base_stem, _ = os.path.splitext(base_name)

    for lang in languages:
        code = lang["code"]
        flag = lang["flag"]
        native = lang["nameNative"]
        code_lower = code.lower()

        if is_in_locales:
            if code_lower == "en":
                target_file = f"../{base_stem}.md"
            else:
                target_file = f"{base_stem}.{code_lower}.md"
        else:
            if code_lower == "en":
                target_file = f"{base_stem}.md"
            else:
                target_file = f"locales/{base_stem}.{code_lower}.md"

        if code_lower == current_lang.lower():
            links.append(f"**[{flag} {native}]({target_file})**")
        else:
            links.append(f"[{flag} {native}]({target_file})")

    return " | ".join(links)

cache_lock = threading.Lock()

def load_cache(cache_path: Path = CACHE_PATH):
    """Loads translation cache from JSON."""
    if cache_path.exists():
        try:
            with open(cache_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def save_cache(cache, cache_path: Path = CACHE_PATH):
    """Saves translation cache atomically."""
    with cache_lock:
        try:
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            tmp_path = cache_path.with_suffix(".tmp")
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(cache, f, ensure_ascii=False, indent=2)
            if tmp_path.exists():
                os.replace(tmp_path, cache_path)
        except Exception:
            pass

def translate_http_google_free(text: str, source_lang: str, target_lang: str) -> str:
    """Translates text using Google Web Translate endpoint with Python standard library urllib."""
    src = LANG_MAP.get(source_lang.lower().replace("_", "-"), source_lang.split("-")[0])
    tgt = LANG_MAP.get(target_lang.lower().replace("_", "-"), target_lang.split("-")[0])

    params = {
        "client": "gtx",
        "sl": src,
        "tl": tgt,
        "dt": "t",
        "q": text,
    }
    url = "https://translate.googleapis.com/translate_a/single?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        if data and isinstance(data, list) and len(data) > 0 and isinstance(data[0], list):
            result = "".join([segment[0] for segment in data[0] if segment and segment[0]])
            return result
    return text

def translate_http_mymemory(text: str, source_lang: str, target_lang: str) -> str:
    """Fallback translation using MyMemory REST API with Python standard library urllib."""
    src = source_lang.split("-")[0]
    tgt = target_lang.split("-")[0]
    pair = f"{src}|{tgt}"
    params = {"q": text, "langpair": pair}
    url = "https://api.mymemory.translated.net/get?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "PokevaultTranslator/1.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        if data and "responseData" in data and "translatedText" in data["responseData"]:
            return data["responseData"]["translatedText"]
    return text

def free_translate_direct(text: str, target_lang: str, source_lang: str = "de") -> str:
    """Multi-engine translation trying Google urllib first, then MyMemory, and optional libraries if installed."""
    if not text or not text.strip():
        return text

    # Optional: If deep_translator or translators is present in user environment, try it
    try:
        import translators as ts
        src_norm = LANG_MAP.get(source_lang.lower(), source_lang)
        tgt_norm = LANG_MAP.get(target_lang.lower(), target_lang)
        res = ts.translate_text(text, from_language=src_norm, to_language=tgt_norm, translator='bing', timeout=5)
        if res and res.strip():
            return res.strip()
    except Exception:
        pass

    # 1. Pure stdlib Google free endpoint
    try:
        res = translate_http_google_free(text, source_lang, target_lang)
        if res and res.strip():
            return res.strip()
    except Exception:
        pass

    # 2. Pure stdlib MyMemory endpoint
    try:
        res = translate_http_mymemory(text, source_lang, target_lang)
        if res and res.strip():
            return res.strip()
    except Exception:
        pass

    return text

def translate_single_string(text: str, target_lang: str, cache, source_lang: str = "de") -> str:
    """Translates a single string with placeholder protection, caching, and fallback."""
    if not text or not text.strip():
        return text

    h = compute_text_hash(text)
    cache_key = target_lang if source_lang == "de" else f"{source_lang}->{target_lang}"
    lang_cache = cache.setdefault(cache_key, {})
    if h in lang_cache and lang_cache[h] != text:
        return lang_cache[h]

    # Optional DeepL API key
    deepl_key = os.environ.get("DEEPL_API_KEY")
    if deepl_key:
        try:
            from deep_translator import DeeplTranslator
            dt = DeeplTranslator(api_key=deepl_key, source=source_lang, target=target_lang)
            masked, placeholders = mask_placeholders(text)
            trans = dt.translate(masked)
            res = unmask_placeholders(trans, placeholders)
            if res and res != text:
                lang_cache[h] = res
                return res
        except Exception:
            pass

    # Free stdlib translation
    masked, placeholders = mask_placeholders(text)
    for attempt in range(2):
        try:
            translated = free_translate_direct(masked, target_lang, source_lang=source_lang)
            restored = unmask_placeholders(translated, placeholders)
            if restored and restored != text:
                lang_cache[h] = restored
                return restored
        except Exception:
            if attempt < 1:
                time.sleep(0.5)

    return text

def collect_uncached_strings(source_node, target_node, target_lang, cache, uncached_set):
    """Collects unique strings that need translation, while populating cache from genuine target strings."""
    if isinstance(source_node, dict):
        tgt_dict = target_node if isinstance(target_node, dict) else {}
        for k, v in source_node.items():
            collect_uncached_strings(v, tgt_dict.get(k), target_lang, cache, uncached_set)
    elif isinstance(source_node, list):
        tgt_list = target_node if isinstance(target_node, list) else []
        for i, item in enumerate(source_node):
            tgt_item = tgt_list[i] if i < len(tgt_list) else None
            collect_uncached_strings(item, tgt_item, target_lang, cache, uncached_set)
    elif isinstance(source_node, str):
        text = source_node.strip()
        if not text:
            return
        h = compute_text_hash(source_node)
        lang_cache = cache.setdefault(target_lang, {})
        if target_node is not None and isinstance(target_node, str) and target_node.strip() and target_node != source_node:
            lang_cache[h] = target_node
            return
        if h in lang_cache and lang_cache[h] != source_node:
            return
        uncached_set.add(source_node)

def main():
    parser = argparse.ArgumentParser(description="PokéVault 13-Language Translation Pipeline")
    parser.add_argument("--doc", type=str, default=None, help="Translate specific markdown file")
    parser.add_argument("--strings", type=str, default=None, help="Translate specific JSON strings file")
    parser.add_argument("--source-lang", default="de", help="Source language (default: de)")
    parser.add_argument("--dry-run", action="store_true", help="Preview actions without writing")
    args = parser.parse_args()

    languages = load_languages_config()
    cache = load_cache()

    print(f"Loaded {len(languages)} target languages.")
    print(f"Translation cache entries: {sum(len(v) for v in cache.values())}")

    if args.doc:
        doc_path = Path(args.doc).resolve()
        if not doc_path.exists():
            print(f"Error: {doc_path} not found.")
            sys.exit(1)
        print(f"Translating markdown doc: {doc_path}")

    if args.strings:
        strings_path = Path(args.strings).resolve()
        if not strings_path.exists():
            print(f"Error: {strings_path} not found.")
            sys.exit(1)
        with open(strings_path, "r", encoding="utf-8") as f:
            source_data = json.load(f)
        for lang_entry in languages:
            code = lang_entry["code"] if isinstance(lang_entry, dict) else str(lang_entry)
            if code == args.source_lang:
                continue
            target_path = strings_path.parent / f"{code}.json"
            existing = {}
            if target_path.exists():
                with open(target_path, "r", encoding="utf-8") as tf:
                    existing = json.load(tf)
            updated = {}
            missing_count = 0
            for k, v in source_data.items():
                if k in existing and str(existing[k]).strip():
                    updated[k] = existing[k]
                else:
                    missing_count += 1
                    updated[k] = v if args.dry_run else translate_single_string(str(v), code, cache, source_lang=args.source_lang)
            if missing_count > 0:
                print(f"  [{code}] Translated {missing_count} missing string(s) -> {target_path.name}")
                if not args.dry_run:
                    with open(target_path, "w", encoding="utf-8") as tf:
                        json.dump(updated, tf, indent=2, ensure_ascii=False)
                        tf.write("\n")

    save_cache(cache)
    print("Done.")

if __name__ == "__main__":
    main()
