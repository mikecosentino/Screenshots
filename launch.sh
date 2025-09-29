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
CACHE_DIR="/mnt/SDCARD/.userdata/tg5040/Screenshots"
mkdir -p "$CACHE_DIR"

show_status() {
  local msg="$1"
  minui-presenter --message "$msg" --timeout -1 &
  STATUS_PID=$!
  echo "Started status presenter PID=$STATUS_PID ($msg)"
}

hide_status() {
  echo "Killing all minui-presenter instances..."
  killall -q minui-presenter 2>/dev/null || true
  STATUS_PID=""
}

###############################################################################
# Build TXT cache of apps and screenshots
###############################################################################

build_all_apps_cache() {
    show_status "Building screenshots cache..."
    apps="$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name '*.png' \
        -exec basename {} .png \; \
        | sed -E 's/\.[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}$//' \
        | sort -u)"

    # Write all apps into plain text file (with spaces wrapped)
    {
        printf "%s\n" "$apps" | while IFS= read -r app; do
            [ -z "$app" ] && continue
            echo " $app "
        done
    } > "$CACHE_DIR/all_apps.txt"

    # Build screenshot lists per app
    printf "%s\n" "$apps" | while IFS= read -r app; do
        [ -n "$app" ] && {
            build_screenshots_cache "$app"
        }
    done
    hide_status
}

build_screenshots_cache() {
    app="$1"
    out_file="$CACHE_DIR/${app}.txt"

    {
        find "$SCREENSHOT_DIR" -maxdepth 1 -type f -name "${app}.*.png" \
        | sort -r | while IFS= read -r file; do
            [ -z "$file" ] && continue
            base="$(basename "$file")"   # e.g. Castlevania.2025-09-15-12-34-56.png
            ts="${base#${app}.}"         # strip app prefix
            ts="${ts%.png}"              # remove extension
            # Format as YYYY-MM-DD HH:MM:SS
            disp="$(echo "$ts" | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})-([0-9]{2})-([0-9]{2})$/\1 \2:\3:\4/')"
            echo " $disp "
        done
    } > "$out_file"
}

build_presenter_json_for_app() {
    app="$1"
    selected_index="$2"   # 0-based index of the chosen screenshot
    ss_file="$CACHE_DIR/${app}.txt"
    out_file="$CACHE_DIR/${app}.presenter.json"

    [ ! -f "$ss_file" ] && return

    {
        echo '{ "items": ['
        first=1
        idx=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            ts="$(echo "$line" | xargs)"  # pretty string "YYYY-MM-DD HH:MM:SS"
            ts_file="${ts// /-}"
            ts_file="${ts_file//:/-}"
            shot_path="$SCREENSHOT_DIR/${app}.${ts_file}.png"

            [ $first -eq 0 ] && echo ","
            printf '  { "text": "%s", "background_image": "%s", "alignment": "bottom" }' \
                "$ts" "$shot_path"
            first=0
            idx=$((idx+1))
        done < "$ss_file"
        echo "], \"selected\": $selected_index }"
    } > "$out_file"
}

delete_screenshot() {
    app="$1"
    ts="$2"

    # Rebuild file name (convert "YYYY-MM-DD HH:MM:SS" back to YYYY-MM-DD-HH-MM-SS)
    ts_file="${ts// /-}"
    ts_file="${ts_file//:/-}"
    file="$SCREENSHOT_DIR/${app}.${ts_file}.png"

    echo "Deleting screenshot: $file" >>"$LOGS_PATH/$PAK_NAME.txt"
    if [ -f "$file" ]; then
        rm -f "$file"
        minui-presenter --message "Deleted $ts" --timeout 2
        build_screenshots_cache "$app"   # refresh that app’s list
    else
        minui-presenter --message "File not found" --timeout 2
    fi
}

###############################################################################
# Main
###############################################################################

build_all_apps_cache

while true; do
    echo "---- New cycle ----" >>"$LOGS_PATH/$PAK_NAME.txt"

    # Pick an app
    tmp_sel="$(mktemp)"
    minui-list --format text --file "$CACHE_DIR/all_apps.txt" \
        --title "All Apps" --write-location "$tmp_sel"
    selected_app="$(cat "$tmp_sel" | xargs)"
    rm -f "$tmp_sel"

    echo "selected_app raw: '$selected_app'" >>"$LOGS_PATH/$PAK_NAME.txt"
    [ -z "$selected_app" ] && break

    ss_file="$CACHE_DIR/${selected_app}.txt"
    echo "Checking screenshots file: $ss_file" >>"$LOGS_PATH/$PAK_NAME.txt"

    while [ -f "$ss_file" ]; do
        tmp_ss="$(mktemp)"
        minui-list --format text --file "$ss_file" \
            --title "${selected_app}" \
            --action-button "X" --action-text "DELETE" \
            --write-location "$tmp_ss"
        ret=$?                                  # capture exit code FIRST
        sel_line="$(cat "$tmp_ss" | xargs)"     # only read after
        rm -f "$tmp_ss"

        echo "selected_screenshot raw: '$sel_line' (ret=$ret)" >>"$LOGS_PATH/$PAK_NAME.txt"

        if [ $ret -eq 2 ]; then
            # B pressed → back to app list
            break
        elif [ $ret -eq 4 ]; then
            if [ -n "$sel_line" ]; then
                ts="$sel_line"
                ts_file="${ts// /-}"
                ts_file="${ts_file//:/-}"
                shot_path="$SCREENSHOT_DIR/${selected_app}.${ts_file}.png"

                confirm_file="$CACHE_DIR/confirm_delete.json"
                {
                    echo '{ "items": ['
                    echo '  {'
                    echo "    \"text\": \"Delete this screenshot?\","
                    echo "    \"background_image\": \"$shot_path\","
                    echo "    \"alignment\": \"top\""
                    echo '  }'
                    echo '], "selected": 0 }'
                } > "$confirm_file"

                minui-presenter --file "$confirm_file" \
                    --confirm-button "X" --confirm-text "DELETE" --confirm-show \
                    --cancel-button "B" --cancel-text "CANCEL" --cancel-show
                confirm_ret=$?

                if [ $confirm_ret -eq 0 ]; then
                    delete_screenshot "$selected_app" "$ts"
                else
                    echo "Delete cancelled" >>"$LOGS_PATH/$PAK_NAME.txt"
                fi
            fi
            continue
        elif [ -z "$sel_line" ]; then
            # no selection → back to app list
            break
        fi

        # A pressed (ret=0) → open presenter
        sel_index=$(grep -nx " $sel_line " "$ss_file" | cut -d: -f1)
        sel_index=$((sel_index - 1))

        build_presenter_json_for_app "$selected_app" "$sel_index"
        presenter_file="$CACHE_DIR/${selected_app}.presenter.json"
        echo "Opening screenshot set via presenter: $presenter_file" >>"$LOGS_PATH/$PAK_NAME.txt"

        minui-presenter --file "$presenter_file" --cancel-text "Back" --cancel-show
        ret=$?

        if [ $ret -eq 2 ]; then
            # B in presenter → back to screenshot list
            continue
        else
            # Any other exit → back to app list
            break
        fi
    done
done