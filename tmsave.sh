#!/usr/bin/env bash
# tmsave - Save and restore tmux pane layouts per directory
#
# Functions:
#   tmsave    - Save current layout for $PWD
#   tmre      - Restore saved layout for $PWD
#   tmsave_mv - Move layout from one path key to another

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

  # Get layout string
  local layout
  layout=$(tmux list-windows -F "#{window_layout}")

  # Get pane info
  local panes_json="["
  local first=true
  while IFS='|' read -r index path active; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      panes_json+=","
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
}

# Restore saved layout for $PWD
tmre() {
  _tmsave_check_tmux || return 1

  local dir="${1:-$PWD}"
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

  # Read layout
  local layout
  layout=$(jq -r '.layout' "$layout_file")

  # Get current pane count vs saved pane count
  local current_panes saved_panes
  current_panes=$(tmux list-panes | wc -l)
  saved_panes=$(jq '.panes | length' "$layout_file")

  # Create additional panes if needed
  while (( current_panes < saved_panes )); do
    tmux split-window
    ((current_panes++))
  done

  # Apply layout
  tmux select-layout "$layout"

  # Set working directory for each pane
  local active_pane=0
  while IFS=$'\t' read -r index path active; do
    tmux send-keys -t ".$index" "cd '$path'" Enter
    if [[ "$active" == "true" ]]; then
      active_pane=$index
    fi
  done < <(jq -r '.panes[] | [.index, .path, .active] | @tsv' "$layout_file")

  # Restore active pane
  tmux select-pane -t ".$active_pane"

  echo "Restored layout for: $dir"
}

# Move layout from one path to another
tmsave_mv() {
  if [[ $# -ne 2 ]]; then
    echo "Usage: tmsave_mv <old_path> <new_path>" >&2
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
