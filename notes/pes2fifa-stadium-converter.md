---
name: pes2fifa-stadium-converter
description: "pes2fifa (built 2026-11-05) converts PES 2021 / Football Life stadium folders to FIFA 16 PS4 stadium mods without Blender; where it lives, format facts learned, how to test in game"
metadata:
  node_type: memory
  type: project
  originSessionId: 23c5133d-dfde-48e9-abda-4768d167684a
  modified: 2026-11-05T21:37:34.947Z
---

`pes2fifa` (`~/FIFA16Mods/tools/pes2fifa/`, launcher `/opt/homebrew/bin/pes2fifa`, README beside it)
converts a PES stadium-server folder (the one holding `Asset/model/bg/stNNN`) into game-layout files:
`pes2fifa convert "<folder>" --id <FIFA stadium id> --out <dir>`, `pes2fifa preview <dir> --id <id>`
(offline render of the written files incl. crowd seats), then `fifamod install <dir> --name ...`.
First target: Spotify Camp Nou from Football Life 2026 (CrossOver bottle "Football Life 2025",
`SiderAddons/content/stadiums/Spain/Spotify Camp Nou`) -> mod `Spotify_Camp_Nou_PES_2021_conversion`.

Facts that cost time to find:
- Stadium ids come from the db `stadiums` table: Camp Nou = 6 (NOT 10 = Mestalla), Bernabeu 2, Old Trafford 1.
  The kick-off default (Barcelona v Real Madrid) plays at 6, and the menus render it as their backdrop.
- PES world is left-handed (camera side +Z), FIFA right-handed (camera side -Z): p_fifa = 100*(x, y, -z),
  triangle order kept. The Blender tutorial route (rotate 180 deg) yields a MIRRORED stadium. Proof: seat
  lettering (stock crowd file spells MES QUE UN CLUB correctly in a right-handed render).
- `stadium_<id>.rx3` = meshes + materials + scene groups (MainStadium, Alpha, Pitch, AdBoard, Jumbotron, Sky...)
  + props + collision; `rx3.py` round-trips stock files byte for byte. Textures are matched by NAME.
- `ambientTexture` (lightmap, UV set t1) multiplies the diffuse AND drives crowd brightness. Stock levels for
  Camp Nou: seating ~184 by day, ~66 at night, shade 16 / 3. PES albedo is ~1.8x brighter than FIFA's.
- Crowd file `crowd_<id>_<tod>.dat`: 'CRWD', u16 261, u32 count, 32-byte records (pos 3f, angle f =
  atan2(-fz, fx) degrees, seat RGB, type a/b, tier, attendance, ..., variant). PES seats come from
  `audi/#Win/audiarea_*.fpk` quads + `audi/sourceimages/au_seat.png` colour map.
- The game ran the 729k-triangle / 34 MB-texture stadium at 60 fps (Metal build), no decimation needed.

**Why:** the user wants an automated converter instead of the manual two-Blender workflow from the
SoccerGaming video tutorial.

**How to apply:** in-game check = `VIS_STATES=none STOP_WHEN='(^|\|)[0-9]{2}:[0-9]{2}(\||$)' DWELL_SAMPLES=8
KEEP_SHOTS=60 bash ~/fifa_autotest.sh drive metal` (sandbox off): the menu reference shots no longer
match (the stadium is the menu backdrop) and the La Liga scoreboard defeats the in_match detector, so the
verdict line is meaningless; read `~/fifa_metal/runs/<latest>/shots/*.jpg` instead. Time of day is random
per run. To iterate, copy the new `data/sceneassets` into the mod's `files/` and run `fifamod build`.
Still stock in a conversion: ball collision, sideline props/benches, pitch. See [[fifamod-mod-manager]].
