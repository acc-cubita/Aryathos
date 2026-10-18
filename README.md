# Aryathos

A World of Warcraft-style RPG made in Godot 4: a single-player vertical slice of the Arkanor
starting zone, Silverrun Vale. The lore is in [story.txt](story.txt).

## Running it

1. Download Godot 4.7.2 (standard, win64) and put `Godot_v4.7.2-stable_win64.exe` and
   `Godot_v4.7.2-stable_win64_console.exe` in `tools/godot/`.
2. `Play Game.bat` starts the game; `Open Editor.bat` opens the project in the editor.

Tests (from `game/`):

    ../tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --smoke-test
    ../tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . -- --model-shots=<folder>
    ../tools/godot/Godot_v4.7.2-stable_win64_console.exe --path . -- --scenery=<folder> [--scenery-fps=camp]

## Folders

| Folder | What is in it |
| :--- | :--- |
| `game/` | The Godot project: units, combat, quests, UI, world, data (`.tres`), art and audio it uses. |
| `tools/art/` | Scripts that make the art: textures, foliage, sounds (`audio_pack.py`). |
| `tools/art/blender/` | Blender scripts: characters (MakeHuman/MPFB), beasts, rocks, trees, weapons. |
| `char/` | Concept art and modeling sheets of the races. |
| `art/` | Art sources; third-party downloads go to `art/vendor/` (not in git). |

Third-party assets and their licenses: [game/CREDITS.md](game/CREDITS.md).
