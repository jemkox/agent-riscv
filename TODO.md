# M11 (Wrap-up of Doom) checklist
- [x] read play harness/verify + Makefile play section
- [x] fix tools/play_verify.py: compare scripted run against a NO-KEY baseline run (identical before first key, diverge after)
- [x] verify new `hdl make play_test` PASSes with the fix (and FAILs for a no-op key script)
- [x] `hdl make all_tests` target: test, test CACHE_LAT=5, ui um mi, regress N=500, m7, doom
- [x] run all_tests green, record output in PROGRESS.md
- [ ] README.md: Doom section (how to build/run `hdl make play`, numbers, frames, limitations)
- [ ] PROGRESS.md D1 section + commit `D1: ...`
- next: D2 P2 speed toward 15M cyc/s (profile Doom runner first)
