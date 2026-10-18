"""Copies the game's sound effects from the CC0 packs in art/vendor/audio into
game/audio/<set>/<n>.ogg: every set is a few takes of one sound, the game picks one at random
(Audio autoload). The campfire loop is turned into a seamless 16-bit mono WAV.

    python tools/art/audio_pack.py

Sources (all CC0): Kenney Impact Sounds, RPG Audio, Interface Sounds (kenney.nl); rubberduck's
80 CC0 RPG SFX, 80 CC0 creature SFX, 100 CC0 SFX (opengameart.org); "Birds and Wind - Ambient"
by Spring Spring and "fireplace sound loop" by PagDev (opengameart.org).
"""
import shutil
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "art" / "vendor" / "audio"
OUT = ROOT / "game" / "audio"
KI = "kenney_impact-sounds/Audio/"
KR = "kenney_rpg-audio/Audio/"
KU = "kenney_interface-sounds/Audio/"
RPG = "80-CC0-RPG-SFX_0/"
CRE = "80-CC0-creature-SFX_0/"
SFX = "100-CC0-SFX_0/"


def takes(prefix, names):
    return [prefix + n + ".ogg" for n in names]


def numbered(prefix, stem, count, start=0, digits=3):
    return [prefix + "%s%0*d.ogg" % (stem, digits, i) for i in range(start, start + count)]


SETS = {
    # footsteps by ground
    "step_grass": numbered(KI, "footstep_grass_", 5),
    "step_dirt": numbered(KR, "footstep", 10, digits=2),
    "step_rock": numbered(KI, "footstep_concrete_", 5),
    "step_snow": numbered(KI, "footstep_snow_", 5),
    "step_sand": numbered(KI, "footstep_carpet_", 5),
    "paw_heavy": numbered(KI, "impactSoft_heavy_", 5),
    # combat
    "swing": takes(RPG, ["blade_01", "blade_02", "blade_03"]),
    "hit": numbered(KI, "impactPunch_medium_", 5),
    "hit_crit": numbered(KI, "impactPunch_heavy_", 5),
    "hit_crystal": numbered(KI, "impactGlass_light_", 5),
    "spell_cast": takes(RPG, ["spell_01", "spell_02"]),
    "spell_shard": takes(RPG, ["item_gem_01", "item_gem_02", "item_gem_03", "item_gem_04"]),
    "spell_storm": takes(RPG, ["spell_fire_02", "spell_fire_04", "spell_fire_06"]),
    "spell_heal": takes(RPG, ["item_gem_03", "item_gem_04"]),
    # creatures and people
    "wolf_aggro": takes(CRE, ["barking_01", "barking_02", "howl"]),
    "wolf_bite": takes(CRE, ["eat_01", "eat_02", "eat_03", "eat_04"]),
    "wolf_hurt": takes(CRE, ["hurt_01", "hurt_02", "hurt_03"]),
    "wolf_death": takes(RPG, ["creature_die_01"]),
    "bear_aggro": takes(CRE, ["roar_01", "roar_02"]),
    "bear_roar": takes(CRE, ["roar_03"]) + takes(RPG, ["creature_roar_01", "creature_roar_02"]),
    "bear_attack": takes(CRE, ["monster_01", "monster_02", "monster_03", "monster_04"]),
    "bear_hurt": takes(RPG, ["creature_hurt_01", "creature_hurt_02"]),
    "bear_death": takes(RPG, ["creature_roar_03"]),
    "human_aggro": takes(CRE, ["grunt_01", "grunt_02", "grunt_03"]),
    "human_hurt": takes(CRE, ["hurt_04", "hurt_05", "grunt_04", "grunt_05"]),
    "human_death": takes(CRE, ["scream_01", "scream_02"]),
    # things
    "coins": takes(RPG, ["item_coins_01", "item_coins_02", "item_coins_03", "item_coins_04"]),
    "loot": takes(KR, ["handleSmallLeather", "handleSmallLeather2", "cloth1", "cloth2"]),
    "gather": takes(KR, ["cloth3", "cloth4"]),
    # interface
    "ui_open": takes(KR, ["bookOpen"]),
    "ui_close": takes(KR, ["bookClose"]),
    "ui_click": numbered(KU, "click_", 5, start=1),
    "ui_error": numbered(KU, "error_", 3, start=1),
    "ui_quest": takes(SFX, ["bell_01"]),
    "ui_level": takes(SFX, ["gong_01"]),
    "ui_achievement": takes(SFX, ["bell_02"]),
}
AMBIENCE = {"birds_wind.ogg": "ambience/birds_wind_ambient.ogg"}
# CC0 music (opengameart.org): TAD, CleytonKauffman, Brandon Morris, Emma_MA
MUSIC = {"treasure_hunter.mp3": "music/treasure_hunter.mp3",
         "once_upon_a_time.mp3": "music/once_upon_a_time_loop.mp3",
         "forest_whisper.ogg": "music/forest_whisper/Forest Whisper Theme/Forest Whisper.ogg",
         "orchestra_loop.ogg": "music/rpg.ogg",
         "determined_pursuit.wav": "music/determined_pursuit_loop.wav"}
FIRE = "ambience/fireplace_loop.wav"
CROSSFADE = 1.5  # seconds blended from the end into the start


def seamless_mono16(source, target):
    with wave.open(str(source)) as w:
        channels, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        data = np.frombuffer(w.readframes(frames), {2: np.int16, 4: np.int32}[width]).astype(np.float64)
    data = data.reshape(-1, channels).mean(axis=1) / (2 ** (8 * width - 1))
    fade = int(CROSSFADE * rate)
    ramp = np.linspace(0.0, 1.0, fade)
    loop = data[:-fade].copy()
    loop[:fade] = data[:fade] * ramp + data[-fade:] * (1.0 - ramp)
    loop *= 0.9 / max(np.abs(loop).max(), 1e-6)
    with wave.open(str(target), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((loop * 32767).astype(np.int16).tobytes())
    return len(loop) / rate


if __name__ == "__main__":
    for name, files in SETS.items():
        folder = OUT / name
        if folder.exists():
            for old in folder.glob("*.ogg"):
                old.unlink()
        folder.mkdir(parents=True, exist_ok=True)
        for i, rel in enumerate(files):
            shutil.copyfile(VENDOR / rel, folder / ("%d.ogg" % i))
        print("audio: %-15s %d takes" % (name, len(files)))
    (OUT / "ambience").mkdir(parents=True, exist_ok=True)
    for name, rel in AMBIENCE.items():
        shutil.copyfile(VENDOR / rel, OUT / "ambience" / name)
    print("audio: fire loop %.1f s" % seamless_mono16(VENDOR / FIRE, OUT / "ambience" / "fire.wav"))
    (OUT / "music").mkdir(parents=True, exist_ok=True)
    for name, rel in MUSIC.items():
        shutil.copyfile(VENDOR / rel, OUT / "music" / name)
    print("audio: %d music pieces" % len(MUSIC))
