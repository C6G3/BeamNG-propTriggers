# BeamNG.drive - propTriggers

`propTriggers` is a custom Lua extension for BeamNG.drive that vastly improves vehicle interiors by allowing modders to bind interactive click triggers directly to animated vehicle props.

Traditionally, BeamNG triggers (`vehicleTriggers`) are bound to static JBeam nodes. If you have an animated prop (like an indicator stalk, gear shifter, or switch), a node-based trigger will stay behind when the prop moves. `propTriggers` solves this by attaching triggers directly to the live 3D mesh of the prop, perfectly following its animation without requiring any complex animation curves.

---

## Features

- **Live Prop Inheritance:** Triggers extract the real-time world transform (position & rotation) of any `targetProp` and follow it seamlessly.
- **Multiple Target Props (Fallback / Swap Support):** `targetProp` accepts a list of candidate prop names (JSON array or comma-separated string). `propTriggers` recursively iterates through candidates to bind to whichever prop is currently installed on the vehicle (e.g. interchangeable steering wheels). If the player swaps parts in the Vehicle Config menu mid-game, triggers dynamically re-attach on the fly!
- **Mesh Triggers:** Adds a brand new `mesh` trigger type. You can use a `.obj` file to define the exact 3D shape of your clickable area instead of relying on basic boxes or spheres.
- **Extended Mouse & Wheel Controls:**
  - **Left Click:** Triggers `action0` / `leftClick` / `mouseLeft`
  - **Right Click:** Triggers `action1` / `rightClick` / `mouseRight`
  - **Middle Click:** Triggers `action2` / `middleClick` / `mouseMiddle`
  - **Wheel Up & Down:** Triggers `wheelUp` / `wheelDown` (instant scroll events for knobs, selectors, and volume controls)
- **BeamNG v0.39+ Crosshair & Icon Support:**
  - 3D screen-space bubble stream (`vehicleTriggerCrosshairTarget`) with accurate screen bounds projection and label placement.
  - Automatic icon resolution for infotainment, audio, vehicle lighting, cruise control, differentials, and doors.
  - Native `ui_bindingsLegend` tile support rendering matching icons and device badges.
- **Dynamic Event Links:** Features a `propTriggerEventLinks` system that works identically to `triggerEventLinks2`.
- **Transform Offsets:** Easily offset the clickable area relative to the prop using `baseTranslation` and `baseRotation`.

---

## Installation

Copy `propTriggers.lua` into your mod's folder structure at the following path:
```
lua/ge/extensions/propTriggers.lua
```

The game automatically loads the extension when the vehicle spawns.

---

## JBeam Usage

Configure prop triggers in your vehicle's `.jbeam` file, similarly to standard triggers.

### 1. Multiple Target Props Example (Selectable Steering Wheels)

Pass an array of prop meshes in `targetProp`. The trigger automatically binds to whichever steering wheel the player selects in the vehicle configuration:

```json
"propTriggers":[
    ["id", "targetProp", "type", "size", "meshName", "baseTranslation", "baseRotation", "action"],
    
    // Binds to "g81800dd_steering_w", "g81800dd_steering_w_v8", or "g81800dd_steering_w_wood" depending on what is installed:
    ["cruisecontrol_+", ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0155, "y":0.0130, "z":0.0098}, "", {"x":-0.0841, "y":-0.0193, "z":-0.1219}, {"x":-173.980, "y":0.575, "z":-89.653}, ""],
    ["info_volUp", ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0083, "y":0.0130, "z":0.0098}, "", {"x":0.0096, "y":-0.1555, "z":-0.0719}, {"x":179.438, "y":-9.823, "z":-89.766}, ""],
],
```

*(Comma-separated strings like `"steering_w_1, steering_w_2"` are also supported).*

---

### 2. Mesh Trigger Example

Use a custom `.obj` mesh for the clickable collision area:

```json
"propTriggers":[
    ["id", "targetProp", "type", "size", "meshName", "baseTranslation", "baseRotation", "action"],
    
    // "cruisecontrol_+" is the trigger ID.
    // "steering_wheel" is the prop mesh name.
    // {"x":90, "y":0, "z":45} applies a local rotation offset.
    // {"x":0.1, "y":0, "z":0} applies a local translation offset along rotated axes.
    ["cruisecontrol_+", "steering_wheel", "mesh", {"x":1, "y":1, "z":1}, "vehicles/your_vehicle/mesh/trigger_box.obj", {"x":0.1, "y":0, "z":0}, {"x":90, "y":0, "z":45}, ""],
],
```

---

### 3. Standard Box Trigger Example (Node-Based)

Traditional node-based triggers (`idRef`, `idX`, `idY`) remain fully supported:

```json
"propTriggers":[
    ["id", "idRef:", "idX:", "idY:", "type", "size", "baseRotation", "rotation", "translation", "baseTranslation", "action"],
    ["toggle_switch", "sw1","sw3","sw2", "box", {"x":0.015, "y":0.014, "z":0.009}, {"x":284, "y":358, "z":0.6}, {"x":0, "y":0, "z":0}, {"x":0, "y":0, "z":0}, {"x":0.20, "y":0.16, "z":0.07}, ""],
],
```

---

### 4. Binding Input Actions (Mouse Clicks & Scroll Wheels)

Map triggers to vehicle actions via `propTriggerEventLinks`. Supports `action0` (LMB), `action1` (RMB), `action2` (MMB), `wheelUp`, and `wheelDown`:

```json
"propTriggerEventLinks":[
    ["triggerId", "triggerInput", "inputAction"],
    
    // Left click on steering wheel button increases cruise speed
    ["cruisecontrol_+", "action0", "cruisecontrol_+"],

    // Mouse Middle Click toggles mute
    ["info_volume_knob", "action2", "c6g3_infotainment:info_mute"],

    // Mouse Wheel Up / Down increments / decrements volume
    ["info_volume_knob", "wheelUp", "c6g3_infotainment:info_volUp"],
    ["info_volume_knob", "wheelDown", "c6g3_infotainment:info_voDown"],
],
```

---

## BeamNG v0.39+ Compatibility

- **Screen-Space Crosshair Target Bubble:** Projects 3D trigger bounding boxes into screen space and emits the `vehicleTriggerCrosshairTarget` stream for seamless 0.39+ crosshair bubble placement.
- **Automatic Icon Resolution:** Triggers automatically resolve suitable icons (`soundLoud`, `soundQuiet`, `soundOff`, `nextTrack`, `prevTrack`, `road`, `hazardLights`, `doorHandle`, `cruiseEnable`, `differentialMiddleLocked`, `mouseLMB`, `mouseRMB`, `mouseMMB`, `mouseWheel`) or use explicit `icon` fields specified on actions or triggers.
- **Keybindings Legend:** Integrates with `ui_bindingsLegend` to display action labels, icons, and keyboard/mouse shortcut badges.
