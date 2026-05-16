# Magely

**Magely** is a mage-focused buff manager addon for *World of Warcraft: TBC Anniversary*, inspired by the Priestly/Wildly workflow.

It tracks:

- Arcane Intellect / Arcane Brilliance
- Amplify Magic (optional, mode-based)
- Dampen Magic (optional, mode-based)
- Optional second pane for Innervate and Power Infusion request tracking

## Usage

```text
/magely help
```

Open settings:

```text
/magely config
```

## Features

- Compact group/raid buff rows with secure click-casting
- Spec-aware mage header styling for Arcane, Fire, and Frost
- Optional encounter-aware visibility modes for Amplify/Dampen
- Optional cooldown request pane:
  - Innervate tracking (with debug override)
  - Power Infusion tracking
  - Click row to whisper the provider

## Installation

### Manual

1. Place the `Magely` folder into:

   ```text
   C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\
   ```

2. Ensure the final path is:

   ```text
   ...\AddOns\Magely\
   ```

3. After each deployment/update, run:

   ```text
   /reload
   ```

Relog is only a fallback if the client does not detect a brand-new addon folder in the current session.

## Supported Version

- World of Warcraft: TBC Anniversary
- Interface: `20505`
