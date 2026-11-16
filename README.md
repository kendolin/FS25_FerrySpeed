# FS25 Ferry Speed

A Farming Simulator 25 mod that makes the map ferries run faster (or slower).

## Install

Zip the contents of this folder (so `modDesc.xml` sits at the top level of the zip), name it `FS25_FerrySpeed.zip`, and put it in:

```
Documents/My Games/FarmingSimulator2025/mods
```

Then enable the mod on your savegame.

## Setting the speed

The default is 3x. Allowed range is 0.1x to 10x.

- **In game:** pause menu > Settings > Game Settings > Ferry Speed (at the bottom of the page)
- **Settings file:** `modSettings/FS25_FerrySpeed.xml` in the FS25 user folder
- **Console:** `ferrySpeed 5` (`ferrySpeed` alone shows the current value)

In multiplayer the host's value is the one that counts.

## How it works

The game's ferry code isn't publicly documented, so the mod doesn't change a speed value directly. It scales the frame time the ferry receives, so the whole crossing (travel, ramps, waiting) runs faster.

`ferrySpeedInfo` in the console prints what the mod has hooked, which helps when something isn't working.

## Status

Not yet verified in game. Very high multipliers may make vehicles slide on deck.
