# Forza Motorsport 2 — agent guide

Portfolio rules: `E:\Source\dbce-project-mgmt\HOW-WE-WORK.md` (read first; it replaces older process, lease, review and testing instructions). Current focus: `E:\Source\dbce-project-mgmt\NOW.md`. Feature status lives in the portfolio grid (`python E:\Source\dbce-project-mgmt\tools\portfolio_grid.py plan fm2`), not in this file. Grid id: `fm2`.

## Project

Native Windows x64 port of the Xbox 360 Forza Motorsport 2 by static recompilation (PowerPC to C++, ReXGlue SDK v0.10.0), Direct3D 12 renderer, own launcher (`Forza2Launcher.exe`). Remote `d-b-c-e/hl360-Forza2` (fork of `0herculabs/hl360-Forza2`; visibility unconfirmed, so do not push). The repo has no game files; users supply their own EU or US disc image. Recompiled code in `generated/` is committed, so a clone builds without the game.

## Build

`build.bat [release|relwithdebinfo|debug]` (default release). Needs Visual Studio 2022 Build Tools with the C++ workload and LLVM; it fetches the SDK into `_sdk\` on first run via `scripts/get-sdk.ps1`. Output: `out\build\win-amd64-<config>\forza2.exe`. To regenerate code, put `default.xex` in `assets\` and build again. `tools\package_release.ps1` builds the release ZIP.

## Test

- Provider-free tests are in `tests/provider_free` (`test_console.c`, `test_io.c`, `test_native.cpp`, `test_rounding.cpp`); how to build and run them: unknown — check `docs/2026-11-03-provider-free-qualification.md`.
- Profiles and saves live under `Documents\forza2\profiles\<profile>\`. Back up and restore them around a run.

## Install / run on the rig

Players use `Forza2Launcher.exe`. For development, `run.bat` starts the build tree against `assets\` and logs to `run.log` (set `FORZA2_BUILD=relwithdebinfo` for symbolized crash reports).

## Shared code

No vendored DBCE toolkit copy found yet. Reusable code goes in the toolkit. Change shared code in the toolkit and re-sync; never edit the vendored copy.

## Project-specific rules

- Do not commit game files, disc images, extracted assets or native binaries.
- Project Forza Plus 2 install/uninstall must keep the original files so uninstall restores the game exactly.

## Key docs

- `README.md`, `CHANGELOG.md`
- `docs/PLAYERS.md`
- `docs/2026-11-03-provider-free-qualification.md`
- `docs/THIRD_PARTY_NOTICES.txt`


<!-- BEGIN project-file-location -->
## Project files and temporary work

Keep project-related research, evidence, scripts, packages, and other working files inside the relevant project folder whenever practical. Keep disposable or machine-specific outputs git-ignored when they do not belong in version control; never ignore files that should be committed merely to hide them. When a project folder is unsuitable, use `E:\Source\temp\<project>` instead of creating scattered drive-root folders. Record the location of material needed by later work and update references when relocating it.

Clean up temporary files and disposable copies promptly once they are no longer useful. Preserve active work, user data, settings, saves, required evidence, backups, rollback artifacts, and worktrees until their retention or replacement is established. Follow existing project, rig, and data-loss safeguards; do not remove files merely because they are old or untracked.
<!-- END project-file-location -->
