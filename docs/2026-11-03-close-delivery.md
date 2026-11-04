# Native close delivery while Present is in flight

This private qualification fix delivers a normal close request from native
input polling when Present no longer advances. It does not unblock Present or
prove a real hung FM2 process exits. No full-game EXE was built or run here.

Production commit `a454534a6339efe226aa2b13cc6f86598327e920` changes only
`src/provider_free.cpp`. Frame and Input share the existing close-once latch;
the selected consumer obtains the callback under the mutex and invokes it after
unlocking. Quit packets become neutral before state delivery and trace/status
publication. The1500ms stale threshold, nine-minute ceiling,80ms status cap,
zero-driver/silent-ACK/network/force fences and ordinary mode are preserved.
No new timer, thread, backend, forced stop or timeout was added.

Fixture22a41377 adds quit/stale modes to the real native consumer fixture. The
real Present wrapper enters an inert original; its probe consumes either an
active quit packet or a stale packet before the original returns. It checks
normal-close delivery in that interval, neutral state, callback re-entry into
the actual Input function without deadlock, and no repeated close from later
Input/Frame calls. Re-entry uses invalid user1 and changes no consumed controls.

## Actual offline result: GO508295

The frozen baseline uses actual production4b95691c with the identical new fixture
bytes. Both old cases exited1 with exact `FM2_NATIVE_CLOSE_DELIVERY` markers.
Their witnesses show frames1/returns1, closes0 and no callback re-entry. Old
quit delivered active controls; old stale delivered neutral but no close during
Present. Fixed quit and stale each passed40 checks, with close delivered while
entry1/return0, neutral state, callback re-entry and close once. The captured
summary is printed after original return and therefore shows returns1; its
`duringPresent` flag records the earlier interval. Existing full native fixture
passed261 checks,40 direct network exports/158 DLL entries and zero host drivers.

Two sequential native compiles succeeded with existing compiler/macro warnings.
The24.688-second slot built only fixture EXEs; no SDK/full-game build, game/ROM,
SDL/window initialization, hook, device, owner write, installation or public push.
All held tool roots exited normally, no force, job empty, retained handles zero.
Old diagnostic worktree4b95691c and canonical main79ff506 remain clean/unchanged.

Evidence under `_local/close-delivery/cpu01`:

| File | SHA-256 |
|---|---|
| result.json | `8F2975DB5D83FFF67011D45BAC473EB92A031DDB2ABC7D9E7FEFF9D68F40D7C0` |
| baseline-native-test.exe | `F032B2F6DF79985801451F66CCA541FFBACCB504DADB5D5F88948039F4064660` |
| fixed-native-test.exe | `5AFDCC81E42F1F993B18FA2F7EECD6CFF2B1173BDF65DD38D425AFC19D4A2DAF` |
| independent-process-audit.json | `DD994F1489ED18A4441743E7CC9BDA511E9BDF03208FF29DBB59003C61410F3B` |
| independent-all-images.json | `A0C5068ACE1EE1F9FA3BACC9A810EA9A270F59DEEBF0AC29D187A7C310733F61` |

## Audit timing limitation and correction

The pre-release independent CIM filter omitted the renamed
baseline-native-test/fixed-native-test image names. Held-root/exited-handle/job
closure passed, but that filter does not establish independent coverage of those
two names. A supplementary all-image/no-name-filter scoped CIM audit after the
automatic named lease release, before FINAL resource admission, found no residuals.
It does not retroactively qualify the original pre-release filter. No custody or
pending resource request remains; the original receipt is preserved unchanged.

Future machine-local operator `Check-Close-AuditV2.ps1` removes the name filter.
Its actual extracted pure function passed five synthetic scope/exclusion cases,
including both renamed EXEs and an unknown image scoped only by command line.
The original approved operator/hash remain unchanged; native tests were not
repeated. Future operator SHA
`40ECF010DC825ADA8056D48C992651B48B1E0402A9FAFEC9A5B3F08F60A58CDD`.
It needs a new frozen plan/GO before use. This pure check is not a new operating
lease result or complete descendant/independent timing qualification.

Full candidate build, private live normal-exit behavior, rendered gameplay,
physical/device/owner acceptance and installation remain separate gates.
