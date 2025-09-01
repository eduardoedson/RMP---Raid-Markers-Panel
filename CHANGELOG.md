# Changelog

## [1.8.2] - 2025-09-01
### Changed
- Panel frame strata set to **LOW** (no longer overlaps default interface windows).
- Added optional setting to place panel behind interface windows.

## [1.8.1] - 2025-09-01
### Changed
- Ground/world marker toggle now only checks if the player is in a group/raid; it no longer requires leader/assistant.

## [1.8.0] - 2025-09-01
### Added
- Tooltip text updated to show correct target/ground marker info with placeholders.
- Unified error messages when not in group or missing leader/assistant permission.
- Secure PreClick now fully decides world marker toggle (no static macrotext).
- Improved consistency of "UNLOCKED" indicator behavior.

### Changed
- Code cleanup for readability and maintainability.
- Removed redundant static `/wm` assignment, relying only on PreClick logic.

---

## [1.7.3]
- Right-click toggle for world markers: place if missing, clear if present.
- Fallback logic when `IsRaidMarkerActive` isn’t available.
- In combat: right-click **places only** (secure restriction).

## [1.7.2]
- Removed Shift modifiers.
  - **Left-click**: set target icon.
  - **Right-click**: toggle ground marker.
- Cleaned code/comments; removed debug output.

## [1.7.1]
- Ready Check uses `C_PartyInfo.DoReadyCheck` with `/readycheck` fallback.
- Pull button:
  - **Left**: start with configured seconds (`/pull` or API).
  - **Right**: cancel (`/pull 0` + DBM/BigWigs fallbacks).
- Minimap skull: left opens options; right locks/unlocks panel.

## [1.7.0]
- Correct icon → ground mapping: Star→5, Circle→6, Diamond→3, Triangle→2, Moon→7, Square→1, Cross→4, Skull→8 (Skull no longer clears all).

## [1.6.0]
- Switched clicks to mouse-up to avoid taint/modifier misreads.
- Ground marker via secure macros (`/wm` / `/cwm`); improved tooltips.

## [1.5.0]
- Options UI polish:
  - Hover value tooltip on sliders.
  - Better spacing/scroll.
  - Removed text fields under sliders.
- “UNLOCKED” indicator above first icon when movable.

## [1.4.0]
- **Behavior** page:
  - Show only when in group/raid.
  - Default pull seconds.
  - Minimap icon toggle and size.

## [1.3.0]
- **Layout** page:
  - Button size, spacing, per row/column, vertical orientation.
  - Panel/background/border opacity.
  - Icon inner padding.
  - Lock/unlock with position save.

## [1.2.0]
- Minimap skull (borderless), draggable:
  - Left opens options, right locks/unlocks.

## [1.1.0]
- Panel with all raid icons + Ready Check + Pull.
- SavedVariables defaults.

## [1.0.0]
- Initial release: compact panel to set target raid markers.
