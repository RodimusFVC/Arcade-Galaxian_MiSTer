<h1 align="center">Galaxian Hardware FPGA Core</h1>

<p align="center">
  Arcade hardware implementation for MiSTer FPGA
</p>

---

## Overview

FPGA implementation of the **Namco Galaxian hardware (1979)** and the boards derived from it, in a single core.

The goal is every set in MAME's Galaxian family of drivers. The Galaxian and Moon Cresta boards and the AY-sound boards are working now; the Konami boards (Scramble, Frogger, Super Cobra and relatives) and the remaining oddball boards are in development.

This core targets MiSTer FPGA and aims for accurate gameplay behavior, video timing, and sound reproduction.

---

## Supported Games

| Hardware | Games |
|----------|-------|
| Galaxian board | Galaxian, Azurian Attack, Black Hole, Catacomb, Orbitron, War of the Bugs, Defend the Terra Attack on the Red UFO, Lucky Today, Triple Draw Poker, and clones |
| Moon Cresta board | Moon Cresta, Moon Quasar, Moon Alien Part 2, Kong, Sky Base, and clones |
| Galaxian + AY sound | Jump Bug, Bongo, Levers, Check Man, Dingo |

Clones and regional versions are in `releases/_alternatives/`. More boards will be added as they are completed.

---

## Controls

Default MiSTer gamepad mapping (button names are set per game by its `.mra`):

| Input | Action |
|-------|--------|
| D-Pad / Joystick | Move |
| A | Button 1 (Fire) |
| Y | Button 2 |
| B | Button 3 |
| X | Button 4 |
| Select | Insert Coin |
| Start | 1 Player Start |
| Right Shoulder | 2 Player Start |
| Left Shoulder | Pause |

Button 5 and Button 6 are available but unassigned — map them in the OSD's *Define Buttons* if a game needs them.

---

## Features

- One core for every supported board, selected by the `.mra`
- Arcade-accurate CPU timing
- Galaxian discrete sound, AY-3-8910 and sound-CPU boards
- Star field and bullet hardware
- High score saving support (98 sets)
- DIP switches for every set, taken from MAME
- CRT and HDMI flip, pause, and scandoubler options
- MiSTer-compatible .mra provided
- Verified ROM definitions with checksums

---

## ROM Requirements

ROM files are **not included**.

To use this arcade core, you must provide legally obtained ROM files.

To simplify setup:

- `.mra` files are provided in the **Releases** section.
- The `.mra` specifies all required ROM files along with checksums.
- The ROM `.zip` filename corresponds to the naming convention used by the MAME project.

For setup instructions and environment configuration, refer to:

MiSTer Arcade ROM guide:  
https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms

---

## Installation

1. Copy the core `.rbf` file to your MiSTer `/_Arcade/cores` folder.
2. Copy the `.mra` files (including the `_alternatives` folder) to your MiSTer `/_Arcade` folder.
3. Place the appropriate ROM `.zip` files in your `/games/mame` directory.
4. Launch the core from the MiSTer Arcade menu.

---

## Legal Notice

This project contains **no copyrighted game data**.

Users are responsible for obtaining and using ROM files in accordance with applicable laws.

Do not request ROM files in issues or discussions.

---

## Credits

FPGA core development: RodimusFVC  
Board model derived from "FPGA GALAXIAN" by Katsumi Degawa and the MiSTer Galaxian port by Alexey Melnikov (Sorgelig)  
Memory maps and hardware notes per the MAME project (Nicola Salmoria, Aaron Giles, Couriersud and contributors)  
T80 CPU core: Daniel Wallner, with updates by Sorgelig  
JT49 / JT89 sound cores: Jose Tejada (jotego)  
Hiscore, pause and NVRAM modules: Jim Gregory and Alan Steremberg  
Audio filters: Gregory Hogan (Soltan_G42)  
Original arcade games © Namco, Nichibutsu and their respective owners

---
