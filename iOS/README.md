# Drift for iPhone

Pip lives in your Dynamic Island. Long-press the island to pet Pip, give it a snack or put it to bed. The app itself has falling snow, leaves, petals and stars that follow the tilt of your phone; shake it for a snow-globe swirl.

Open `Drift.xcodeproj` in Xcode, choose your team under Signing & Capabilities for both targets (Drift and PipIsland), pick your iPhone and press Run. On the iPhone, turn on Developer Mode (Settings → Privacy & Security) and trust your developer profile (Settings → General → VPN & Device Management).

The Pip images in `Shared/Pip.xcassets` are built from the 3D renders with `python3 Tools/ios_assets.py Resources/Characters iOS/Shared/Pip.xcassets iOS/App/Assets.xcassets`.

## 3D penguin

Pick the penguin chick and Pip appears as a real 3D model (`App/Pip3D.usdz`, made in Meshy), drawn with SceneKit in `App/Pip3DView.swift`. It breathes and waddles, leans as you tilt the phone, hops when you tap it, spins when you shake, and you can spin it with a finger. The 3D/2D chip switches back to the drawn penguin. The Mac app uses the same model as a pre-rendered image (`Tools/render3d.swift`).

To add another Meshy model: slim it with `Tools/slim_model.py`, package it with `Tools/make_usd.py` and `usdzip`, then drop the `.usdz` into `App/`.
