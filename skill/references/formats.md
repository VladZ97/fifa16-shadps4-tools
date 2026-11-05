# File formats met when patching FIFA on PS4

## BIG4 archives (`*.big`, index in `*.bh`)

Big-endian header: magic `BIG4`, u32 size (LE), u32 entry count, u32 header size; then per
entry u32 offset, u32 size, NUL-terminated name. `scripts/big4.py` lists and extracts.
Loose files under `/download0/<name>` override entries of the same name.

## Compression containers inside PS4 archives

- `chunkzip`: 48-byte header then a raw deflate stream (zlib wbits -15).
- `chunlzma`: header fields at 12/16/20 = uncompressed size, chunk size (0x80000), chunk
  count; LZMA1 chunks start at offset 48 with a 5-byte props header each, dictionary = chunk
  size. Kit textures are stored this way, 2.6 MB raw to 130 KB.

The engine accepts loose files either raw or wrapped; PC patch files are raw.

## RX3 asset files

`RX3l` magic, u32 version (4), u32 file size, u32 section count, then 16-byte section
entries (id, offset, size, 0). Section 0x6bd085dc is the texture header (per texture:
dimensions, format, mip count); 0x7a0b60da sections hold texel data (BC1/BC3/BC5 blocks).
PS4 and PC files for the same asset have identical section tables and headers for kits, boots,
balls, heads and adboards, which is why those work unchanged. Exception found 2026-11-04:
`hair_*` / `hairlod_*` meshes. Section 0xc28193f0 holds the vertex format string; PC hair is
`p0:00:00:0001:3f32 n0:0C ...` (3 x float32 positions, stride 40) while every stock PS4 hair is
`p0:00:00:0001:4f16 n0:08 ...` (4 x float16, w = 1.0, stride 36). The PS4 build renders PC hair
correctly in the main draw but another hair path assumes the console layout, so the mesh
explodes into stadium-sized brown streaks in replays/close-ups. Convert with
`~/FIFA16Mods/tools/hair_ps4.py` (fifamod runs it automatically on install). Vertex section
0x00587aa1 = {u32 size, count, stride, 1} + vertices, padded to 16; index section 0x005878f4 =
{u32 size, index count, 2, 0} + u16 indices.

## Database

`data/db/fifa_ng_db.db` with `fifa_ng_db-meta.xml`; signature `DB\0\x08` then platform
byte (0 = PC layout, which the PS4 build also uses), tables with bit-packed fields. The
decompiled FifaLibrary (`DbFile.cs`, `Table.cs`, `Record.cs`) documents the layout if a
database edit is ever needed; for head problems the Lua override is simpler.

## DDS UI images

Standard DDS (`DDS |` header, DXT1/DXT5). Loose `.dds` under `data/ui/imgAssets` are used
directly.
