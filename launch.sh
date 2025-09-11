#!/bin/sh
# Screenshots. A MinUI pak for browsing your saved screenshots. Automatically organized by game/app.
# Mike Cosentino

PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
set -x

rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1

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
CACHE_MAX_AGE=$((24 * 60 * 60)) # 24 hours
CACHE_DIR="/mnt/SDCARD/.userdata/tg5040/Screenshots"
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
  minui-presenter --message "Building list of screenshots" --timeout 2
  TMP_ALL_INDEX="$(mktemp -p /tmp allidx.XXXXXX)"
  : > "$TMP_ALL_INDEX"

  # Build a master index of: app \t rest \t fullpath
  find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name "*.png" | while IFS= read -r f; do
    base="$(basename "$f")"
    case "$base" in
      *.png)
        noext="${base%.png}"
        # Extract timestamp using simple pattern matching
        timestamp="$(echo "$noext" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}$')"
        if [ -n "$timestamp" ]; then
          # Get app name by removing timestamp pattern from the end
          app="${noext%.$timestamp}"
          printf '%s\t%s\t%s\n' "$app" "$timestamp" "$f" >> "$TMP_ALL_INDEX"
        fi
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
  # Only check cache once per session unless forced
  [ -n "$CACHE_CHECKED" ] && return 0
  CACHE_CHECKED=1

  curr_sig="$(compute_signature)"
  old_sig=""
  
  if [ -f "$CACHE_SIG_FILE" ]; then
    old_sig="$(cat "$CACHE_SIG_FILE" 2>/dev/null)"
  fi
  
  # Only rebuild if signatures differ or cache is missing
  if [ ! -s "$CACHE_APPS" ] || [ "$curr_sig" != "$old_sig" ]; then
    rebuild_cache
  fi
}

delete_screenshot() {
    echo "DEBUG: delete_screenshot called with file=$1"
    local file="$1"
    local base="$(basename "$file")"
    
    # Show confirmation dialog
    minui-presenter \
      --message "Delete: $base" \
      --confirm-button A \
      --confirm-text "YES" \
      --confirm-show \
      --cancel-button B \
      --cancel-text "NO" \
      --cancel-show \
      --timeout 0
    
    rc=$?
    echo "DEBUG: minui-presenter confirmation rc=$rc"
    if [ "$rc" = "0" ]; then  # A pressed = Yes
        echo "DEBUG: Deleting file $file"
        rm -f "$file"
        show_msg "Screenshot deleted" 1
        # Force cache rebuild on next check
        CACHE_CHECKED=""
        echo "DEBUG: delete_screenshot returning success"
        return 0
    fi
    echo "DEBUG: delete_screenshot cancelled"
    return 1
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
            --file "$VIEW_JSON" \
            --action-button X \
            --action-text "DELETE" \
            --action-show \
            --cancel-show \
            --cancel-text "EXIT" \
            --timeout 0 \
            --font-size-default 12
          rc=$?
          case "$rc" in
            0) ;;  # A pressed inside viewer, do nothing special
            2) ;;  # Cancel/Exit pressed inside viewer, do nothing special
            4) if delete_screenshot "$SEL_PATH"; then
                # after successful delete, rebuild list
                continue 2
              fi ;;  # X pressed → delete screenshot
          esac
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