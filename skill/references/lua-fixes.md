# Lua fixes for PC patch scripts on the PS4 engine

The asset scripts in `data/fifarna/lua/assets/*.lua` build semicolon-separated lists of
candidate file paths; the engine loads the first one that exists. A PC patch (FIP) replaces
these scripts with much larger versions that reference assets the patch's Windows installer
generates or that come in separate packs. When every candidate is missing the engine draws
nothing (headless player) or a placeholder (cyan crowd). Both fixes below append or override
candidates; they never remove the patch's own choices.

Keep the original file as `<file>.orig-before-ps4-fix` next to the edited one, and re-apply
after updates, which overwrite the scripts.

## Headless players: force generic heads

`player.lua` decides real-vs-generic face with `getPlayerFace(id, headtype)`: class 0 means a
real face (`head_<id>_0.rx3`), 1 means generic. `playerFace` is an override table that other
scripts (`rm_common.lua`) reset, so put the override inside the function:

```lua
-- PS4/shadPS4 local fix: flagged for real faces in the database, no head files in any pack.
ps4ForcedGenericFace = { [268889]=1, [272600]=1 }   -- ids from fip_missing.py

function getPlayerFace(id,headtype)

if (ps4ForcedGenericFace[id] ~= nil) then
return 1
end

if (playerFace[id] ~= nil) then
return playerFace[id]
end

return headtype
end
```

Prefer installing the matching face pack; use the override for the remainder.

## Cyan crowd: fall back to real kit textures

FIP's `crowd.lua` has `GetRMCrowdShirt(idx, ishome, character)` returning only
`crowdkit_<team>_*.rx3` candidates, files its installer generates on PC. The stock script
uses the team's kit textures. Append them before `return kit`:

```lua
	-- PS4/shadPS4 local fix: no crowdkit_* files shipped, fall back like the stock crowd.lua.
	local kittype = 0
	if (ishome == 2) then
	kittype = 1
	end
	kit = kit.."data/sceneassets/kit/kit_"..team.."_"..kittype.."_0.rx3;"
	kit = kit.."data/sceneassets/kit/kit_"..team.."_0_0.rx3;"
```

## Reading the stock scripts for comparison

The PS4 originals live inside `data_startup.big` wrapped in `chunkzip`;
`scripts/big4.py extract data_startup.big data/fifarna/lua/assets/crowd.lua out.lua` decodes
them. Diffing stock against patch scripts shows what the patch expects that the platform
lacks.

## Custom hair exploding across the pitch (hair physics)

Symptom: in replays/close-ups a facepack player's hair becomes giant brown streaked polygons
covering the stadium (looks like untextured stadium geometry at first). Cause: facepack hair
ships empty `simplecloth/simhair_<id>_*.rx3` placeholders that switch hair physics off; the
PS4 build crashes on them so they were removed, and `player.lua`'s `haircloth` candidate list
then falls back to a *generic* hairstyle's physics mesh (`simhair_<generichair>_<class>_0`),
which drives the custom hair mesh with the wrong topology. Fix (fifamod mod "Hair physics
fix (PS4)", 2026-11-04): in `PlayerAsset...` replace the second candidate with the
non-existent `data/sceneassets/simplecloth/dummy_-1.rx3` (EA's own "no cloth" convention):

    gr:AddAsset(player, lod, "haircloth", "data/sceneassets/simplecloth/simhair_${db.player[?].hair}_${db.player[?].faceProxyHeadClass}_0.rx3;data/sceneassets/simplecloth/dummy_-1.rx3")

Stock players keep physics (their own simhair exists). Verify with a close-up replay.
