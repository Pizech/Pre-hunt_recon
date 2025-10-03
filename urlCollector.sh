#!/usr/bin/env bash
# katana_gobuster_one_shot.sh
# ---------------------------------
# This script:
# 1) Runs Katana (headless if possible) and saves JSONL output
# 2) Extracts unique URLs from Katana output
# 3) Runs Gobuster (directory mode) with a wordlist and saves raw output
# 4) Normalizes Gobuster output into full URLs
# 5) Runs gau (get-all-urls) to collect historical/OSINT URLs and normalizes them
# 6) Produces files with entries that are in Gobuster but NOT in Katana, and in Gau but NOT in Katana
# 7) Combines the Katana + Gobuster + Gau URL lists (union, not recursive)
# 8) Produces a file containing only URLs whose path ends with .js
#
# Usage: ./katana_gobuster_one_shot.sh https://example.com /path/to/wordlist.txt
# If wordlist is omitted, defaults to a common SecLists wordlist.

set -euo pipefail   # Exit on error, treat unset vars as errors, fail pipelines on any error
IFS=$'
	'        # Set IFS to newline+tab to avoid surprising word-splitting

# --- Argument parsing -----------------------------------------------------
if [[ "$#" -lt 1 ]]; then
  # If no arguments provided, print usage and exit
  echo "Usage: $0 <target> [wordlist]"
  echo "Example: $0 https://example.com /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt"
  exit 1
fi

TARGET="$1"  # First CLI arg: target URL (e.g., https://example.com)
# Second CLI arg (optional) or fallback default wordlist
WORDLIST="${2:-/usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt}"
THREADS=40    # Default concurrency for gobuster

# --- Output filenames (centralized) -------------------------------------
KATANA_URLS="katana_urls.txt"      # extracted unique URLs from katana
GOB_RAW="gobuster_raw.txt"         # raw gobuster stdout/stderr saved
GOB_URLS="gobuster_urls.txt"       # normalized URLs extracted from gobuster output
GAU_RAW="gau_raw.txt"              # raw gau output
GAU_URLS="gau_urls.txt"            # normalized URLs from gau output
COMBINED="combined_urls.txt"       # union of katana + gobuster + gau
JS_ONLY="js_files.txt"             # only URLs whose path ends with .js
GOB_ONLY="gobuster_not_in_katana.txt"  # URLs found by gobuster but not by katana
GAU_ONLY="gau_not_in_katana.txt"       # URLs found by gau but not by katana

# --- Helper: check required commands -------------------------------------
command_exists(){ command -v "$1" >/dev/null 2>&1; }
if ! command_exists katana; then
  echo "Error: katana is not installed or not in PATH."
  exit 2
fi
if ! command_exists gobuster; then
  echo "Error: gobuster is not installed or not in PATH."
  exit 2
fi
if ! command_exists jq; then
  echo "Error: jq is required but not installed."
  exit 2
fi
if ! command_exists gau; then
  echo "Error: gau (get-all-urls) is not installed or not in PATH."
  echo "If you don't want to use gau, you can install it from https://github.com/lc/gau or skip this script's gau step."
  exit 2
fi

# Remove any trailing slash from target to avoid double slashes when prefixing
TARGET_NO_TRAIL="${TARGET%/}"

echo "[*] Target: $TARGET_NO_TRAIL"
echo "[*] Wordlist: $WORDLIST"

# Temporary files setup (cleaned up on exit)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- 1) Run Katana (prefer headless/system-chrome, fallback to plain) -----
echo "[*] Running katana (this may take a while if headless JS is used)..."
# Try headless with system Chrome first; if it fails, run without headless
if katana -u "$TARGET_NO_TRAIL" -system-chrome -headless -o "$KATANA_URLS"; then
  echo "[*] Katana finished (headless)."
else
  echo "[!] Katana headless failed; running plain crawl..."
  # Plain crawl (non-headless) as fallback
  katana -u "$TARGET_NO_TRAIL" -o "$KATANA_URLS"
fi


# --- 3) Run Gobuster (dir mode) and save raw output -----------------------
echo "[*] Running gobuster (dir mode)..."
if gobuster dir -u "$TARGET_NO_TRAIL" -w "$WORDLIST" -t "$THREADS" -x php,html,js,txt -o "$GOB_RAW" -q; then
  echo "[*] Gobuster finished. Raw output -> $GOB_RAW"
else
  echo "[!] Gobuster returned non-zero exit code (check $GOB_RAW)."
fi

# --- 4) Normalize gobuster output into full URLs -------------------------
echo "[*] Normalizing gobuster results -> $GOB_URLS"
if [[ -s "$GOB_RAW" ]]; then
  # Extract tokens that are full URLs or absolute paths
  grep -oP 'https?://[^ ]+|/[^ ]+' "$GOB_RAW" 2>/dev/null || true
else
  :
fi | while read -r token; do
  [[ -z "$token" ]] && continue
  if [[ "$token" =~ ^/ ]]; then
    echo "${TARGET_NO_TRAIL}${token}"
  else
    echo "$token"
  fi
done | sed '/^$/d' | sort -u > "$GOB_URLS"

# --- 5) Run gau (get-all-urls) to collect historical/OSINT URLs ------------
echo "[*] Running gau (get-all-urls) to collect known/historical URLs..."
# Gau typically prints full URLs; capture raw output
if gau "$TARGET_NO_TRAIL" > "$GAU_RAW" 2>/dev/null; then
  echo "[*] Gau finished -> $GAU_RAW"
else
  echo "[!] Gau returned non-zero exit code (check $GAU_RAW). Continuing..."
fi

# Normalize gau output into full URLs (some entries may be only paths)
echo "[*] Normalizing gau results -> $GAU_URLS"
if [[ -s "$GAU_RAW" ]]; then
  # Gau usually outputs full URLs, but be defensive and normalize paths starting with '/'
  grep -oP 'https?://[^ ]+|/[^ ]+' "$GAU_RAW" 2>/dev/null || true
else
  :
fi | while read -r token; do
  [[ -z "$token" ]] && continue
  if [[ "$token" =~ ^/ ]]; then
    echo "${TARGET_NO_TRAIL}${token}"
  else
    echo "$token"
  fi
done | sed '/^$/d' | sort -u > "$GAU_URLS"

# --- 6) Produce files with Gobuster-only and Gau-only entries (not in Katana) ---
echo "[*] Producing Gobuster-only and Gau-only files (items not present in katana)"
# Ensure sorted unique copies for comm operations
sort -u "$GOB_URLS" -o "$TMPDIR/gob_sorted.txt" || true
sort -u "$GAU_URLS" -o "$TMPDIR/gau_sorted.txt" || true
sort -u "$KATANA_URLS" -o "$TMPDIR/kat_sorted.txt" || true

# Lines in gob_sorted that are NOT in kat_sorted -> gob_only
if [[ -s "$TMPDIR/gob_sorted.txt" ]]; then
  comm -23 "$TMPDIR/gob_sorted.txt" "$TMPDIR/kat_sorted.txt" > "$GOB_ONLY" || true
else
  : > "$GOB_ONLY"
fi
# Lines in gau_sorted that are NOT in kat_sorted -> gau_only
if [[ -s "$TMPDIR/gau_sorted.txt" ]]; then
  comm -23 "$TMPDIR/gau_sorted.txt" "$TMPDIR/kat_sorted.txt" > "$GAU_ONLY" || true
else
  : > "$GAU_ONLY"
fi

# --- 7) Combine all sources (union & dedupe) ------------------------------
echo "[*] Combining katana, gobuster, and gau -> $COMBINED"
cat "$KATANA_URLS" "$GOB_URLS" "$GAU_URLS" | sed '/^$/d' | sort -u > "$COMBINED"

# --- 8) Produce .js-only file list (path ends with .js) -------------------
echo "[*] Extracting .js URLs -> $JS_ONLY"
awk -F'?' '{print $0 "	" $1}' "$COMBINED" | while IFS=$'	' read -r full urlpath; do
  if [[ "$urlpath" =~ \.js$ ]]; then
    echo "$full"
  fi
done > "$JS_ONLY"

# --- Final summary -------------------------------------------------------
echo "
[+] Done. Files created/updated:"
ls -l "$KATANA_URLS" "$GOB_RAW" "$GOB_URLS" "$GAU_RAW" "$GAU_URLS" "$GOB_ONLY" "$GAU_ONLY" "$COMBINED" "$JS_ONLY" 2>/dev/null || true

echo "
Tip: Review $COMBINED before feeding into scanners. Be sure you have permission to test the target."
