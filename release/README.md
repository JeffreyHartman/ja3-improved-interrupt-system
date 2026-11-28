# Release

The texts and images for the Steam Workshop and Nexus Mods pages.

| File | Use |
|---|---|
| `workshop.txt` | The Workshop description. `tools/set-description.py` writes it into the `description` field of `mod/metadata.lua`. The Mod Editor uploads that field, and the in-game Mod Manager shows it. Thus it is plain text, with no BBCode. |
| `nexus.bbcode` | The Nexus description, with the install steps and the full settings list. |
| `images/preview.jpg` | The preview image, 1024x1024. `tools/images.py preview [SCREENSHOT]` makes it. |
| `images/shot-N.jpg` | The screenshots. `tools/images.py shots FILE...` makes them. |
| `dist/` | The Nexus zip. `tools/package.sh` makes it. Git ignores this folder. |

Do not edit the description on the Steam page. Each upload replaces it with the text in `metadata.lua`. Edit `workshop.txt`, and then run `tools/set-description.py`.

## Screenshots to take

Take each screenshot with the game UI visible. On Steam, press F12. Steam saves the screenshots in its screenshot folder for app 1084160.

1. A merc interrupt: the INTERRUPT! banner, the merc that interrupted, and the enemy that stopped.
2. An enemy interrupt: the Enemy Interrupt banner.
3. An IOS interrupt: a merc on Overwatch that aims at an enemy, with the to-hit preview.
4. Mod Options: the options of the mod, with their group colors.

Then run `tools/images.py shots <the 4 files>`, and `tools/images.py preview <screenshot 1>` for a preview with a game background.

## Steam Workshop upload

1. Run `tools/set-description.py`, and then run `tools/deploy.sh`.
2. Start the game, open the Mod Editor, and open the mod.
3. Set "Preview image" to `release/images/preview.jpg`. Set "Screenshot" 1 to 4 to the `shot-N.jpg` files.
4. Fill in "Last changes" with the changes of the version from `CHANGELOG.md`. The upload stops if this field is empty.
5. Upload the mod. Before you make it public, subscribe to it, and start the game once without the local copy.
6. Copy `metadata.lua` from the game's Mods folder to `mod/metadata.lua`, and commit it. The editor writes the `steam_id`, the image paths and "Last changes" into that file. `tools/deploy.sh` deletes the `steam_id`. Without the ID, the next upload makes a new Workshop item.

## Nexus Mods upload

- **Name:** Improved Interrupt System (JA2 1.13 Interrupts)
- **Category:** Gameplay
- **Summary:** JA2 1.13 interrupts for JA3. Your mercs can interrupt the enemy turn, and enemies can interrupt yours. Optional: take your Overwatch shots yourself. Works with vanilla and GBO 4.
- **Description:** paste `nexus.bbcode`.
- **Main file:** run `tools/package.sh`, and upload `release/dist/ImprovedInterruptSystem-<version>.zip`.
- **Images:** the preview and the screenshots.
