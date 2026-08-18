# To verify

Items needing manual verification with a physical controller. Remove entries once checked.

## Wheel menu style + `hud_zoom`

Verified automatically already: config decoding (both menu forms, aliases, bad-value fallback, zoom clamping), the wheel's aim/rotation math, wheel and list layout rendered offscreen, Xcode build, docs build, and that the app launches without crashing.

Still needs a controller and a live panel:

- [ ] **Stick aiming** — open a wheel menu, sweep either thumbstick, confirm the highlight follows the item under the stick and the ring stays still. Returning the stick to centre should keep the last selection, not reset it.
- [ ] **Dpad rotation** — dpad left/right rotates the ring and the highlight stays on the marker at 12 o'clock. Mixing the two (aim with the stick, then press dpad) should rotate the currently aimed item up to the anchor.
- [ ] **Confirm / cancel** — A and RT execute the highlighted item; B, X and LT close without executing.
- [ ] **Live panel sizing at zoom** — set `"hud_zoom"` to 1.5 and 2.5 and open each of the five HUDs (help, mode picker, custom menu, mode notification, debug overlay). Confirm each is scaled, not clipped, and still on screen. The screen-edge-anchored ones (mode notification, debug overlay) are the likely failure cases. Panel sizing was verified offscreen via `ImageRenderer`, not in a live `NSPanel`.
- [ ] **No pointer drift while aiming** — with a stick bound to `mouse_move`, confirm aiming the wheel does not also move the cursor underneath.
