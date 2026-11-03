# Native provider-free qualification, November 3

Windows-only, opt-in source candidate. **Unbuilt and unrun** at this handoff;
ordinary native launch, owner settings/install and physical behavior remain
unqualified by this work. Public origin means local commits only.

Source branch: `napo/forza2-provider-free-20261103`, isolated worktree
`E:\Source\_work\napo-forza2-provider-free-20261103`, starting at
`8cb28bca616ef5358f9f0ab7e67fff791f36efde`.
Coordinator request504092 selected FM2 after FM3's read-only prerequisite audit.

Installed FM2 EXE remains
`95E74E3DCD4EA5AB3A50A4DD0363561DCD1211D4BA05C0D19CEC9F2015A69A50`
(46,051,328 bytes). Its user TOML selects SDL, keyboard emulation and fullscreen
and points through the historical LaunchBox alias; do not run that configuration
for this case. Owner profiles `dbce` and `Player` live under
`C:\Users\antho\Documents\forza2\profiles`. Genuine importer log records2344
files/5.03GB and zero missing/size/hash mismatches. No owner install receipt is
invented or changed. Current source SDK package0.10.0 has runtime
`E359209F...` and GPU `0C23CFA2...`; these differ from the historical installed
tuple and will be identified separately in the candidate receipt.

## Source behavior

- `--provider_free=true` is a one-way latch selected before backend construction.
  The real SDK InputSystem has zero drivers. Actual guest slot0 gets only the
  private native pad command; capabilities/keystrokes/rumble cannot touch a pad.
- The silent audio system supplies a real successful guest render-client
  driver and acknowledges256-sample frames at48kHz on the SDK's existing worker.
  It does not construct SDL/DirectSound/XAudio/WASAPI/waveOut audio backends or
  contain a host-output fallback. Actual driver/frame/failure counters are
  published. This is source/fixture evidence until a live candidate establishes
  the selected path; it is not a physical-silence claim.
- All40 NetDll imports in the compiled game table are fenced. Ordinary mode
  resolves original DLL exports. Distinct local wrapper symbols are used in
  guest mappings/calls and host definitions to avoid COFF `__imp_` collisions;
  no duplicate-symbol linker override is used.
- Commands/status use actual shared-delete readers and whole-file atomic
  publication. Strict nonce/sequence/range validation, stale-command neutral,
  consumed-state trace and normal close are exercised in scratch. Real
  Present-wrapper progress is distinct from actual captured pixels.
- Non-Windows builds keep a disabled qualification stub; no non-Windows build
  or runtime evidence is claimed.

## Admission and evidence

`tools/provider-free/Cheap.ps1` is the complete no-lease/no-game/no-hook/no-device
scratch suite. It exercises90 actual native consumer/export/factory/driver
checks, the real data clone/2344-member alternative-hash verifier, typed
Build/Run positive and refusal paths, actual host-header/Present syntax, the
production concurrent IO,29 sparse/metadata/lifecycle checks with an independent
numeric-tick verifier, six owned-job classifier cases, callback scope regressions
and nested versus helper-only stop accounting. Development evidence is ignored
under `_local/provider-free/cheap-dev*`. Final admission requires two complete
passes with identical source/SDK pins after the source is frozen.

`Prepare-Cpu.ps1` produces a clean-source/full-SDK/tool/shared-catalog plan.
`Build.ps1` requires a fresh CPU GO and exclusive lease, at most1800s total,
90s cleanup reserve and two compiler jobs. It clones and verifies owner disc,
profile/cache privately, builds only the native EXE from existing generated
code, inventories complete EXE/runtime-DLL imports against the shared catalog,
persists owned child identities and releases only after quiescence. No game,
renderer, input, owner write, install or public push is part of that CPU case.

Only a later separately approved ONE live plan may use the rig:440s native
Start/A/release with six2s exact-HWND WGC milestones,720s total/120s cleanup,
fresh180s idle and passive LL authority, at most three zero-LL startup resets
within90s, fixed foreground or one natural exact-owned transition. Private
runtime/settings/user/cache only; complete owner snapshot plus independent
verification, exact topology and full hook/job/lease cleanup. Native quit,
then exact owned SDL/main-window normal WM_CLOSE after5s if needed; **no game
hard kill**. A capture-helper failure cannot implicitly kill the game. Unknown
owner drift is preserved for investigation, never overwritten as a routine
restore. Uncertain close/state cleanup retains custody.

The assertion is native consumed input/progress plus captured UI/startup
milestones. Driving, pedals/gears, physical wheel/FFB, settings UI, telemetry,
triples/seating, installation and owner acceptance remain open. Every shared
host-surface signal needs a concrete resolution before an isolation claim.
