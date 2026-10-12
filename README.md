# BeamNG.drive - propTriggers

`propTriggers` is a custom Lua extension for BeamNG.drive that vastly improves vehicle interiors by allowing modders to bind interactive click triggers directly to animated vehicle props.

Traditionally, BeamNG triggers (`vehicleTriggers`) are bound to static JBeam nodes. If you have an animated prop (such as an indicator stalk, gear shifter, steering wheel, or switch), a node-based trigger stays behind or drifts when the prop moves. `propTriggers` solves this by attaching triggers directly to the live 3D transform of the prop, perfectly following its position and rotation in real time without requiring complex animation curves.

---

## Features

- **Live Prop Inheritance:** Triggers extract the real-time world transform (position & rotation) of any `targetProp` and follow it seamlessly.
- **Multiple Target Props (Variant / Swap Support):** `targetProp` (or `targetProps`) accepts a list of candidate prop names (JSON array, nested table, or comma/semicolon/pipe-separated string). `propTriggers` recursively iterates through candidates to bind to whichever prop is currently installed and active on the vehicle (e.g. interchangeable steering wheel variants).
- **Dynamic In-Game Reconfiguration:** When the player changes vehicle parts in the Vehicle Config menu mid-game, `onVehicleResetted` automatically re-evaluates candidate lists and re-binds triggers to newly equipped parts on the fly.
- **Mesh Triggers:** Adds a dedicated `mesh` trigger type. You can supply a `.obj` file to define the exact 3D shape of your clickable collision area instead of relying solely on basic boxes or spheres.
- **Comprehensive Mouse & Wheel Controls:** Supports Left Click (`action0`), Right Click (`action1`), Middle Click (`action2`), and Mouse Wheel scroll (`wheelUp` / `wheelDown` / `wheel`), ideal for interactive rotary dials, volume knobs, fan speeds, switches, and buttons.
- **Native UI Integration:** Fully supports the vanilla BeamNG `ui_bindingsLegend` (< 0.39) and the 3D crosshair target bubble (>= 0.39). When hovering over a custom trigger, action titles and keyboard shortcuts appear identically to vanilla vehicle triggers.
- **Dynamic Event Links:** Features a `propTriggerEventLinks` system that works identically to `triggerEventLinks2`.
- **Transform Offsets:** Easily offset the clickable area relative to the prop using `baseTranslation` and `baseRotation`.

---

## Installation

Copy `propTriggers.lua` into your mod's folder structure at the following path:
```
lua/ge/extensions/propTriggers.lua
```

BeamNG automatically loads the extension when a vehicle spawns.

---

## JBeam Usage

Configure prop triggers in your vehicle's `.jbeam` file, similarly to standard triggers.

### 1. Multiple Target Props (Interchangeable Parts)

Pass an array or delimited string of candidate prop mesh names in `targetProp`. The trigger automatically binds to whichever part is installed:

```json
"propTriggers":[
    ["id", "targetProp", "type", "size", "meshName", "baseTranslation", "baseRotation", "action"],
    
    // Binds to "g81800dd_steering_w", "g81800dd_steering_w_v8", or "g81800dd_steering_w_wood" depending on what is equipped:
    ["cruisecontrol_+", ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0155, "y":0.0130, "z":0.0098}, "", {"x":-0.0841, "y":-0.0193, "z":-0.1219}, {"x":-173.980, "y":0.575, "z":-89.653}, ""],
    ["cruisecontrol_-", ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0112, "y":0.0130, "z":0.0098}, "", {"x":-0.1010, "y":-0.0183, "z":-0.1218}, {"x":-173.980, "y":0.575, "z":-90.273}, ""],
    ["info_volUp",      ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0083, "y":0.0130, "z":0.0098}, "", {"x":0.0096,  "y":-0.1555, "z":-0.0719}, {"x":179.438,  "y":-9.823, "z":-89.766}, ""],
    ["info_volDown",    ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0083, "y":0.0130, "z":0.0098}, "", {"x":-0.0112, "y":-0.1573, "z":-0.0752}, {"x":179.436,  "y":-10.270,"z":-89.766}, ""],
    ["info_prev",       ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0112, "y":0.0090, "z":0.0098}, "", {"x":-0.0055, "y":-0.1675, "z":-0.0805}, {"x":177.724,  "y":-7.925, "z":-90.645}, ""],
    ["info_next",       ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0112, "y":0.0090, "z":0.0098}, "", {"x":-0.0066, "y":-0.1414, "z":-0.0729}, {"x":177.765,  "y":-9.610, "z":-91.333}, ""],
    ["info_mute",       ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0112, "y":0.0130, "z":0.0098}, "", {"x":-0.0015, "y":-0.1217, "z":-0.0820}, {"x":175.386,  "y":-6.302, "z":-82.139}, ""],
    ["info_voiceNav",   ["g81800dd_steering_w", "g81800dd_steering_w_v8", "g81800dd_steering_w_wood"], "box", {"x":0.0112, "y":0.0130, "z":0.0098}, "", {"x":0.0199,  "y":-0.1225, "z":-0.0798}, {"x":-179.354, "y":-7.307, "z":-83.843}, ""]
],
```

*(Delimited string formats such as `"g81800dd_steering_w, g81800dd_steering_w_v8; g81800dd_steering_w_wood"` are also supported).*

---

### 2. Mesh Trigger Example (.obj Collision)

Use a custom `.obj` mesh for complex 3D collision surfaces:

```json
"propTriggers":[
    ["id", "targetProp", "type", "size", "meshName", "baseTranslation", "baseRotation", "action"],
    
    // "cruisecontrol_+" is the trigger ID.
    // "steering_wheel" is the prop name.
    // "vehicles/your_vehicle/mesh/trigger_box.obj" provides the collision geometry.
    ["cruisecontrol_+", "steering_wheel", "mesh", {"x":1, "y":1, "z":1}, "vehicles/your_vehicle/mesh/trigger_box.obj", {"x":0.1, "y":0, "z":0}, {"x":90, "y":0, "z":45}, ""]
],
```

---

### 3. Traditional Node-Based Trigger Example

Traditional node-based triggers (`idRef`, `idX`, `idY`) remain supported:

```json
"propTriggers":[
    ["id", "idRef:", "idX:", "idY:", "type", "size", "baseRotation", "rotation", "translation", "baseTranslation", "action"],
    ["toggle_switch", "sw1", "sw3", "sw2", "box", {"x":0.015, "y":0.014, "z":0.009}, {"x":284, "y":358, "z":0.6}, {"x":0, "y":0, "z":0}, {"x":0, "y":0, "z":0}, {"x":0.20, "y":0.16, "z":0.07}, ""]
],
```

---

### 4. Enabling Actions (`actionsEnabled`)

In order for triggers to be highlighted and clickable in-game, their action IDs must be declared in your vehicle JBeam's `"actionsEnabled"` list:

```json
"actionsEnabled": [
    ["id"],
    ["cruisecontrol_+"],
    ["cruisecontrol_-"],
    ["info_volUp"],
    ["info_volDown"],
    ["info_prev"],
    ["info_next"],
    ["info_mute"],
    ["info_voiceNav"]
],
```

---

### 5. Event Links (`propTriggerEventLinks`)

Map triggers to actions defined in your vehicle's `interaction.json` (or `input_actions.json`):

```json
"propTriggerEventLinks":[
    ["triggerId", "triggerInput", "inputAction"],
    
    // Steering wheel cruise control (Left Click)
    ["cruisecontrol_+", "action0", "cruisecontrol_+"],
    ["cruisecontrol_-", "action0", "cruisecontrol_-"],
    
    // Steering wheel audio & nav controls (Left Click)
    ["info_volUp",    "action0", "info_volUp"],
    ["info_volDown",  "action0", "info_volDown"],
    ["info_prev",     "action0", "info_prev"],
    ["info_next",     "action0", "info_next"],
    ["info_mute",     "action0", "info_mute"],
    ["info_voiceNav", "action0", "info_voiceNav"],

    // Dual-Action Button Example: Left Click vs Right Click
    ["drive_mode_btn", "action0", "next_drive_mode"],
    ["drive_mode_btn", "action1", "prev_drive_mode"],

    // Rotary / Volume Knob Example: Mouse Wheel Up / Down
    ["rotary_volume",  "wheelUp",   "info_volUp"],
    ["rotary_volume",  "wheelDown", "info_volDown"],
    ["rotary_volume",  "action0",   "info_mute"]
],
```

---

## Action Definition (`interaction.json` vs `input_actions.json`)

> [!IMPORTANT]
> **Avoid Action Duplication**: BeamNG's input manager loads both `input_actions.json` and `<vehicle>.interaction.json`. Define each action in **only one** of these files. Declaring the same action in both files will trigger BeamNG's `"Detected duplication of action"` error.

Define clickable vehicle interaction actions in `vehicles/<vehicle_name>/<vehicle_name>.interaction.json`:

```json
{
  "fileversion": 2,
  "actions": {
    "info_volUp":    { "order": 48, "ctx": "elua", "onDown": "extensions.c6g3_infotainment.volumeUp(0.02)",   "title": "Infotainment Volume Up",        "desc": "Increases infotainment volume by 2%" },
    "info_volDown":  { "order": 49, "ctx": "elua", "onDown": "extensions.c6g3_infotainment.volumeDown(0.02)", "title": "Infotainment Volume Down",      "desc": "Decreases infotainment volume by 2%" },
    "info_prev":     { "order": 50, "ctx": "elua", "onDown": "extensions.c6g3_infotainment.mediaPrevious()",  "title": "Infotainment Previous Track",   "desc": "Previous media track or image" },
    "info_next":     { "order": 51, "ctx": "elua", "onDown": "extensions.c6g3_infotainment.mediaNext()",      "title": "Infotainment Next Track",       "desc": "Next media track or image" },
    "info_mute":     { "order": 52, "ctx": "elua", "onDown": "extensions.c6g3_infotainment.toggleMute()",      "title": "Infotainment Toggle Mute",      "desc": "Toggles infotainment mute" },
    "info_voiceNav": { "order": 53, "ctx": "elua", "onDown": "extensions.c6g3_infotainment.toggleVoiceNav()", "title": "Toggle Voice Navigation",        "desc": "Toggles navigation voice guidance on or off" }
  }
}
```

---

## Engine Version Compatibility (v0.38 & v0.39+)

`propTriggers` includes automatic dynamic version detection (`checkIs039OrHigher()`):

- **BeamNG < v0.39 (v0.38 and earlier):** Renders hover actions and keyboard/controller bindings via `extensions.ui_bindingsLegend.addActions('propTriggers', ...)` in the native top-right legend bar, matching vanilla v0.38 behavior.
- **BeamNG v0.39+:** Streams 3D screen-space bubble target payloads via `setPropTriggerCrosshairTargetStream` with real-time edge-aware label placement, matching the vanilla v0.39 crosshair interaction system.

