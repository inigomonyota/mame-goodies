Multi-mode screensaver plugin

This plugin adds an automatic, configurable screensaver to MAME. After a
period of inactivity, gameplay is paused and a visual screensaver is
displayed until input is detected.

Multiple classic screensaver styles are included, and each can be
individually configured from MAME's internal menu.

------------------------------------------------------------------------

## Features

• Automatic activation after configurable idle timeout\
• Gameplay is safely paused while the screensaver runs\
• Instantly dismissed on any input\
• Multiple visual modes:

-   Bounce (DVD-style bouncing MAME logo)
-   Starfield
-   Mystify
-   Matrix-style falling characters
-   Fireworks particle effects
-   Plasma effect
-   Random mode (chooses a mode each activation)

• Per-mode configuration menus\
• Test mode for previewing effects\
• Settings are automatically saved and restored

------------------------------------------------------------------------

## Installation

1.  Copy the plugin folder into:

    ```mame/plugins/```

so the structure becomes:

    mame/
     └── plugins/
         └── screensaver/
             ├── init.lua
             ├── plugin.json
             ├── screensaver_menu.lua
             ├── screensaver_persist.lua
             └── mame_logo.png

2.  Enable plugins in MAME if not already enabled:

    ```mame -plugins```

or set in `mame.ini`:

    plugins 1

3.  Enable the plugin from:

    ```MAME UI → Plugin Options → Screensaver```

------------------------------------------------------------------------

## Usage

When enabled, the screensaver activates after the configured idle
timeout. Any keyboard, controller, or joystick input immediately
restores gameplay.

The game is automatically paused while the screensaver is active and
resumes when it exits.

------------------------------------------------------------------------

## Configuration

Open the configuration menu inside MAME:

    Tab → Plugin Options → Screensaver

From here you can:

• Enable or disable the screensaver\
• Set idle timeout\
• Select screensaver mode\
• Adjust per-mode parameters\
• Run test previews for each mode\
• Enable debug logging

All settings are stored automatically between sessions.

------------------------------------------------------------------------

## Modes Overview

### Bounce

A classic DVD-style bouncing MAME logo that changes color on impact.

Adjustable: - Logo scale - Horizontal speed - Vertical speed

### Starfield

A flying starfield effect simulating forward movement through space.

Adjustable: - Star count - Travel speed

### Mystify

A recreation of the classic Windows Mystify screensaver with bouncing
polygons and trails.

Adjustable: - Number of polygons - Points per polygon - Movement speed

### Matrix

Matrix-style cascading characters.

Adjustable: - Number of columns - Scroll speed

### Fireworks

Fireworks rockets with particle explosions.

Adjustable: - Launch rate

### Plasma

Animated plasma effect with selectable palettes.

Adjustable: - Animation speed - Color palette (rainbow, fire, ocean,
matrix)

### Random

Randomly selects a mode each time the screensaver activates.

------------------------------------------------------------------------

## Notes

• The screensaver monitors both emulated and host inputs.\
• Works with keyboard and controller input.\
• Designed to be lightweight and compatible with standard MAME builds.

------------------------------------------------------------------------

## License

GPL-3.0+

------------------------------------------------------------------------

## Author

Inigo Montoya
