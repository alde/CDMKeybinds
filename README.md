# CDMKeybinds

CDMKeybinds shows action bar keybinds on Blizzard's Essential and Utility
Cooldown Manager icons.

It resolves action-bar, BindPad, and Clique bindings. Spells used through
`/cast`, `/use`, and `/castsequence` macros are supported. Modifier conditions
are included in the displayed binding, using compact prefixes such as `s-`,
`c-`, and `a-`.

## Installation

Copy the `CDMKeybinds` directory into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Enable **CDMKeybinds** on the character-selection add-on screen. Blizzard's
Cooldown Manager must also be enabled in the game settings.

## Usage

The add-on works automatically. Changing an action bar slot, macro, keybind,
action page, or shapeshift form refreshes the displayed bindings.

Use `/kb` to open Blizzard's Quick Keybind Mode. CDMKeybinds only registers
this command when another add-on has not already claimed it.

## Scope

Keybinds are shown on the Essential and Utility cooldown viewers. Buff icons
and buff bars are not altered because they represent aura state rather than
castable cooldown buttons.

Clique and BindPad integration is automatic when either add-on is installed.
CDMKeybinds has no settings or saved variables.
