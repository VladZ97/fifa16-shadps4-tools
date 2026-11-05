#!/usr/bin/env python3
"""ball_originals.py <overlay-name> [--textures-original]
Links every ball mesh of the Metal overlay to FIP's unmodified high-poly original
(Manual Install/fip/_overwritten_by_mac_apply/balls-highpoly) and, with --textures-original,
every ball texture to the Manual Install's own file instead of the header-fixed copy.
Only replaces symlinks. Prints a summary. Rollback: make_fip_overlay.py rebuilds the stripified links."""
import os, sys
HP = '/Volumes/SanDiskSSD/Manual Install/fip/_overwritten_by_mac_apply/balls-highpoly'
MI = '/Volumes/SanDiskSSD/Manual Install/data/sceneassets/ball'
name = sys.argv[1]; tex_orig = '--textures-original' in sys.argv
O = os.path.expanduser(f'~/fifa_perf/overlay/{name}/data/sceneassets/ball')
meshes = textures = skipped = 0
for n in sorted(os.listdir(O)):
    p = os.path.join(O, n)
    if not os.path.islink(p) or not n.endswith('.rx3'):
        continue
    if n.endswith('_textures.rx3'):
        if tex_orig and os.path.exists(os.path.join(MI, n)):
            os.unlink(p); os.symlink(os.path.join(MI, n), p); textures += 1
        continue
    src = os.path.join(HP, n)
    if os.path.exists(src):
        os.unlink(p); os.symlink(src, p); meshes += 1
    else:
        skipped += 1
print(f'{meshes} ball meshes -> FIP high-poly originals, {textures} textures -> Manual Install originals, {skipped} meshes without an original left as they were')
