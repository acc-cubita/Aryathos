"""Copies the game's music from the CC0 pieces in art/vendor/audio/music into
game/audio/music (the Audio autoload plays them). The game has no sound effects, by choice.

    python tools/art/audio_pack.py

Sources (all CC0, opengameart.org): TAD, CleytonKauffman, Brandon Morris, Emma_MA.
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "art" / "vendor" / "audio"
OUT = ROOT / "game" / "audio"
MUSIC = {"treasure_hunter.mp3": "music/treasure_hunter.mp3",
         "once_upon_a_time.mp3": "music/once_upon_a_time_loop.mp3",
         "forest_whisper.ogg": "music/forest_whisper/Forest Whisper Theme/Forest Whisper.ogg",
         "orchestra_loop.ogg": "music/rpg.ogg",
         "determined_pursuit.wav": "music/determined_pursuit_loop.wav"}


if __name__ == "__main__":
    (OUT / "music").mkdir(parents=True, exist_ok=True)
    for name, rel in MUSIC.items():
        shutil.copyfile(VENDOR / rel, OUT / "music" / name)
    print("audio: %d music pieces" % len(MUSIC))
