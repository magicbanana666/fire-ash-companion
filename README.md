# Fire Ash Companion

A second-screen companion for **Pokémon Fire Ash** (Pokémon Essentials v19.1) running in **JoiPlay** on Android dual-screen handhelds such as the **AYN Thor** — plus a 16:9 widescreen mode for the game itself.

The game runs on the top screen; the companion app lives on the bottom screen and updates live while you play.

> Fan project. Not affiliated with Nintendo, Game Freak, The Pokémon Company or the Fire Ash team.
> **No game files are included** — you need your own copy of Fire Ash.

## Features

**Companion app (bottom screen)**

| Tab | What it shows |
|---|---|
| ⚔ Battle | Appears automatically during battles: opponent types, weaknesses/resistances/immunities, and how effective each of your moves is (2×, 4×, ½×, no effect). |
| Route | Wild Pokémon on your current route per method (grass, surfing, rods, …) with levels and encounter rates, the table that is active *now* (day/night), and caught/seen markers. Inside buildings it shows the surrounding area. Unseen Pokémon are shown as silhouettes (spoiler toggle in settings). |
| Map | The region map with your position. Tap any square to see which Pokémon live there. |
| Team | Party with HP, status and held items. Tap a Pokémon for moves (type, power, accuracy, PP), ability, nature, stats and EXP. |
| Bag | All items per pocket. |
| Badges | Your badge case plus 8 badge slots per region, and the gym leaders / Elite Four from the walkthrough with their teams. |
| Guide | The walkthrough shipped with the game (`Helpful Notes`), jumps to your current location. Trainer teams, wild Pokémon and shops are rendered as cards with icons. Search, chapter index, other notes (routes, locations, evolutions, …). |
| Cheats | Money, heal party, raise party level, give any item, add any Pokémon, force the next wild Pokémon (and shiny), repel, walk through walls, game speed (1×–5×). |
| ✎ PokeEditor | From the Team tab: species, nickname, level, nature, ability (incl. hidden), held item, gender, shiny, 4 moves (learnable or any), IVs, EVs and happiness. |

The header shows the location, badges, money, day/night, Pokédex progress and the measured FPS (+ fast-forward speed).

**In-game plugins**

* `DualScreenExport.rb` – writes the game state to `DualScreen/*.json` inside the game folder.
* `DualScreenCheats.rb` – executes cheat / editor commands from the app (only while you walk on the overworld) and writes the data lists for the editor.
* `WideScreen.rb` – renders the overworld at 682×384 (16:9) instead of 512×384, so you *see more* instead of stretching. Menus switch to 4:3 behind a fade; battles stay exactly as designed in the centre with the sides filled by a blurred copy of the battle background. Disable it by creating an empty file `DualScreen/no_widescreen` in the game folder.

Everything is wrapped in error handling: a problem in a plugin is logged to `DualScreen/error.txt` / `widescreen_error.txt` and never stops the game.

## How it works

```
Fire Ash (JoiPlay, top screen)                 Companion app (bottom screen)
  plugins in Data/Scripts.rxdata                 WebView UI (app/assets/www)
     │ writes DualScreen/state.json  ───────────▶  polls the files ~2×/s
     │ writes static.json / editor.json             (served via a local
     │ reads   DualScreen/cmd.json   ◀───────────   https://app.local/ handler)
```

No network, no root. The app needs "All files access" to read the game folder.

## Installation

### 1. Patch the game scripts

Requirements: Python 3 with `pip install rubymarshal`.

```bash
# back up first!
cp "Fire Ash/Data/Scripts.rxdata" "Fire Ash/Data/Scripts_backup.rxdata"

python tools/inject_script.py "Fire Ash/Data/Scripts.rxdata" "Fire Ash/Data/Scripts.rxdata" \
    DualScreenExport game/DualScreenExport.rb \
    DualScreenCheats game/DualScreenCheats.rb \
    WideScreen       game/WideScreen.rb
```

The tool inserts the three scripts right before `Main` (re-running it replaces them) and verifies the result. To undo, restore your backup.

### 2. Install the app

Download `FireAshCompanion.apk` from the [Releases](../../releases) page (or build it, see below) and install it. On first start, allow **All files access**.

Default game folder: `/storage/emulated/0/JoiPlay/Pokemon Fire Ash 3.7` — if yours differs, pick it in the ⚙ tab.

On a dual-screen device the app moves itself to the second screen.

### 3. (Optional) Auto-start with the game

The app contains an accessibility service that only watches for the JoiPlay RPG Maker runtime coming to the foreground (it does not read screen content). When Fire Ash boots, the companion opens on the bottom screen automatically.

Enable it under *Settings → Accessibility → Fire Ash Companion auto-start*, or via adb (keep any services you already have in that list):

```bash
adb shell settings put secure enabled_accessibility_services be.vanhulle.fireashcompanion/.GameWatcherService
```

## Building the APK

No Gradle needed — JDK 17 and an Android SDK with `build-tools;34.0.0` and `platforms;android-34`:

```powershell
./app/build.ps1 -Sdk C:\path\to\android-sdk -Jdk C:\path\to\jdk-17
```

A local signing key (`app/companion.keystore`, git-ignored) is generated on the first build.

## Development

* `tools/extract_scripts.py` – dump `Scripts.rxdata` / `PluginScripts.rxdata` to `.rb` files for reading.
* `tools/test_plugins.rb` – smoke test for the plugins outside the game (JSON writer/parser, hooks). Runs with JRuby or MRI.
* Tested with Fire Ash 3.7, JoiPlay 1.22 (RPG Maker plugin), AYN Thor (Android 13).

## Notes

* Cheats and editor changes are applied when you are walking on the overworld (not in menus or battles). Save in-game to keep them.
* Other Essentials v19.1 games may partially work (Route/Map/Team/Bag/Battle), but the guide, badge layout and widescreen tweaks were made for Fire Ash.

## License

[MIT](LICENSE)
