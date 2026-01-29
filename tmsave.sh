#!/usr/bin/env bash
# tmsave - Save and restore tmux pane layouts per directory
#
# Functions:
#   tmsave    - Save current layout for $PWD
#   tmre      - Restore saved layout for $PWD (or from another dir, -n to skip ~/.bashrc)
#   tmlist    - List all saved layouts
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
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
Usage: tmsave [-D] [directory]

Save the current tmux window layout for a directory.

Options:
  -D          Save a default 3-pane layout (only if no layout exists)

Arguments:
  directory   Directory to associate with layout (default: $PWD)

The layout includes pane geometry, subdirectory paths, and active pane.
Layouts are stored in ~/.local/share/tmsave/layouts/
EOF
    return 0
  fi

  # Handle -D flag for default layout
  if [[ "$1" == "-D" ]]; then
    _tmsave_check_tmux || return 1

    local dir="${2:-$PWD}"
    local encoded=$(_tmsave_encode_path "$dir")
    local layout_file="$TMSAVE_DIR/$encoded.json"

    if [[ -f "$layout_file" ]]; then
      echo "Error: Layout already exists for: $dir" >&2
      echo "Use 'tmsave' without -D to overwrite, or delete the existing layout first." >&2
      return 1
    fi

    mkdir -p "$TMSAVE_DIR"

    local escaped_dir
    escaped_dir=$(echo "$dir" | sed 's/\\/\\\\/g; s/"/\\"/g')

    cat > "$layout_file" << EOF
{
  "path": "$escaped_dir",
  "layout": "2c26,361x83,0,0{229x83,0,0,4,131x83,230,0[131x41,230,0,5,131x41,230,42,6]}",
  "panes": [
    {"index":0,"path":"$escaped_dir","active":true},
    {"index":1,"path":"$escaped_dir","active":false},
    {"index":2,"path":"$escaped_dir","active":false}
  ],
  "saved_at": "$(date -Iseconds)"
}
EOF

    echo "Saved default layout for: $dir"
    return 0
  fi

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
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
Usage: tmre [source_dir]

Restore a saved tmux layout to the current directory.

Arguments:
  source_dir  Load layout from this directory instead of $PWD
              Useful for git worktrees - reuse main branch layout

Examples:
  tmre                  # Restore layout saved for current directory
  tmre ~/project/main   # Apply ~/project/main's layout to current directory

Subdirectory panes are mapped relatively to your current directory.
EOF
    return 0
  fi

  _tmsave_check_tmux || return 1

  local source_dir=""
  local target_dir="$PWD"
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
        if [[ -z "$source_dir" ]]; then
          # Resolve to absolute path
          source_dir="$(cd "$1" 2>/dev/null && pwd)" || {
            echo "Error: Cannot access directory: $1" >&2
            return 1
          }
        else
          echo "Usage: tmre [-n|--no-source] [source_dir]" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$source_dir" ]]; then
    source_dir="$target_dir"
  fi

  local encoded=$(_tmsave_encode_path "$source_dir")
  local layout_file="$TMSAVE_DIR/$encoded.json"

  if [[ ! -f "$layout_file" ]]; then
    echo "No saved layout for: $source_dir" >&2
    return 1
  fi

  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    return 1
  fi

  # Read layout and pane info
  local layout saved_panes saved_base_path
  layout=$(jq -r '.layout' "$layout_file")
  saved_panes=$(jq '.panes | length' "$layout_file")
  saved_base_path=$(jq -r '.path' "$layout_file")

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

  # Source bashrc (if enabled) and cd into subdirectories where needed
  # Use saved_base_path to calculate relative paths, apply to target_dir
  for i in "${!pane_paths[@]}"; do
    local pane_path="${pane_paths[$i]}"
    local cmd=""
    if [[ "$source_env" == "true" ]]; then
      cmd="[[ -f ~/.bashrc ]] && source ~/.bashrc >/dev/null 2>&1"
    fi
    # Only cd if it's a subdirectory of the original base path
    if [[ "$pane_path" == "$saved_base_path/"* ]]; then
      local relative="${pane_path#$saved_base_path/}"
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

  if [[ "$source_dir" != "$target_dir" ]]; then
    echo "Restored layout from: $source_dir (applied to: $target_dir)"
  else
    echo "Restored layout for: $target_dir"
  fi
}

# List all saved layouts
tmlist() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
Usage: tmlist [--json]

List all saved tmux layouts.

Options:
  --json    Output as JSON array (for scripting)

Without --json, displays a human-readable list with path, pane count,
and save date.
EOF
    return 0
  fi

  local json_mode=false
  if [[ "$1" == "--json" ]]; then
    json_mode=true
  fi

  # Check if layouts directory exists
  if [[ ! -d "$TMSAVE_DIR" ]]; then
    if [[ "$json_mode" == "true" ]]; then
      echo "[]"
    else
      echo "No saved layouts."
    fi
    return 0
  fi

  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    return 1
  fi

  local files=("$TMSAVE_DIR"/*.json)

  # Check if any files exist
  if [[ ! -f "${files[0]}" ]]; then
    if [[ "$json_mode" == "true" ]]; then
      echo "[]"
    else
      echo "No saved layouts."
    fi
    return 0
  fi

  if [[ "$json_mode" == "true" ]]; then
    # JSON output - array of layout objects
    local first=true
    echo "["
    for f in "${files[@]}"; do
      if [[ "$first" == "true" ]]; then
        first=false
      else
        echo ","
      fi
      jq '{path, panes: (.panes | length), saved_at}' "$f"
    done
    echo "]"
  else
    # Human-readable output
    printf "%-50s %5s  %s\n" "PATH" "PANES" "SAVED"
    printf "%s\n" "$(printf '%.0s-' {1..75})"
    for f in "${files[@]}"; do
      local path panes saved_at
      path=$(jq -r '.path' "$f")
      panes=$(jq '.panes | length' "$f")
      saved_at=$(jq -r '.saved_at' "$f")
      # Format date more nicely (remove timezone for brevity)
      local date_fmt
      date_fmt=$(echo "$saved_at" | cut -d'+' -f1 | tr 'T' ' ')
      printf "%-50s %5s  %s\n" "$path" "$panes" "$date_fmt"
    done
  fi
}

# Move layout from one path to another
tmsavemv() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
Usage: tmsavemv <old_path> <new_path>

Move a saved layout from one path key to another.

Useful when you relocate a project directory. Updates the stored
path reference and renames the layout file.

Example:
  tmsavemv ~/old/project ~/new/project
EOF
    return 0
  fi

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
