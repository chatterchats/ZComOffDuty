# Off Duty overnight simtest report

Final report. All times are America/New_York (EDT, UTC−04:00).

Repository: `ZComOffDuty` (the paths below are relative to its root).

Started: **2026-10-09 22:41:14 EDT**. Last completed run: **2026-10-10 07:11:40 EDT**. Cleanup and shutdown verified: **2026-10-10T07:15:48-04:00**.

Stopped early at the human’s request after they manually closed the game. Batch 18 is the last completed batch. Batch 19’s harness had started and logged a mission-launch request, but no mission setup or result completed; its pending launch was cancelled. No batch 20 was started. The original 08:00 cutoff was superseded by this request.

**252 completed, sanity-valid runs (63 per condition), 0 excluded rows.** This comprises 12 full batches (5–16, 20 runs each), 2 single-round batches (17–18, 4 runs each), and batch 4’s 4 prior valid runs. This session completed 248 new runs. Batch 19 contributed 0 completed runs. Batch 3 and earlier and calibration runs are excluded as incomparable.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 63 | 100.0 | 5.73 (3–13) | 10.00 | 0.51 | 0.51 | 34.54 (2.75–67.70) | 0.00 (0) |
| tired | 63 | 100.0 | 5.71 (3–16) | 10.00 | 0.56 | 0.56 | 34.75 (11.68–68.73) | 0.00 (0) |
| exhausted | 63 | 100.0 | 5.56 (3–11) | 10.00 | 0.46 | 0.46 | 37.72 (6.52–64.49) | 1.24 (78) |
| spent | 63 | 100.0 | 5.90 (3–13) | 10.00 | 0.65 | 0.65 | 37.04 (6.11–72.52) | 2.19 (138) |

Health loss is computed per run as 100 × (1 − health_end / health_start), then averaged. The harness’s health total excludes downed operators. Starting health was consistently 291 / 291 / 276 / 262 across baseline / tired / exhausted / spent, reflecting the tier max-HP penalties. A win can report foes_left > 0 because the last death has not yet appeared in that read; MissionStatus/result remains authoritative.

## Interpretation

**The results do not show a clear increasing overall cost from baseline → tired → exhausted → spent.** Mean rounds are 5.73 → 5.71 → 5.56 → 5.90; mean health loss is 34.54% → 34.75% → 37.72% → 37.04%; mean downed is 0.51 → 0.56 → 0.46 → 0.65. These sequences are not consistently increasing. Every condition won all 63 runs and killed all 10 enemies.

Tired is descriptively very close to baseline. Exhausted and spent lose somewhat more health on average, and spent has the highest mean rounds and downs, but the observed round and health-loss ranges overlap for **every pair of tiers**: baseline/tired, baseline/exhausted, baseline/spent, tired/exhausted, tired/spent, and exhausted/spent. Range overlap alone does not prove equal effects. This sample does not establish a reliable ordering of tired versus baseline or exhausted versus spent, nor a clear separation in rounds or downs. No statistical significance claim is made.

AP loss shows the expected tier-specific cost: baseline/tired 0, exhausted 1.24, spent 2.19 events per run (78 and 138 events in total). Two short final spent runs had 0 AP losses; there is no five-consecutive-spent-run window with zero losses. The max-HP penalty is also consistently visible in starting health.

**The sample is too small to rank rare loss risk:** with no losses in any tier, these runs cannot show whether spent eventually loses more often. Even 63 runs per condition do not resolve the small, heavily overlapping outcome differences here. If investigating those overlaps further, collect 5 more runs per condition with the same setup rather than concluding the tiers are indistinguishable or have a proven monotonic cost.

## Sanity checks, exclusions, and oddities

Every completed comparable row passed the checks: freed Char_ first slot, at least one stopped reinforcement encounter, arrivals 0, foes_start 10, correct tier starting health, baseline/tired AP losses 0, valid win/loss/turn-cap result, and an empty error field. **No completed rows were excluded.** No five-run spent window had zero AP losses.

Batch 19 has no completed result row and is outside the outcome denominator. Its transcript ends with an unanswered mission-launch request after successful ai off, speed 1, campaign reset, and hub-settled replies. The human reported closing the game before the batch started; the harness timestamps show that scheduling had begun at 07:11:54, before a mission setup/result was logged. This is an interrupted launch, not a loss or sanity failure.

Relevant batch 19 transcript tail:

```text
> campaign reset
< ok reset to HUB_Root_2026.10.09-21.38.54 - Den ready 10872 ms after LoadFile
> wait phase=hub settled=1 timeout=240000
< ok waited 0 ms, 0 frames
> mission launch SK_Mapuzo_015 squad="Jacira Ako,Kabb Uppercut,Luco Bronc,Jae Mordant" enemies=SS_Separatist_Threat_01
[No reply before the pending harness was cancelled after manual game closure.]
```

## Crashes and timeouts

No new UECC crash folder appeared relative to the 15 folders present at the start. No completed CSV row or transcript contains an error or reply-timeout marker. The final game closure was reported by the human as intentional; it is not recorded as a spontaneous crash. No new crash address or recurrence of SWZeroCompany.exe+0x97042b6 was observed, so there is no new dump/run/condition/crash-time entry to report. Pre-existing dumps are not new crash evidence.

## Batches and raw files

All paths below are relative to the repository root given above.

- Batch 4 (prior session): 4 valid runs; `dist/simtest/20261010T023226Z-results.csv`; `dist/simtest/batch4.out`.
- Batch 5: 20 completed runs; requested 5 per condition; started 2026-10-09T22:46:02-04:00; completed 2026-10-09T23:26:23-04:00; return code 0. Output: `dist/simtest/batch5.out`. CSV: `dist/simtest/20261010T024602Z-results.csv`. Transcript: `dist/simtest/20261010T024602Z-run.log`.
- Batch 6: 20 completed runs; requested 5 per condition; started 2026-10-09T23:26:35-04:00; completed 2026-10-10T00:06:01-04:00; return code 0. Output: `dist/simtest/batch6.out`. CSV: `dist/simtest/20261010T032635Z-results.csv`. Transcript: `dist/simtest/20261010T032635Z-run.log`.
- Batch 7: 20 completed runs; requested 5 per condition; started 2026-10-10T00:06:13-04:00; completed 2026-10-10T00:45:36-04:00; return code 0. Output: `dist/simtest/batch7.out`. CSV: `dist/simtest/20261010T040613Z-results.csv`. Transcript: `dist/simtest/20261010T040613Z-run.log`.
- Batch 8: 20 completed runs; requested 5 per condition; started 2026-10-10T00:45:48-04:00; completed 2026-10-10T01:24:26-04:00; return code 0. Output: `dist/simtest/batch8.out`. CSV: `dist/simtest/20261010T044548Z-results.csv`. Transcript: `dist/simtest/20261010T044548Z-run.log`.
- Batch 9: 20 completed runs; requested 5 per condition; started 2026-10-10T01:24:39-04:00; completed 2026-10-10T02:05:16-04:00; return code 0. Output: `dist/simtest/batch9.out`. CSV: `dist/simtest/20261010T052439Z-results.csv`. Transcript: `dist/simtest/20261010T052439Z-run.log`.
- Batch 10: 20 completed runs; requested 5 per condition; started 2026-10-10T02:05:28-04:00; completed 2026-10-10T02:49:52-04:00; return code 0. Output: `dist/simtest/batch10.out`. CSV: `dist/simtest/20261010T060528Z-results.csv`. Transcript: `dist/simtest/20261010T060528Z-run.log`.
- Batch 11: 20 completed runs; requested 5 per condition; started 2026-10-10T02:50:06-04:00; completed 2026-10-10T03:29:33-04:00; return code 0. Output: `dist/simtest/batch11.out`. CSV: `dist/simtest/20261010T065006Z-results.csv`. Transcript: `dist/simtest/20261010T065006Z-run.log`.
- Batch 12: 20 completed runs; requested 5 per condition; started 2026-10-10T03:29:47-04:00; completed 2026-10-10T04:11:11-04:00; return code 0. Output: `dist/simtest/batch12.out`. CSV: `dist/simtest/20261010T072947Z-results.csv`. Transcript: `dist/simtest/20261010T072947Z-run.log`.
- Batch 13: 20 completed runs; requested 5 per condition; started 2026-10-10T04:11:25-04:00; completed 2026-10-10T04:49:49-04:00; return code 0. Output: `dist/simtest/batch13.out`. CSV: `dist/simtest/20261010T081125Z-results.csv`. Transcript: `dist/simtest/20261010T081125Z-run.log`.
- Batch 14: 20 completed runs; requested 5 per condition; started 2026-10-10T04:50:02-04:00; completed 2026-10-10T05:30:13-04:00; return code 0. Output: `dist/simtest/batch14.out`. CSV: `dist/simtest/20261010T085002Z-results.csv`. Transcript: `dist/simtest/20261010T085002Z-run.log`.
- Batch 15: 20 completed runs; requested 5 per condition; started 2026-10-10T05:30:25-04:00; completed 2026-10-10T06:10:14-04:00; return code 0. Output: `dist/simtest/batch15.out`. CSV: `dist/simtest/20261010T093025Z-results.csv`. Transcript: `dist/simtest/20261010T093025Z-run.log`.
- Batch 16: 20 completed runs; requested 5 per condition; started 2026-10-10T06:10:30-04:00; completed 2026-10-10T06:57:09-04:00; return code 0. Output: `dist/simtest/batch16.out`. CSV: `dist/simtest/20261010T101030Z-results.csv`. Transcript: `dist/simtest/20261010T101030Z-run.log`.
- Batch 17: 4 completed runs; requested 1 per condition; started 2026-10-10T06:57:23-04:00; completed 2026-10-10T07:04:04-04:00; return code 0. Output: `dist/simtest/batch17.out`. CSV: `dist/simtest/20261010T105723Z-results.csv`. Transcript: `dist/simtest/20261010T105723Z-run.log`.
- Batch 18: 4 completed runs; requested 1 per condition; started 2026-10-10T07:04:19-04:00; completed 2026-10-10T07:11:40-04:00; return code 0. Output: `dist/simtest/batch18.out`. CSV: `dist/simtest/20261010T110419Z-results.csv`. Transcript: `dist/simtest/20261010T110419Z-run.log`.
- Batch 19: 0 completed runs; requested 1 per condition; started 2026-10-10T07:11:54-04:00; interrupted pending baseline launch after manual game closure; return code −15. Output: `dist/simtest/batch19.out`. CSV: `dist/simtest/20261010T111154Z-results.csv`. Transcript: `dist/simtest/20261010T111154Z-run.log`.

The native report command was run with explicit batch 4+ comparable CSV paths after every completed batch, and all returned 0. The final independent recheck is `dist/simtest/overnight-report-final.txt`; its explicit CSV inputs are recorded in `dist/simtest/overnight-final-audit.json`. Earlier/calibration CSVs and batch 19’s empty CSV are not included. The table above was independently recomputed from the completed rows, including downed_ever and min–max spreads.

Before each batch, both campaign-load and hub-settled commands printed ok. Only one harness was run at a time; full-batch durations ranged from 38.4 to 46.6 minutes. At 06:57:09, 62.8 minutes remained, below the full estimate of 64.3 minutes, so testing switched to single-round batches (estimate 17.7 minutes). Testing then ended on the human’s early-stop request.

## Cleanup and settings

The remaining harness was stopped by its exact PID 3225671 and the owned scheduler by PID 3105279. No harness or scheduler remains live, and no further batch will start. The game was closed by the human; no attempt was made to launch, restart, or kill the game. Final ai off / speed 1 commands were skipped because it was already closed. The last completed batch ended with successful ai off and speed 1 replies.

`python3 -I tools/simtest.py restore-settings` returned 0 and printed `restored Off Duty's settings`. The simtest backup is gone. No mod code or tools/simtest.py was edited; no pak was built/installed, and nothing was committed or pushed.

**Reminder: check Off Duty in the in-game mod menu after restarting. Your real settings are the Standard preset with AP loss OFF. An earlier backup was lost, so the restored file may not match; set these by hand if needed.**

## Batch summaries (appended after each batch)

### Batch 5

20 recorded rows; 20 valid, 0 excluded. Duration 40.4 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 6.40 (4–11) | 10.00 | 0.80 | 0.80 | 41.10 (15.12–67.70) | 0.00 (0) |
| tired | 5 | 100.0 | 5.00 (3–8) | 10.00 | 0.20 | 0.20 | 31.00 (13.06–55.33) | 0.00 (0) |
| exhausted | 5 | 100.0 | 6.60 (5–10) | 10.00 | 0.80 | 0.80 | 48.12 (36.23–58.70) | 1.80 (9) |
| spent | 5 | 100.0 | 5.20 (4–7) | 10.00 | 0.40 | 0.40 | 32.14 (17.94–53.05) | 2.20 (11) |

### Batch 6

20 recorded rows; 20 valid, 0 excluded. Duration 39.4 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 5.40 (5–6) | 10.00 | 0.20 | 0.20 | 38.14 (29.55–52.58) | 0.00 (0) |
| tired | 5 | 100.0 | 5.60 (3–13) | 10.00 | 0.60 | 0.60 | 27.97 (11.68–62.20) | 0.00 (0) |
| exhausted | 5 | 100.0 | 4.80 (4–5) | 10.00 | 0.20 | 0.20 | 34.35 (32.61–35.51) | 0.80 (4) |
| spent | 5 | 100.0 | 6.40 (5–9) | 10.00 | 1.00 | 1.00 | 47.56 (28.24–70.61) | 2.80 (14) |

### Batch 7

20 recorded rows; 20 valid, 0 excluded. Duration 39.4 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 5.20 (3–7) | 10.00 | 0.80 | 0.80 | 35.74 (17.18–55.33) | 0.00 (0) |
| tired | 5 | 100.0 | 7.40 (4–16) | 10.00 | 0.80 | 0.80 | 39.59 (17.87–64.26) | 0.00 (0) |
| exhausted | 5 | 100.0 | 5.00 (5–5) | 10.00 | 0.00 | 0.00 | 31.59 (22.46–41.30) | 1.00 (5) |
| spent | 5 | 100.0 | 5.40 (4–8) | 10.00 | 0.00 | 0.00 | 28.40 (20.61–38.93) | 2.20 (11) |

### Batch 8

20 recorded rows; 20 valid, 0 excluded. Duration 38.6 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 5.40 (4–8) | 10.00 | 0.20 | 0.20 | 27.56 (16.49–43.64) | 0.00 (0) |
| tired | 5 | 100.0 | 5.60 (4–7) | 10.00 | 1.20 | 1.20 | 40.00 (24.05–68.73) | 0.00 (0) |
| exhausted | 5 | 100.0 | 4.00 (3–5) | 10.00 | 0.20 | 0.20 | 25.80 (10.87–42.03) | 0.80 (4) |
| spent | 5 | 100.0 | 6.40 (5–9) | 10.00 | 1.00 | 1.00 | 46.11 (31.30–56.49) | 3.20 (16) |

### Batch 9

20 recorded rows; 20 valid, 0 excluded. Duration 40.6 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 6.40 (3–8) | 10.00 | 0.80 | 0.80 | 43.44 (22.68–67.01) | 0.00 (0) |
| tired | 5 | 100.0 | 5.40 (5–6) | 10.00 | 0.80 | 0.80 | 39.86 (23.37–51.20) | 0.00 (0) |
| exhausted | 5 | 100.0 | 5.40 (4–8) | 10.00 | 0.60 | 0.60 | 38.26 (18.84–62.32) | 2.40 (12) |
| spent | 5 | 100.0 | 6.80 (5–9) | 10.00 | 0.60 | 0.60 | 42.21 (28.24–72.52) | 2.60 (13) |

### Batch 10

20 recorded rows; 20 valid, 0 excluded. Duration 44.4 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 5.00 (4–8) | 10.00 | 0.20 | 0.20 | 25.09 (13.75–52.58) | 0.00 (0) |
| tired | 5 | 100.0 | 7.20 (5–9) | 10.00 | 0.80 | 0.80 | 40.21 (26.12–63.57) | 0.00 (0) |
| exhausted | 5 | 100.0 | 8.60 (4–11) | 10.00 | 2.00 | 2.00 | 55.00 (32.61–64.49) | 1.60 (8) |
| spent | 5 | 100.0 | 6.00 (4–11) | 10.00 | 0.40 | 0.40 | 27.94 (17.56–49.62) | 1.40 (7) |

### Batch 11

20 recorded rows; 20 valid, 0 excluded. Duration 39.4 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 6.60 (3–13) | 10.00 | 1.00 | 1.00 | 38.21 (17.18–59.45) | 0.00 (0) |
| tired | 5 | 100.0 | 5.00 (3–9) | 10.00 | 0.20 | 0.20 | 28.52 (13.06–58.76) | 0.00 (0) |
| exhausted | 5 | 100.0 | 4.60 (4–5) | 10.00 | 0.20 | 0.20 | 39.71 (25.36–49.28) | 1.60 (8) |
| spent | 5 | 100.0 | 6.00 (5–7) | 10.00 | 0.80 | 0.80 | 34.66 (19.08–58.02) | 1.80 (9) |

### Batch 12

20 recorded rows; 20 valid, 0 excluded. Duration 41.4 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 6.60 (4–10) | 10.00 | 0.80 | 0.80 | 37.80 (19.24–53.26) | 0.00 (0) |
| tired | 5 | 100.0 | 5.40 (4–8) | 10.00 | 0.40 | 0.40 | 37.18 (16.49–61.51) | 0.00 (0) |
| exhausted | 5 | 100.0 | 6.20 (5–7) | 10.00 | 0.20 | 0.20 | 45.80 (17.39–59.42) | 2.00 (10) |
| spent | 5 | 100.0 | 4.40 (3–6) | 10.00 | 0.20 | 0.20 | 31.37 (11.07–56.49) | 0.80 (4) |

### Batch 13

20 recorded rows; 20 valid, 0 excluded. Duration 38.4 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 5.20 (4–6) | 10.00 | 0.00 | 0.00 | 32.71 (22.68–46.05) | 0.00 (0) |
| tired | 5 | 100.0 | 5.00 (5–5) | 10.00 | 0.20 | 0.20 | 26.80 (18.56–39.86) | 0.00 (0) |
| exhausted | 5 | 100.0 | 5.00 (4–6) | 10.00 | 0.20 | 0.20 | 35.07 (22.46–47.83) | 0.20 (1) |
| spent | 5 | 100.0 | 5.40 (3–8) | 10.00 | 1.20 | 1.20 | 41.15 (8.02–63.36) | 2.40 (12) |

### Batch 14

20 recorded rows; 20 valid, 0 excluded. Duration 40.2 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 5.40 (4–8) | 10.00 | 0.20 | 0.20 | 25.50 (2.75–43.99) | 0.00 (0) |
| tired | 5 | 100.0 | 5.40 (4–9) | 10.00 | 0.20 | 0.20 | 30.93 (15.81–43.99) | 0.00 (0) |
| exhausted | 5 | 100.0 | 5.80 (4–9) | 10.00 | 0.60 | 0.60 | 34.49 (17.39–57.97) | 1.20 (6) |
| spent | 5 | 100.0 | 6.60 (4–13) | 10.00 | 1.20 | 1.20 | 46.03 (28.24–66.03) | 2.00 (10) |

### Batch 15

20 recorded rows; 20 valid, 0 excluded. Duration 39.8 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 5.00 (3–8) | 10.00 | 0.60 | 0.60 | 36.77 (18.56–62.89) | 0.00 (0) |
| tired | 5 | 100.0 | 5.80 (4–10) | 10.00 | 0.80 | 0.80 | 39.59 (11.68–67.70) | 0.00 (0) |
| exhausted | 5 | 100.0 | 4.80 (4–5) | 10.00 | 0.00 | 0.00 | 28.84 (24.64–34.78) | 1.00 (5) |
| spent | 5 | 100.0 | 6.40 (5–8) | 10.00 | 0.40 | 0.40 | 37.25 (29.77–51.91) | 3.20 (16) |

### Batch 16

20 recorded rows; 20 valid, 0 excluded. Duration 46.6 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5 | 100.0 | 6.00 (4–10) | 10.00 | 0.20 | 0.20 | 32.92 (17.87–54.64) | 0.00 (0) |
| tired | 5 | 100.0 | 6.60 (3–9) | 10.00 | 0.80 | 0.80 | 39.45 (15.81–53.61) | 0.00 (0) |
| exhausted | 5 | 100.0 | 6.60 (4–9) | 10.00 | 0.80 | 0.80 | 45.65 (22.46–62.32) | 1.00 (5) |
| spent | 5 | 100.0 | 7.20 (5–10) | 10.00 | 1.00 | 1.00 | 45.19 (30.53–61.83) | 2.40 (12) |

### Batch 17

4 recorded rows; 4 valid, 0 excluded. Duration 6.7 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 1 | 100.0 | 3.00 (3–3) | 10.00 | 0.00 | 0.00 | 6.19 (6.19–6.19) | 0.00 (0) |
| tired | 1 | 100.0 | 4.00 (4–4) | 10.00 | 0.00 | 0.00 | 30.93 (30.93–30.93) | 0.00 (0) |
| exhausted | 1 | 100.0 | 5.00 (5–5) | 10.00 | 0.00 | 0.00 | 23.19 (23.19–23.19) | 0.00 (0) |
| spent | 1 | 100.0 | 3.00 (3–3) | 10.00 | 0.00 | 0.00 | 6.11 (6.11–6.11) | 0.00 (0) |

### Batch 18

4 recorded rows; 4 valid, 0 excluded. Duration 7.4 min.

| Condition | Runs | Win % | Rounds mean (min–max) | Kills mean | Downed end mean | Downed ever mean | Health lost % mean (min–max) | AP losses mean (total) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 1 | 100.0 | 7.00 (7–7) | 10.00 | 1.00 | 1.00 | 34.02 (34.02–34.02) | 0.00 (0) |
| tired | 1 | 100.0 | 4.00 (4–4) | 10.00 | 0.00 | 0.00 | 30.93 (30.93–30.93) | 0.00 (0) |
| exhausted | 1 | 100.0 | 5.00 (5–5) | 10.00 | 0.00 | 0.00 | 33.33 (33.33–33.33) | 0.00 (0) |
| spent | 1 | 100.0 | 3.00 (3–3) | 10.00 | 0.00 | 0.00 | 9.92 (9.92–9.92) | 0.00 (0) |

### Batch 19

0 completed runs. Human closed the game during the pending baseline launch; no result row to include.
