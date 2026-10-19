"""Frames out of a reference video (Blender's own FFmpeg reads it), for studying motion.

    blender -b --python tools/art/video_frames.py -- <video> <out folder> <first> <last> <step> [scale]

Saves <out>/<frame>.png for every `step`-th frame from `first` to `last` (1-based),
scaled by `scale` (default 1). The frames are study material only: they stay out of
the repository.
"""
import sys
from pathlib import Path

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
video, out = args[0], Path(args[1])
first, last, step = int(args[2]), int(args[3]), int(args[4])
scale = float(args[5]) if len(args) > 5 else 1.0
out.mkdir(parents=True, exist_ok=True)

scene = bpy.context.scene
scene.sequence_editor_create()
editor = scene.sequence_editor
strips = editor.strips if hasattr(editor, "strips") else editor.sequences
clip = bpy.data.movieclips.load(video)
# rendered at the video's own size (a smaller render crops or refits the strip), then
# the saved picture is scaled
scene.render.resolution_x = clip.size[0]
scene.render.resolution_y = clip.size[1]
strip = strips.new_movie("video", video, 1, 1)
strip.transform.scale_x = strip.transform.scale_y = 1.0
scene.render.resolution_percentage = 100
scene.render.fps = round(clip.fps)
scene.frame_end = clip.frame_duration
scene.render.image_settings.file_format = "PNG"
for frame in range(first, min(last, clip.frame_duration) + 1, step):
    scene.frame_set(frame)
    path = str(out / ("%05d.png" % frame))
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    if scale != 1.0:
        image = bpy.data.images.load(path)
        image.scale(int(clip.size[0] * scale), int(clip.size[1] * scale))
        image.save()
        bpy.data.images.remove(image)
print("frames: saved", out)
