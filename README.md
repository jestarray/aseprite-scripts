# aseprite-scripts

## jest_import_existing_tags (also imports frame durations)
Video(SCRIPT RE-NAMED TO jest_import_existing_tags): (https://6-28.mastodon.xyz/media_attachments/files/014/003/934/original/be68e70a2fc7c855.mp4)

Instructions
1. Export your animation tags and duration info with:
```
./aseprite.exe --data="anim_info.json" --format="json-array" --list-tags [file].ase -b
```
2. In aseprite menu go to: File > Scripts > jest_import_existing_tags . Select the animation info json file and done.

## jest_merge_all_tabs.lua
Video: https://6-28.mastodon.xyz/media_attachments/files/105/473/764/637/461/769/original/d7d438e81f1d8e96.mp4

Instructions:
1. Import all the individual frames
2. In aseprite menu go to: File > Scripts > jest_merge_all_tabs , and it will merge everything into 1 sprite

## jest_import_packed_atlas
Video: https://youtu.be/XVnEURlY_Do

NOTE: This does not work with rotated atlases

1. Make sure the current tab selected is the sprite packed in a texture atlas
2. Select the corresponding json file associated with it

This script can also be ran via cli:
```
// png and json file don't have to be aboslute paths but script file most likely need absolute path. If it doesn't work just use absolute paths

aseprite.exe <C:\SPRITE.png> --script-param json="C:\SPRITE.json" --script "C:\jest_import_packed_atlas.lua" --batch
```

note: if you see all the colors wrong, you did not have the texture atlas sprite active.
