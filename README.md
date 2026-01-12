# tmsave

Save and restore tmux pane layouts per directory.

## Installation

Source the script in your shell config:

```bash
source /path/to/tmsave.sh
```

**Dependency:** `jq` (for JSON parsing on restore)

## Usage

### Save layout

```bash
cd ~/myproject
# Set up your panes how you like them
tmsave
```

### Restore layout

```bash
cd ~/myproject
tmre
```

### Move layout to new path

When you relocate a project:

```bash
tmsavemv ~/old/path ~/new/path
```

## How it works

- Layouts are stored in `~/.local/share/tmsave/layouts/`
- Indexed by base64-encoded directory path
- Saves: pane geometry, subdirectory paths, active pane
- Restores: recreates panes, applies layout, `cd`s into subdirectories only where needed

## Notes

- Run `tmsave` from the project root directory
- Panes in subdirectories are restored with relative `cd`
- Panes outside the base directory stay at the base on restore (warning shown on save)
