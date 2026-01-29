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

### Apply layout from another directory (git worktrees)

Pass a directory to load its layout and apply it to your current directory. Subdirectory panes are mapped relatively.

```bash
# You have a layout saved for your main worktree
cd ~/myproject-feature-branch
tmre ~/myproject

# Pane that was at ~/myproject/ui → opens at ~/myproject-feature-branch/ui
```

### List saved layouts

```bash
tmlist          # Human-readable table
tmlist --json   # JSON array for scripting
```

### Move layout to new path

When you relocate a project:

```bash
tmsavemv ~/old/path ~/new/path
```

### Help

All commands support `-h` / `--help`:

```bash
tmsave --help
tmre --help
tmlist --help
tmsavemv --help
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
