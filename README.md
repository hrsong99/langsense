# Langsense

A small macOS menu bar prototype for fixing text that was typed with the wrong keyboard language active:

- English keys pressed when the user meant Korean
- Korean typed when the user meant English

The app keeps a short buffer of recent typing, looks for likely wrong-script tokens, and can either:

- suggest a correction for manual invocation,
- auto-fix a completed token when you hit a boundary key, or
- aggressively rewrite the current token mid-word when confidence is extremely high.

## Safety status

This project is still a prototype.

- **Manual mode is the default and recommended mode.**
- **Both auto modes are experimental.** They now use much stricter heuristics than before and may trigger less often by design.
- Auto-fixes are intentionally conservative and may skip many tokens that manual conversion would still handle.
- Replacement and input-source switching are best-effort and can still fail in some apps or secure contexts.

If you want the safest behavior for public use, stay in **Manual** mode.

## What works

- SwiftUI macOS menu bar app (`MenuBarExtra`)
- Global key event monitoring for recent typed text
- Heuristic detection of likely mistyped token
- Conversion between:
  - QWERTY letters -> Hangul syllables using the standard Korean 2-set keyboard mapping
  - Hangul syllables/jamo -> QWERTY letters
- Global hotkey (via `NSEvent` monitors) to apply the latest suggestion manually
- User-selectable correction modes in the menu bar UI
- Best-effort input source switching between U.S. English and Korean
- Text replacement that tries the Accessibility API first (atomic, no clipboard) and falls back to a safer async paste path with clipboard-change guard
- Token buffer invalidation on mouse clicks, scroll, navigation keys, modifier chords, and app switches to avoid replacing text at the wrong cursor position
- Secure-input detection (`IsSecureEventInputEnabled()`) that skips replacement in password fields and terminals with secure input active
- Lightweight SwiftPM tests for conversion and stricter auto-mode gating

## Correction modes

### 1) Manual
The original and safest behavior.

- The app watches recent typing and computes a suggestion.
- Nothing is changed automatically.
- You apply the current suggestion via the menu button or the hotkey.

**Recommended for normal use.**

### 2) Auto-fix on boundary (Experimental)
Conservative auto-fix for completed words.

- The app waits for a token boundary such as `Space`, `Return`, `Tab`, or punctuation.
- It only auto-fixes when the finished token passes stricter composition and confidence checks.
- Recent corrections enter a short cooldown so freshly corrected text is not immediately corrected again.
- If replacement fails after switching input source, the app tries to restore the previous input source.

**Experimental. Safer than aggressive mode, but still less safe than manual mode.**

### 3) Aggressive mid-word (Experimental)
Faster, riskier auto-fix while you are still typing.

- After more characters have been typed, the app may rewrite the current token immediately.
- This mode now requires extremely high confidence and also honors the short correction cooldown.
- It is intentionally much less eager than earlier prototype behavior.

**Experimental and still the riskiest mode.**

## macOS permissions / limitations

### Input Monitoring
Required so the app can observe global key presses via an event tap.
Without this permission, recent-text tracking and automatic suggestion updates will not work.

### Accessibility
Required so the app can synthesize delete / paste keystrokes for correction.
Without this permission, the app can still compute a suggestion, but it cannot reliably replace text in the frontmost app.

### Input source switching limitations
The app uses Carbon Text Input Source APIs (`TISCreateInputSourceList`, `TISSelectInputSource`) to switch between English and Korean.
This is best-effort and depends on the target input sources being installed/enabled in macOS settings. The app looks for:

- `com.apple.keylayout.US`
- Korean sources whose input source ID or localized name contains `Korean` / `2-Set`

If the user uses a different English or Korean layout, the selection logic may need adjustment.

### Replacement limitations
Automatic background correction is not consistently reliable on macOS across all apps. This prototype uses a layered best-effort workflow:

1. Watch recent typing, invalidating the buffer on cursor-moving input (mouse clicks, scroll, arrow/Home/End/PageUp/PageDown keys, modifier chords, app/window switches).
2. Infer a likely mismatch.
3. Check `IsSecureEventInputEnabled()`; skip replacement if a password field or terminal with secure input is active.
4. Switch input source.
5. Try Accessibility replacement first: read the focused element's selected text range, extend it backward, and write the replacement directly. No clipboard, no synthetic keystrokes.
6. If the focused element does not support Accessibility text replacement (e.g. some Electron apps), fall back to an async paste path:
   - Write replacement to the pasteboard and record its change count.
   - On a background queue, post delete keystrokes followed by `⌘V`.
   - After a short delay, restore the previous pasteboard contents *only* if the change count has not advanced (so a concurrent `⌘C` by the user is not clobbered).

This works best in normal text fields/editors. It may still fail or behave inconsistently in:

- remote desktop windows
- games
- apps that block paste or synthetic events
- apps whose text insertion timing differs from standard AppKit fields

Even in supported apps, auto-correction is heuristic and not guaranteed. Manual mode remains the safest fallback.

## Hotkeys

- `Control` + `Option` + `Command` + `Return` — apply the current suggestion.
- `Control` + `Option` + `Command` + `Z` — revert the last auto-correction, restore the previous input source, and add the original token to a persistent blocklist so it is never corrected again.

The blocklist is stored at `~/Library/Application Support/Langsense/blocklist.json` and is consulted before any suggestion.

## Regression matrix

A built-in CLI regression matrix verifies that common English words (e.g. `check`, `world`, `doesn`) are not mis-corrected and common Korean mistypes (e.g. `dkssud`, `tkfkdgo`) do convert cleanly:

```bash
./.build/debug/Langsense --regression-check
```

Exits 0 if all cases pass. Extend `Sources/Langsense/RegressionHarness.swift` with more cases as you find them.

## Project structure

- `Package.swift` - Swift package definition
- `Sources/Langsense` - app source files
- `Tests/LangsenseTests` - conversion and heuristic tests

## How conversion works

### English -> Korean
Each Latin key is mapped to a Korean 2-set jamo key. The converter then composes jamo into Hangul syllables using the standard Hangul composition formula (`L/V/T`).

Example:

- `dkssudgktpdy` -> `안녕하세요`

### Korean -> English
Each Hangul syllable is decomposed into its leading consonant, vowel, and optional final consonant jamo, then mapped back to the original Korean keyboard key sequence.

Example:

- `ㅗ디ㅣㅐ` -> `hello`

## Running

Open the package in Xcode on macOS:

1. `open Package.swift` or `xed .`
2. Run the `Langsense` target.
3. Grant Accessibility permission when prompted.
4. Open **System Settings → Privacy & Security → Input Monitoring** and enable the app there if macOS does not prompt automatically.
5. Ensure both English and Korean input sources are enabled in System Settings.
6. Leave the app in **Manual** mode unless you specifically want to try the experimental auto modes.

You can also build from Terminal on macOS:

```bash
swift build
swift run
swift test
```

## Notes

This repository is being hardened for safer public publishing, but it is still a heuristic macOS utility. The auto modes are intentionally stricter and less eager than the original prototype, which reduces false positives at the cost of fixing fewer tokens automatically.
