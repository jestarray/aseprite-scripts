# aseprite-scripts

Scripts:


## Import Existing Tags (also imports frame durations)
Video: (https://6-28.mastodon.xyz/media_attachments/files/014/003/934/original/be68e70a2fc7c855.mp4)

Instructions
1. Export your animation tags and duration info with:
```
./aseprite.exe --data="anim_info.json" --format="json-array" --list-tags [file].ase -b
```
2. In aseprite menu go to: File > Scripts > Import_Existing_tags . Select the animation info json file and done.

