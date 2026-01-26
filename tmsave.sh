#!/usr/bin/env bash
# tmsave - Save and restore tmux pane layouts per directory
#
# Functions:
#   tmsave    - Save current layout for $PWD
#   tmre      - Restore saved layout for $PWD (use -n/--no-source to skip ~/.bashrc)
#   tmsavemv  - Move layout from one path key to another

TMSAVE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmsave/layouts"

# Helper: encode path to safe filename
_tmsave_encode_path() {
  echo -n "$1" | base64 | tr '/+' '_-' | tr -d '='
}

# Helper: check if inside tmux
_tmsave_check_tmux() {
  if [[ -z "$TMUX" ]]; then
    echo "Error: Not inside a tmux session" >&2
    return 1
  fi
}

# Save current tmux layout for $PWD
tmsave() {
  _tmsave_check_tmux || return 1

  local dir="${1:-$PWD}"
  local encoded=$(_tmsave_encode_path "$dir")
  local layout_file="$TMSAVE_DIR/$encoded.json"

  # Ensure storage directory exists
  mkdir -p "$TMSAVE_DIR"

  # Get layout string for current window only
  local layout
  layout=$(tmux display-message -p "#{window_layout}")

  # Get pane info (only path and active status)
  local panes_json="["
  local first=true
  local has_outside=false
  while IFS='|' read -r index path active; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      panes_json+=","
    fi

    # Check if pane is outside base dir
    if [[ "$path" != "$dir" && "$path" != "$dir/"* ]]; then
      has_outside=true
    fi

    # Escape path for JSON
    local escaped_path
    escaped_path=$(echo "$path" | sed 's/\\/\\\\/g; s/"/\\"/g')
    panes_json+="{\"index\":$index,\"path\":\"$escaped_path\",\"active\":$([[ "$active" == "1" ]] && echo "true" || echo "false")}"
  done < <(tmux list-panes -F "#{pane_index}|#{pane_current_path}|#{pane_active}")
  panes_json+="]"

  # Escape dir for JSON
  local escaped_dir
  escaped_dir=$(echo "$dir" | sed 's/\\/\\\\/g; s/"/\\"/g')

  # Write JSON
  cat > "$layout_file" << EOF
{
  "path": "$escaped_dir",
  "layout": "$layout",
  "panes": $panes_json,
  "saved_at": "$(date -Iseconds)"
}
EOF

  echo "Saved layout for: $dir"
  if [[ "$has_outside" == "true" ]]; then
    echo "Warning: Some panes were outside this directory (will stay at base on restore)"
  fi
}

# Restore saved layout for $PWD
tmre() {
  _tmsave_check_tmux || return 1

  local dir=""
  local source_env=true

  while (( $# > 0 )); do
    case "$1" in
      -n|--no-source)
        source_env=false
        shift
        ;;
      -*)
        echo "Unknown option: $1" >&2
        return 1
        ;;
      *)
        if [[ -z "$dir" ]]; then
          dir="$1"
        else
          echo "Usage: tmre [-n|--no-source] [path]" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$dir" ]]; then
    dir="$PWD"
  fi
  local encoded=$(_tmsave_encode_path "$dir")
  local layout_file="$TMSAVE_DIR/$encoded.json"

  if [[ ! -f "$layout_file" ]]; then
    echo "No saved layout for: $dir" >&2
    return 1
  fi

  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    return 1
  fi

  # Read layout and pane info
  local layout saved_panes
  layout=$(jq -r '.layout' "$layout_file")
  saved_panes=$(jq '.panes | length' "$layout_file")

  # Read pane data into arrays
  local -a pane_paths
  local active_pane=0
  while IFS=$'\t' read -r index path active; do
    pane_paths[$index]="$path"
    if [[ "$active" == "true" ]]; then
      active_pane=$index
    fi
  done < <(jq -r '.panes[] | [.index, .path, .active] | @tsv' "$layout_file")

  # Get current pane count
  local current_panes
  current_panes=$(tmux list-panes | wc -l)

  # Create additional panes (they inherit current directory)
  while (( current_panes < saved_panes )); do
    tmux split-window
    ((current_panes++))
  done

  # Apply layout
  tmux select-layout "$layout"

  # source bashrc and cd into subdirectories where needed
  for i in "${!pane_paths[@]}"; do
    local pane_path="${pane_paths[$i]}"
    local cmd=""
    if [[ "$source_env" == "true" ]]; then
      cmd="[[ -f ~/.bashrc ]] && source ~/.bashrc >/dev/null 2>&1"
    fi
    # Only cd if it's a subdirectory of current dir
    if [[ "$pane_path" == "$dir/"* ]]; then
      local relative="${pane_path#$dir/}"
      if [[ -n "$cmd" ]]; then
        cmd="$cmd; cd '$relative'"
      else
        cmd="cd '$relative'"
      fi
    fi
    if [[ -n "$cmd" ]]; then
      tmux send-keys -t ".$i" "$cmd" Enter
    fi
  done

  # Restore active pane
  tmux select-pane -t ".$active_pane"

  echo "Restored layout for: $dir"
}

# Move layout from one path to another
tmsavemv() {
  if [[ $# -ne 2 ]]; then
    echo "Usage: tmsavemv <old_path> <new_path>" >&2
    return 1
  fi

  local old_path="$1"
  local new_path="$2"

  local old_encoded=$(_tmsave_encode_path "$old_path")
  local new_encoded=$(_tmsave_encode_path "$new_path")

  local old_file="$TMSAVE_DIR/$old_encoded.json"
  local new_file="$TMSAVE_DIR/$new_encoded.json"

  if [[ ! -f "$old_file" ]]; then
    echo "No saved layout for: $old_path" >&2
    return 1
  fi

  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    return 1
  fi

  # Update path in JSON and write to new file
  jq --arg new_path "$new_path" '.path = $new_path' "$old_file" > "$new_file"

  # Remove old file
  rm "$old_file"

  echo "Moved layout: $old_path -> $new_path"
}
