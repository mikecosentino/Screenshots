#!/bin/sh

# Screenshots

PAK_DIR="$(dirname "$0")"
PAK_NAME="${PAK_DIR##*/}"
PAK_NAME="${PAK_NAME%.*}"
set -x
: "${LOGS_PATH:=/mnt/SDCARD/Logs}"
mkdir -p "$LOGS_PATH"
rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt" 2>&1

# Ensure platform tools first on PATH (adjust if needed)
export PATH="$PAK_DIR/bin/tg5040:$PATH"

SCREENSHOT_DIR="/mnt/SDCARD/Screenshots"

# temp/debug files
APPS_LIST="$(mktemp -p /tmp apps.XXXXXX)"
FILES_LABELS="$(mktemp -p /tmp labels.XXXXXX)"
FILES_PATHS="$(mktemp -p /tmp paths.XXXXXX)"
TMP_APPS_UNSORTED=""
TMP_FILES_UNSORTED=""
VIEW_JSON="/tmp/screens_view.json"

# Persistent cache to speed up list building
CACHE_DIR="/mnt/SDCARD/.cache/screenshots"
CACHE_APPS="$CACHE_DIR/apps.txt"
CACHE_SIG_FILE="$CACHE_DIR/sig.txt"
TMP_ALL_INDEX=""

mkdir -p "$CACHE_DIR"

# Compute a signature of current screenshots (hash of sorted basenames)
compute_signature() {
  find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name "*.png" -print \
    | sed 's#.*/##' \
    | sort \
    | md5sum \
    | awk '{print $1}'
}

# Rebuild the entire cache in one pass for speed
rebuild_cache() {
  minui-presenter --message "Building list of screenshots" --timeout 0
  TMP_ALL_INDEX="$(mktemp -p /tmp allidx.XXXXXX)"
  : > "$TMP_ALL_INDEX"

  # Build a master index of: app \t rest \t fullpath
  find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name "*.png" | while IFS= read -r f; do
    base="$(basename "$f")"
    case "$base" in
      *.*.png)
        noext="${base%.png}"
        app="${noext%%.*}"
        rest="${noext#*.}"   # YYYY-MM-DD-HH-MM-SS
        printf '%s\t%s\t%s\n' "$app" "$rest" "$f" >> "$TMP_ALL_INDEX"
        ;;
    esac
  done

  # Apps list
  awk -F '\t' '{print $1}' "$TMP_ALL_INDEX" | sort -u > "$CACHE_APPS"

  # Per-app caches: labels.txt and paths.txt sorted newest first (by rest desc)
  while IFS= read -r appname; do
    [ -z "$appname" ] && continue
    appdir="$CACHE_DIR/app/$appname"
    mkdir -p "$appdir"
    awk -F '\t' -v a="$appname" '$1==a {print $2"\t"$3}' "$TMP_ALL_INDEX" \
      | sort -r > "$appdir/_tmp.sorted"
    : > "$appdir/labels.txt"
    : > "$appdir/paths.txt"
    while IFS=$'\t' read -r rest path; do
      [ -z "$rest" ] && continue
      label="$(format_label "$rest")"
      printf '%s\n' "$label" >> "$appdir/labels.txt"
      printf '%s\n' "$path"  >> "$appdir/paths.txt"
    done < "$appdir/_tmp.sorted"
    rm -f "$appdir/_tmp.sorted"
  done < "$CACHE_APPS"

  # Update signature
  compute_signature > "$CACHE_SIG_FILE"
}

# Ensure cache is up-to-date; rebuild if signature differs or cache missing
ensure_cache() {
  curr_sig="$(compute_signature)"
  old_sig=""
  [ -f "$CACHE_SIG_FILE" ] && old_sig="$(cat "$CACHE_SIG_FILE" 2>/dev/null)"
  if [ ! -s "$CACHE_APPS" ] || [ "$curr_sig" != "$old_sig" ]; then
    rebuild_cache
  fi
}

cleanup() {
  echo "Cleanup skipped (debug). Files:"
  echo "  APPS_LIST=$APPS_LIST"
  echo "  FILES_LABELS=$FILES_LABELS"
  echo "  FILES_PATHS=$FILES_PATHS"
  echo "  VIEW_JSON=$VIEW_JSON"
}
trap cleanup EXIT

# ---------- helpers ----------

show_msg() {
  msg="$1"
  secs="${2:-2}"
  minui-presenter --message "$msg" --timeout "$secs"
}

# Convert YYYY-MM-DD-HH-MM-SS -> "YYYY-MM-DD HH:MM:SS"
format_label() {
  echo "$1" | awk -F- '{printf "%s-%s-%s %s:%s:%s",$1,$2,$3,$4,$5,$6}'
}

# Show a TEXT list with a title, return 0-based index
present_index_titled() {
  file="$1"
  title="$2"
  idxfile="$(mktemp -p /tmp idx.XXXXXX)"
  out="$(minui-list --format text --file "$file" --title "$title" --write-location "$idxfile" 2>/dev/null)"
  rc=$?
  [ $rc -ne 0 ] && return 1

  # minui-list (text) writes the LABEL to idxfile/stdout, not an index
  sel="$(tr -d '\r\n' < "$idxfile")"
  [ -z "$sel" ] && sel="$out"
  [ -z "$sel" ] && return 1

  lineno="$(grep -n -F -x -- "$sel" "$file" | head -n1 | cut -d: -f1)"
  [ -z "$lineno" ] && return 1
  echo $((lineno - 1))
  return 0
}

# ---------- builders ----------

build_apps_list() {
  ensure_cache
  # Point APPS_LIST to cached file for minui-list
  cp "$CACHE_APPS" "$APPS_LIST"
  echo "DEBUG: apps=$(wc -l < \"$APPS_LIST\") -> $APPS_LIST"
}

build_file_lists_for_app() {
  choice_app="$1"
  ensure_cache
  appdir="$CACHE_DIR/app/$choice_app"
  > "$FILES_LABELS"
  > "$FILES_PATHS"
  if [ -d "$appdir" ]; then
    cat "$appdir/labels.txt" > "$FILES_LABELS"
    cat "$appdir/paths.txt"  > "$FILES_PATHS"
  fi
  echo "DEBUG: files=$(wc -l < \"$FILES_LABELS\") -> $FILES_LABELS (paths=$FILES_PATHS)"
}

# Build a minui-presenter JSON for L/R navigation within an app's screenshots
build_view_json() {
  selected_idx="$1"  # 0-based
  : > "$VIEW_JSON"
  echo '{ "items": [' >> "$VIEW_JSON"

  total="$(wc -l < "$FILES_LABELS")"
  i=0
  while IFS= read -r label && IFS= read -r path <&3; do
    printf '  { "text": "%s", "background_image": "%s", "show_pill": true, "alignment": "top" }' \
      "$label" "$path" >> "$VIEW_JSON"
    i=$((i+1))
    [ $i -lt $total ] && echo ',' >> "$VIEW_JSON" || echo '' >> "$VIEW_JSON"
  done < "$FILES_LABELS" 3<"$FILES_PATHS"

  echo '  ], "selected": '"$selected_idx"' }' >> "$VIEW_JSON"
}

# ---------- main ----------

while :; do
  ensure_cache
  build_apps_list
  [ ! -s "$APPS_LIST" ] && { show_msg "No screenshots found" 2; exit 0; }

  # Page 1: title = "Screenshots"
  app_idx="$(present_index_titled "$APPS_LIST" "Screenshots")" || exit 0
  APP_CHOICE="$(awk -v i="$app_idx" 'NR==i+1{print; exit}' "$APPS_LIST")"
  [ -z "$APP_CHOICE" ] && continue
  echo "DEBUG: APP_CHOICE='$APP_CHOICE'"

  # Page 2 loop: title = app name; A=VIEW
  while :; do
    build_file_lists_for_app "$APP_CHOICE"
    [ ! -s "$FILES_LABELS" ] && break

    idxfile="$(mktemp -p /tmp idx.XXXXXX)"
    out="$(minui-list --format text \
            --file "$FILES_LABELS" \
            --title "$APP_CHOICE" \
            --write-location "$idxfile" 2>/dev/null)"
    rc=$?

    # Resolve selected TEXT -> index -> path
    sel="$(tr -d '\r\n' < "$idxfile")"
    [ -z "$sel" ] && sel="$out"
    [ -z "$sel" ] && { [ "$rc" -ge 2 ] && break; continue; }

    lineno="$(grep -n -F -x -- "$sel" "$FILES_LABELS" | head -n1 | cut -d: -f1)"
    [ -z "$lineno" ] && { echo "WARN: could not map selection '$sel'"; continue; }
    file_idx=$((lineno - 1))
    SEL_PATH="$(awk -v i="$file_idx" 'NR==i+1{print; exit}' "$FILES_PATHS")"
    [ -z "$SEL_PATH" ] && continue

    case "$rc" in
      0)  # A pressed → view with L/R navigation
          build_view_json "$file_idx"
          minui-presenter \
            --cancel-show \
            --cancel-text "EXIT" \
            --timeout 0 \
            --font-size-default 12 \
            --file "$VIEW_JSON"
          ;;
      2|3) # B/Menu → back
          break
          ;;
      *)  # anything else: back
          break
          ;;
    esac
  done
done