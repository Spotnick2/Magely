# Magely Forever

**Magely** is a PallyPower-style Mage buff manager for **World of Warcraft: Forever**.

> **Being ported.** Magely is moving from TBC Anniversary to WoW: Forever 1.60.1, on the shared
> [LibGroupBuffs](https://github.com/Spotnick2/LibGroupBuffs) engine that Priestly and Wildly use.
> The current `main` is mid-port and does not run in game yet. TBC Anniversary is no longer
> supported.

It tracks:

- Arcane Intellect / Arcane Brilliance
- Amplify Magic (optional: always, when detected on a group member, or by instance)
- Dampen Magic (optional, same modes)

The TBC version's cooldown request pane (Innervate and Power Infusion) is not part of the first
Forever release: this client does not let addons read the combat log, and neither spell exists at
the current level cap. It is planned to return later.

## Usage

```text
/magely help
/magely config
```

## Installation

Install from CurseForge, which bundles LibGroupBuffs. A manual install goes into:

```text
C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Magely\
```

Developers: see `AGENTS.md`; `pwsh Tools/deploy.ps1` deploys with the library from a
`../LibGroupBuffs` checkout.

## Supported Version

- World of Warcraft: Forever 1.60.1
- Interface: `16001`
