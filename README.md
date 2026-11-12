# Drift

A small menu-bar app for macOS. Snow, sakura petals, leaves and more fall across your desktop and settle on the tops of your real windows, the Dock and the bottom of the screen. Pip, a small fluffy creature, lives on your windows. Clicks pass straight through, so you keep working as usual.

## Build and run

You need the Xcode Command Line Tools (run `xcode-select --install` once if you don't have them).

```bash
cd Drift
bash build.sh            # builds build/Drift.app and starts it
bash build.sh install    # same, and copies it to ~/Applications
bash build.sh share      # makes Drift-share.zip (Apple Silicon + Intel) to send to friends
```

**Sharing:** send `Drift-share.zip`. Your friends unzip it, drag Drift to Applications, and the first time right-click Drift → **Open** → **Open** (or System Settings → Privacy & Security → **Open Anyway**). To skip that warning you need an Apple Developer account to sign and notarize the app.

Drift has no Dock icon. It lives in the menu bar, and its icon matches the current season.

## Meet Pip

Pip is a 3D plush character, sculpted, furred and lit in Blender and rendered as layers that the app animates: blinking, changing expression, tilting its head, waving, waddling, and wearing 3D seasonal outfits. Choose a **bunny** (default), **penguin chick**, **lamb**, **otter pup**, **seal pup** or **hedgehog** in the Pip menu.


Pip is a round little cotton-cloud of fur with big sparkly eyes, a wagging puff of a tail and a curl of hair on top. It lives on top of your windows and dresses for the season: a knitted hat and a chunky knitted scarf in snow, an umbrella in the rain, a flower crown in summer, a leaf hat in autumn, a lantern under the stars.

- Wanders along window tops, leaving footprints in the snow, and hops from window to window.
- Rides along when you move a window. Drag it fast and Pip goes flying ("wheee!").
- Comes over to the window you switch to.
- Catches falling flakes, and builds its own little snowmen.
- **Pet it:** rest the cursor on Pip. Hearts appear.
- **Startle it:** sweep the cursor past quickly and it jumps away.
- Falls asleep when you leave the Mac alone, and waves when you come back.
- Menu → Pip → *Call Pip to this window* (⌘J while the menu is open).

## Effects

| Effect | How |
|---|---|
| Depth | Blurred, slower flakes in the background and sharp ones in front. Only the front ones settle. |
| Real crystals | Snow mixes soft clumps with six-armed crystals. Leaves, petals, blossoms and dandelion seeds are drawn with veins and gradients. |
| Shaded drifts | Bright crests, cool shadows, a soft contact shadow and glints that sparkle in the light. |
| Icicles | Grow under deep drifts on windows and drip now and then. They snap off when you clear the drift. |
| Snow globe | Shake the mouse quickly from side to side. Everything swirls up and Pip gets dizzy. |
| Frost | Creeps in from the screen corners while you're away (snow season). Melts when you return. |
| Raindrops on the glass | In rain, drops land on the screen, wait, then slide down and merge. |
| Shooting stars | Streak across the sky in Stardust. |
| Natural wind | Gentle gusts on top of your wind setting. |
| Brush, roll, shake | Sweep drifts with the cursor; hold ⌥ Option to roll snowballs and stack a snowman; drag a window fast to shake its drift off. |

Every effect can be switched off under **Effects** in the menu bar icon.

## Why it's light

- Falling particles are Core Animation layers composited by the GPU. Nothing is redrawn on the CPU per frame except Pip's small layer.
- Each drift is a small layer that's redrawn only when it changes. Sprites are rendered once per season.
- Window positions are read 30 times a second with one system call. Drift never reads window contents and needs no Screen Recording permission.
- In Low Power Mode or when the Mac runs hot, Drift drops half (or more) of its particles.

## Files

- `Sources/Sim.swift`: weather simulation (seasons, depth, drifts, icicles, raindrops, meteors, snow globe).
- `Sources/Pip.swift`: Pip's behaviour.
- `Sources/Art.swift`: everything drawn (sprites, drifts, icicles, frost, Pip and its outfits).
- `Sources/main.swift`: overlay windows, input, window tracking, menu bar.

## The 3D characters

The characters live in `Resources/Characters/<animal>/`: aligned PNG layers (body, feet, arms, ears, four head expressions, outfits) plus a `manifest.json` with the pivot points. They were made with `Tools/characters.py`, which builds each animal in Blender (sculpted shapes, plush fur, glossy eyes, studio lighting) and renders the layers. To change or add a character:

```bash
python3 -m venv bvenv && bvenv/bin/pip install bpy        # Blender as a Python module
bvenv/bin/python Tools/characters.py Resources/Characters bunny penguin lamb otter seal hedgehog
bash build.sh install
```

You can also drop in your own artwork: any folder of layers with a matching `manifest.json` works. If a character's folder is missing, Drift falls back to drawing that animal in code.
