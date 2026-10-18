# Changelog

All notable changes to Voxflow are documented here.

Entries before 0.1.0 document the upstream FreeFlow project this fork is based on.

This project uses semantic versioning for public releases. Use `MAJOR.MINOR.PATCH`, where:

- `MAJOR` changes include breaking behavior or major compatibility changes.
- `MINOR` changes add user-visible features and improvements.
- `PATCH` changes fix bugs, polish existing behavior, or make small internal improvements.

## [0.1.4] - 2026-10-18

### Removed

- **All Voxflow-owned notch / pill / overlay-window code — deleted, not fixed.** The custom overlay panel, winged menu-bar layout, pill window, notch-geometry calculations, and the whole RecordingOverlay window machinery are gone (both the wide white bar and the small pill were rejected). The app's only top-of-screen presence is now the real system menu bar + a standard `NSStatusItem`: the system draws the menu bar and the real notch (camera cutout) with the real UI and animations. No Voxflow-owned window exists at the top of the screen in any state — menu open or closed, app active or in background, fullscreen or windowed. Recording / transcribing / paste-failed state shows via the status-item icon (record / ellipsis / orange alert) and the menu.
- Settings → Recording Overlay section (Minimalist menu-bar overlay / Drop-down pill + recording-timer toggle + display picker) — it configured the deleted overlay, so it is removed rather than left as dead settings. The Debug tab (Debug Overlay / update-overlay controls) is removed for the same reason.

### Fixed

- **Logo recreated completely (all surfaces).** App icon, menu-bar tray icon, and in-app wordmark redrawn as sharp vector renders: pixel-aligned bars, thicker Bézier ribbon, one continuous vertical gradient across the whole mark, feathered highlight. The hero "VOXFLOW" wordmark was stroke-only at 60–90% opacity with a slow drift (faint/ghosted); it is now solid filled letters with a thin orange hairline at full opacity. No stale/low-res asset is referenced anywhere.
- **Dashboard hero buttons.** The Dashboard never displayed `appState.errorMessage` / recording state, so a failed "Start Dictating" click (permission missing, mic denied, provider error) looked identical to a dead button — the failure only showed in the menu-bar menu. The Dashboard now has a visible status banner (error + working permission action, paste-failure copy action, recording/transcribing indicators), and both hero buttons log at action entry (`os_log`, provable in Console).
- **Ollama works end-to-end.** Root cause: Ollama's OpenAI-compatible API serves `/v1/chat/completions` and `/v1/models` but has NO audio-transcription endpoint, so the app's `{base}/audio/transcriptions` request always 404'd. For the Ollama provider, audio is now transcribed on-device via macOS Speech Recognition (`SFSpeechRecognizer`, on-device when supported) and only the polish/transform step goes to Ollama's `/chat/completions`. Local-host validation no longer demands an API key: an empty key validates by server reachability. Realtime streaming is skipped for Ollama (no realtime API; the file path handles it). The Ollama subtitle and the Transcription Model field now state plainly that the model field is unused for Ollama.
- **Test connection (Settings → AI Provider).** New "Test connection" button reports the REAL result: Ollama not running on `localhost:11434` ("start it with `ollama serve`"), polish model not pulled ("run `ollama pull <model>`"), invalid API key, endpoint 404, unreachable host. Never a bare "404 Not Found" again.
- **Dashboard scroll + pinned tab bar.** The old `ZStack(alignment: .bottom)` let a taller-than-window content stack grow past the window, pushing the CustomTabBar below the visible edge with no way to scroll to it — and no ScrollView wrapped the content. The Dashboard is now one plain `VStack`: top bar, status banner, a single `ScrollView` for the content, tab bar pinned at the bottom. The window also gets `minSize 1080×680` (SwiftUI `.frame(minWidth:minHeight:)` does not constrain the NSWindow). History scrolls normally: the nested `List` (which fought the outer scroll) is replaced by plain rows with dividers, and all nested ScrollViews (Insights, Help, Dictionary, Snippets, Settings sub-views, Run Log) are removed — the Run Log renders its latest 100 rows inline.
- **Permissions are actionable, not dead warnings.** The menu's "Global shortcuts unavailable" row was a dead `Text`; it is now the message plus a working "Grant permission in System Settings" button (opens the Accessibility pane). The Dashboard error banner also offers the right pane for Accessibility / Microphone / Screen Recording errors (the permission prompts themselves already opened the right panes).
- **Paste failure auto-detect + copy button.** After dictation, if the cursor/focus is NOT in an editable text field, the app already detected it via the Accessibility focused-element check — but the only affordance was the deleted pill popup. Now the copy button appears automatically in the status-item menu ("Text not pasted. Click here to copy text." — really copies) and in the Dashboard banner, and the status-item icon turns into an orange alert. The dictation is still saved to history, and history entries keep their working copy action. The 15s auto-clear still applies.

### Changed

- History rows: swipe actions removed (they only work inside a `List`); rows carry the real Copy / Play / Delete buttons.
- Run Log (Settings): renders the latest 100 runs inline with a "Showing the latest 100 of N runs" note instead of a nested scroll.

## [0.1.3] - 2026-10-17

### Fixed

- Pill double-bar: the overlay now hosts its SwiftUI content in ONE `NSHostingView` created once when the panel is created and never replaced. Previously the panel's `contentView` was replaced with a fresh hosting view on every phase change, letting AppKit composite transient frames while the new view laid out — the white bar segment next to the black pill. Phase changes now re-render the same hosted view from published state (the panel frame still animates, so the hotkey animation plays on that single pill). The panel itself is still created once, permanent at the top, opaque black throughout.
- Dashboard hero buttons: "Start Dictating" now runs exactly the menu item's flow (`toggleRecording` — begins a real recording, or stops + transcribes if one is already running) instead of a narrower direct-start path that skipped the manual-session setup. "See how it works" opens the real Help section, as before. Both buttons now carry an explicit full-rect hit area.
- Button hit-testing: pearl, glass, and prominent-glass button styles now declare an explicit full-rectangle hit area, so clicking anywhere on a button — its background or its text label — fires the action. The same full-rect hit area is applied to the Dashboard tab-bar buttons and the TODAY list row buttons (play / copy / delete).

## [0.1.2] - 2026-10-17

### Added

- Permanent pill: after launch a minimal idle pill (mic glyph, existing black-pill style) stays visible at the top center across all apps and spaces. Every phase — recording, transcribing, feedback, paste-failed, update — returns to the idle pill instead of dismissing. The pill's look is unchanged.
- AI provider picker in Settings (inside the Dashboard Settings section): Gemini (default) / Groq / Ollama (local) / Custom OpenAI-compatible endpoint. Switching applies immediately — base URL, all four model fields, and that provider's own Keychain-stored API key — because the pipeline reads those fields at call time. Each provider keeps its own key, so switching never clobbers another provider's key.
- Theme picker in Settings: Light / Dark / System, persisted and applied via `preferredColorScheme`. Light is the premium default.
- Original AI-generated dashboard banner image (abstract sound-wave "V" ribbon, amber→coral), bundled as `DashboardBanner.png` and shown in the Dashboard hero.
- Floating bottom tab bar (capsule, material background, spring-animated selection pill) replaces the left sidebar for Dashboard navigation. All 10 sections stay reachable; the bar scrolls on narrow windows so tabs are never clipped.
- Native SwiftUI motion in the Dashboard, adapted from free web-effect libraries (no React, no copied code): staggered letter rise on headings, word-by-word emerge, wipe reveal on the hero headline, skew slide-in on list headers, outlined VOXFLOW wordmark, 3D image-fold reveal, floating icons, and a slow banner-only gradient mesh. All effects render instantly when macOS Reduce Motion is on, and nothing animates on the pill.
- Pearl button style (glossy black pill, hover sparkle, press-down) on primary actions; Apple-glass-style buttons elsewhere — frosted glass for secondary, prominent glass for secondary-prominent, red-tinted glass for destructive actions. Glass is implemented as a native SwiftUI shim so the app still builds on macOS 13+ and on the CI toolchain (no deployment-target change).
- Vendored atoms from the user's SwiftKitComponents library (adapted to macOS): buttons, cards, StatCard, search/styled fields, ToggleRow, SegmentedPicker, toast, shimmer/skeleton, ProgressRing, empty/error states, SettingsRow, history swipe list, status/count badges, and the tab bar. PricingCard and DeleteAccountButton deliberately not used (Voxflow is free and has no accounts).

### Changed

- Single Dashboard window: Settings renders inline as a Dashboard section and Setup renders inline as the first-run section of the same window. No separate Settings or Setup window; the Settings-opens-Dashboard redirect is gone.
- Dashboard theme follows the pastel-gradient hero: light, airy, rounded-2xl cards, soft shadows, generous spacing. Dark theme is the same layout in deep tones.
- Gemini polish now runs on `gemini-2.5-flash-lite` (audio transcription stays on `gemini-2.5-flash`); polish token cap reduced 4096 → 2048. Existing installs with the old `gemini-2.5-flash` polish default are migrated to flash-lite automatically.
- App icon and tray icon re-rendered sharply from the same original concept (three pill bars forming a V + Bézier ribbon sweep, amber→coral gradient) — vector-clean redraw, all six `.icns` sizes regenerated from the new master.

### Fixed

- "Invalid response" dead-end: Gemini transcription now accepts content as a string or an array of content parts, retries once on a parse failure, and reports an actionable message instead of a bare "Invalid response". Polish failures already fell back to the raw transcript; that path is preserved.
- Language/script: the pipeline now passes the selected language into BOTH transcription and polish. Gemini transcription previously received no language constraint, so it could transcribe Roman-script Hinglish into Devanagari. Output now stays in the same language and script the user spoke; Devanagari is produced only when Output Language is explicitly set to Hindi. If polish still returns Devanagari, it retries once with a stricter script prompt, then falls back to the raw transcript — dictation is never lost.
- Pill rendering: the overlay panel is now created once and never destroyed per phase (phase changes are content swaps + short resizes), the hosting layer is backed opaque black so no pre-layout frame flashes clear/white, and the compact drop-down top-padding bug is fixed — on notched displays in compact mode the padding previously pushed error/update/paste-failed pill content fully out of the frame, rendering empty black strips.
- The striped white/dark vertical-bar artifact reported at the top center is addressed by the persistent-panel + opaque-backing fixes above. The exact compositor artifact could not be reproduced without a Mac; if it persists on a real Mac it is likely outside the overlay (e.g. a screenshot/compositor tear) and should be re-reported with a screen recording.

## [0.1.1] - 2026-10-17

### Fixed

- AppIcon.icns type codes: the icon size entries were mislabeled (e.g. the 16px payload was tagged as 1024px), so macOS could render the app icon at the wrong sizes. The icon now carries the correct type codes.

## [0.1.0] - 2026-10-17

### Added

- Voxflow launch: rebrand of the FreeFlow fork with a new original logo, bundle ID `com.voxflow.app`, and credits to Raphael Axiom and DKH Verse.
- Native Gemini preset: Gemini's OpenAI-compatible endpoint powers both transcription (`gemini-2.5-flash`) and polish. Setup asks for a Gemini API key; Groq remains an optional alternative provider.
- Polish prompt that returns dictation **with layout** (headings, bullets, structure as appropriate) and preserves the speaker's language — Hinglish stays Hinglish in Roman script, with no Devanagari conversion and no forced English.
- Dashboard: searchable history of every dictation with click-to-copy, delete, and clear, plus real stats (words today, total words, words per minute, day streak).
- Paste-fail safety net: when no text field has focus, the dictation is still saved to history and a pill offers "Text not pasted. Click here to copy text."
- Notetaker, Dictionary, Snippets, Style presets, Transforms, and Scratchpad — all fully functional in the dashboard.
- Setup rebuilt around the Gemini API key; the GitHub social-proof panel and Groq references are gone.

### Changed

- Default transcription and polish models are now Gemini models.
- Update checks, release notes, and download links point at `raphaelaxiom/voxflow`.
- Release signing is tolerant: without a Developer ID certificate, builds are ad-hoc signed and notarization is skipped.

## [1.3.1] - 2026-10-09

### Fixed

- The recording timer is now off by default. You can enable it in Settings; existing saved choices are preserved.

## [1.3.0] - 2026-10-09

### Added

- An optional elapsed recording timer in the dictation overlay.
- A setting to disable full-desktop screenshots when active-window capture is unavailable.

### Improved

- Context and fallback models now use Qwen 3.8 on Groq. Existing Groq Qwen 3.6 selections update automatically, while custom provider choices are preserved.
- Context failures now show clear model, authentication, rate-limit, timeout, and response errors in run logs. Failed summaries are omitted from transcript cleanup and Edit Mode, including when retrying older entries.
- Network failures provide clearer guidance when a VPN or proxy may be interrupting transcription.
- Compatibility with newer Swift toolchains and reliability checks for dictation and releases.

## [1.2.1] - 2026-08-11

### Improved

- Model pickers now show only currently supported Groq options, with context models limited to those that can analyze screenshots.

### Fixed

- Fixed typing lag in custom vocabulary and prompt editors by saving changes when editing finishes instead of after every keystroke.

## [1.2.0] - 2026-07-14

### Added

- A Preserve exact wording option that skips transcript cleanup while still supporting literal translation, voice macros, and Edit Mode.
- An instruction guard that retries or falls back to the literal transcript when cleanup appears to answer a dictated prompt instead of preserving it.
- An option to keep dictations in clipboard-manager history.
- A menu bar action for adding copied words directly to the custom vocabulary while avoiding duplicates.

### Improved

- Post-processing now switches to the fallback model immediately when the primary model is rate-limited, remembers daily limits across restarts, and shows their reset times in Settings.
- The default fallback model now uses Qwen 3.6 27B, and models scheduled for Groq shutdown in July or August 2026 have been removed from the picker.
- Transcription failures now distinguish network outages from slow providers and display clearer errors in the recording overlay.
- The default context model now uses Qwen 3.6 27B and strips reasoning tags from context summaries.
- Local model requests now honor their configured timeouts, and transcription uses response formats compatible with a wider range of OpenAI-style models.
- Permission and update checks use fewer unnecessary background wakeups.

### Fixed

- Fixed a recording overlay resource leak that could leave hidden animations running after the overlay closed.

## [1.1.0] - 2026-06-03

### Added

- Model pickers in Settings for post-processing, fallback, context, and transcription models, including Qwen 3 32B and custom model entries.
- A recording overlay display picker for choosing the active window, primary display, or a specific connected monitor.
- In-pill error notifications so transient failures such as network or provider errors are visible without opening logs.
- Advanced timeout overrides for local model and slow network setups.

### Improved

- Retried dictations now place the successful transcript on the clipboard and update Paste Again.
- Paste Again now preserves the latest raw transcript earlier in the dictation flow, so it remains useful if later cleanup or pasting fails.
- Post-processing handles reasoning-oriented model output more cleanly, including Qwen thinking tags and providerless model aliases.

### Fixed

- Fixed cases where transcription could hang indefinitely when a provider accepted a connection but never returned a response.
- Fixed false screen-recording permission alerts from unrelated permission messages.
- Fixed duplicate in-pill error notifications being dismissed by an older timer.

## [1.0.0] - 2026-05-20

FreeFlow is now considered feature-complete and stable enough for a 1.0 release.

### Added

- Paste Again shortcut for re-pasting the most recent dictation.
- Recent transcript history in the menu bar, with copy actions for quickly reusing previous dictations.
- Run Log copy controls for both literal and cleaned transcript output.
- Menu bar actions for opening the Run Log and checking for updates.
- Debug settings for troubleshooting overlays and update prompts.
- A polished drag-to-Applications DMG background for installer builds.

### Improved

- Recording feedback now uses a cleaner minimalist menu-bar overlay, with clearer command-mode state.
- Transcribing and processing feedback appears sooner and more consistently after recording stops.
- Shortcut labels now use friendlier modifier names alongside symbols.
- Setup and recovery flows are more resilient when restoring app state.
- Sentence-ending dictations now paste with trailing spacing that better matches normal writing.
- Development builds and main-branch release automation are easier to identify and validate.

### Fixed

- Fixed shortcut collision checks for edit mode and manual modifier bindings.
- Fixed cases where dictation could terminate automatically while still in progress.
- Fixed clipboard restoration after dictation when the original clipboard content is unchanged.
- Marked transient dictation clipboard contents so clipboard managers can avoid saving them.
- Preserved spoken instructions verbatim during post-processing.
- Simplified transcription submission errors into clearer one-line messages.

## [0.3.3] - 2026-04-25

### Added

- Output Language setting for automatically translating dictated text before it is pasted.
- Transcription Language setting for choosing the language FreeFlow listens for during dictation.
- Recording state flag file for external tools that need to know when FreeFlow is actively recording.
- Distinct FreeFlow Dev app and menu bar icons so development builds are easier to tell apart from release builds.

### Improved

- Permission prompts and setup screens now use the correct app name for the installed build.
- Release notes in update prompts now render changelog formatting more clearly.
- Development builds now have clearer bundle naming and icon handling.

### Fixed

- Fixed audio recording crashes caused by unexpected input formats, resampling, and upload-path conversion.
- Fixed cases where FreeFlow could silently fall back when the selected microphone was unavailable.
- Fixed paste shortcuts on Colemak-DH and other non-QWERTY keyboard layouts.
- Fixed output language handling when custom system prompts are enabled.

## [0.3.2] - 2026-04-23

### Fixed

- Removed the pause-based audio interruption mode that could misfire and resume playback unexpectedly; dictation now only mutes audio.

## [0.3.1] - 2026-04-23

### Added

- Faster live dictation with realtime transcription support.
- A setting for choosing the realtime transcription model.
- Run log exports, so you can save a full dictation run for debugging or sharing.
- A Copy Transcript action in the run log.
- A voice command for submitting text: say "press enter" at the end of a dictation.
- Audio controls that can mute or pause other audio while you dictate, then restore it when recording stops.
- Build details in Settings for easier troubleshooting.
- Direct shortcuts from FreeFlow to the right macOS permission settings.
- A What’s New popup when an update is available.

### Improved

- Recording feedback now feels more responsive.
- The run log is easier to scan and use.
- Exported run logs include more useful context for reproducing issues.
- Realtime transcription is more reliable when recordings are cancelled, retried, or finish with no text.
- Provider settings are easier to edit without accidental whitespace or half-saved values.
- FreeFlow now warns you if alert sounds may be hard to hear because system audio is muted or very low.
- Update prompts now show the version, release date, and release notes more clearly.
- FreeFlow now uses proper version numbers for updates instead of internal build names.

### Fixed

- Fixed cases where arrow or navigation keys could be mistaken for Fn shortcut input.
- Fixed a clipboard timing issue that could paste the wrong content.
- Fixed empty realtime transcriptions getting stuck instead of finishing cleanly.
- Fixed waveform glitches caused by invalid audio levels.
- Filtered out more common transcription artifacts.
- Fixed alert sound hints staying visible after alert sounds are turned off.
- Fixed update checks so users only see real app releases, not internal builds.
- Fixed update checks so the app does not offer an older or already-installed version.
