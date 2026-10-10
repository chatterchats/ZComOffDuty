#!/usr/bin/env python3
"""Off Duty simulation tests: the game's own AI plays the squad, with and without fatigue tiers.

Drives "ZC Unlocked - Sandbox Mode" (ue4ss/Mods/ZCSandbox) through its command file: append
`#<id> <command>` to cmd.txt, read `<id> <status> <verb> | <text>` from reply.txt (see its AUTOMATION.txt).
Everything runs in the sandbox's own forked campaign; the sandbox refuses changes anywhere else.

Each run: `campaign reset` (the baseline Den: no injuries or fatigue carried between runs), launch the
mission with a fixed squad and enemy spawn set, apply the condition's tier to every squad member
(`ge`: Off Duty's tier effect plus the game's accuracy stacks), `ai on` + `speed`, then poll until one
side is gone or the turn cap is reached. Results go to dist/simtest/<time>.csv with a raw transcript.

    tools/simtest.py info                          sandbox status, roster, units, missions, spawn sets
    tools/simtest.py send "<command>"              one raw command (prints the reply)
    tools/simtest.py report [results.csv ...]       per-condition summary (default: all of dist/simtest)
    tools/simtest.py run --mission SK_X --enemies SS_Y --squad "A,B,C,D" \\
        --conditions baseline,tired,exhausted,spent --runs 5 --turn-cap 15 --speed 4

Keep Off Duty's own loop out of the way during runs: set "Fatigue per mission" to 0 in MXM (the harness
applies tiers itself), or pass --neutralise to write that into Off Duty's MXM values for the session.
"""
import argparse
import csv
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("SWZC_GAME_WIN64", "/run/media/chats/e0057d4a-fe46-43eb-a837-db51979c500f/Games/"
                           "STAR WARS Zero Company (2026)/Star Wars Zero Company/SWZeroCompany/Binaries/Win64"))
SANDBOX = GAME / "ue4ss" / "Mods" / "ZCSandbox"
OFFDUTY_LOG = ROOT / "src" / "OffDuty" / "off_duty.log"
MXM_VALUES = ROOT / "src" / "OffDuty" / "MXM" / "values.lua"

EFFECTS = "/Game/OffDuty/Effects/"
ACCURACY = ("/Game/Game/GameData/Progression/NextMissionGameplayEffects/"
            "GE_Lose_NextMission_RangedAccuracy.GE_Lose_NextMission_RangedAccuracy_C")
# Condition -> (Off Duty tier effect, accuracy stacks). Mirrors src/OffDuty/Scripts/rules.lua.
CONDITIONS = {
    "baseline": (None, 0),
    "tired": ("GE_OffDuty_Tired", 1),
    "exhausted": ("GE_OffDuty_Exhausted", 2),
    "spent": ("GE_OffDuty_Spent", 3),
}


class SandboxError(RuntimeError):
    pass


class Sandbox:
    """cmd.txt / reply.txt client. Ids are unique per process (prefix + counter)."""

    def __init__(self, folder=SANDBOX, transcript=None):
        self.cmd = Path(folder) / "cmd.txt"
        self.reply = Path(folder) / "reply.txt"
        self.prefix = "st%d" % (os.getpid() % 100000)
        self.counter = 0
        self.transcript = transcript

    def hello(self):
        try:
            first = self.reply.read_text(errors="replace").splitlines()[0]
        except (OSError, IndexError):
            return None
        return first if first.startswith("hello ok session") else None

    def log(self, text):
        if self.transcript:
            self.transcript.write(text + "\n")
            self.transcript.flush()

    def send(self, line, timeout=None):
        """Send one command; return (status, text). Waits for the reply carrying our id."""
        self.counter += 1
        rid = "%sn%d" % (self.prefix, self.counter)
        if timeout is None:
            m = re.search(r"\btimeout=(\d+)", line)
            timeout = (int(m.group(1)) / 1000 if m else 30) + 10
        # Replace cmd.txt with just this line. Under Proton the sandbox sees every write from Linux as the file
        # being replaced and re-reads it "from the top": with appends that replayed the whole history (old
        # launches, long waits) on every command. A one-line file means the top is only this command.
        with open(self.cmd, "w", newline="\r\n") as f:
            f.write("#%s %s\n" % (rid, line))
        self.log("> " + line)
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                for raw in self.reply.read_text(errors="replace").splitlines():
                    if raw.startswith(rid + " "):
                        rest = raw[len(rid) + 1:]
                        status = rest.split(" ", 1)[0]
                        text = rest.split("|", 1)[1].strip() if "|" in rest else rest
                        self.log("< %s %s" % (status, text))
                        return status, text
            except OSError:
                pass
            time.sleep(0.25)
        self.log("< timeout")
        raise SandboxError("no reply to %r within %ds" % (line, timeout))

    def ok(self, line, timeout=None):
        status, text = self.send(line, timeout)
        if status != "ok":
            raise SandboxError("%s: %s | %s" % (line, status, text))
        return text


def open_transcript(name):
    out = ROOT / "dist" / "simtest"
    out.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return out, stamp, open(out / ("%s-%s.log" % (stamp, name)), "w")


def require_session(sb):
    hello = sb.hello()
    if not hello:
        sys.exit("No sandbox session: is the game running with ZCSandbox? (no hello line in %s)" % sb.reply)
    return hello


# ---- reading the game (formats confirmed against `info` output) ----------------------------------------

def count_foes(text):
    """`foes`: '11 living enemies: e1 ...' (confirmed in game)."""
    m = re.search(r"(\d+) living enem", text)
    if m:
        return int(m.group(1))
    return 0 if re.search(r"\bno living\b|\bnone\b", text, re.I) else None


def foe_entries(text):
    """`foes` entries: [(selector 'e3', actor name 'Char_Enemy_Separatist_B1_C_2', label 'B1 Battle Droid')]."""
    return [(sel, actor, label.strip())
            for sel, label, actor in re.findall(r"\b(e\d+) ([^\[;]+?) \[([^\]]+)\]", text)]


def squad_health(sb):
    """[health per squad unit] from `units` (count) and `stats <n> Health` ('...HealthSet.Health=88')."""
    status, text = sb.send("units")
    m = re.search(r"(\d+) units", text) if status == "ok" else None
    healths = []
    for n in range(1, (int(m.group(1)) if m else 0) + 1):
        status, text = sb.send("stats %d Health" % n)
        h = re.search(r"HealthSet\.Health=([\d.]+)", text) if status == "ok" else None
        healths.append(float(h.group(1)) if h else 0.0)
    return healths


def downed_since(offset):
    """From Off Duty's 'Squad | <name> downed/revived' lines: (downed at the end, ever downed). Downed
    operators keep some health, so health alone can't tell."""
    state, ever = {}, set()
    try:
        with open(OFFDUTY_LOG, errors="replace") as f:
            f.seek(offset)
            for line in f:
                m = re.search(r"Squad \| (.+) (downed|revived)\s*$", line)
                if m:
                    state[m.group(1)] = m.group(2) == "downed"
                    if m.group(2) == "downed":
                        ever.add(m.group(1))
    except OSError:
        pass
    return sum(1 for v in state.values() if v), len(ever)


def mission_status(sb):
    """The mission actor's MissionStatus: 'Active', 'Succeeded', 'Failed' ... (confirmed: 'Failed' after a wipe).
    A wiped squad doesn't read as 0 health: after the mission ends the units report restored characters."""
    status, _ = sb.send("actors /Script/BitReactorGame.BRGameMissionActor")
    if status != "ok":
        return None
    status, text = sb.send("get @last MissionStatus")
    m = re.search(r"MissionStatus\s*=\s*(\w+)", text) if status == "ok" else None
    return m.group(1) if m else None


def log_lines_since(offset, needle):
    """Off Duty log lines containing `needle` written after `offset` (rounds, AP losses)."""
    try:
        with open(OFFDUTY_LOG, errors="replace") as f:
            f.seek(offset)
            return sum(1 for line in f if needle in line)
    except OSError:
        return 0


def log_size():
    try:
        return OFFDUTY_LOG.stat().st_size
    except OSError:
        return 0


# ---- commands --------------------------------------------------------------------------------------------

def cmd_info(args):
    out, stamp, transcript = open_transcript("info")
    sb = Sandbox(transcript=transcript)
    print(require_session(sb))
    for line in ["status", "campaign status", "roster", "units", "missions " + (args.filter or ""),
                 "spawnsets " + (args.filter or "")]:
        status, text = sb.send(line.strip())
        print("\n### %s -> %s\n%s" % (line, status, text))
    print("\n(transcript: %s)" % transcript.name)


def cmd_send(args):
    sb = Sandbox()
    require_session(sb)
    status, text = sb.send(args.line, args.timeout)
    print(status, "|", text)
    return 0 if status == "ok" else 1


MXM_BACKUP = MXM_VALUES.with_name("values.lua.simtest-backup")
NO_VALUES = "-- simtest: there was no values.lua\n"


def neutralise_offduty():
    """Off Duty's fatigue gain 0 for the session (the harness applies tiers itself). The player's own settings
    are kept in a backup file on disk, so an interrupted run can't lose them (an existing backup is kept)."""
    if not MXM_BACKUP.exists():
        MXM_BACKUP.write_text(MXM_VALUES.read_text() if MXM_VALUES.exists() else NO_VALUES)
    MXM_VALUES.parent.mkdir(parents=True, exist_ok=True)
    # No fatigue gain between runs (the harness applies tiers itself); AP loss on (it's part of the test).
    MXM_VALUES.write_text("return {\n    fatigue_per_mission = 0,\n    ap_loss = true,\n}\n")


def restore_offduty():
    if not MXM_BACKUP.exists():
        return False
    saved = MXM_BACKUP.read_text()
    if saved == NO_VALUES:
        MXM_VALUES.unlink(missing_ok=True)
    else:
        MXM_VALUES.write_text(saved)
    MXM_BACKUP.unlink()
    return True


def cmd_restore_settings(args):
    print("restored Off Duty's settings" if restore_offduty() else "no simtest backup: nothing to restore")


def apply_condition(sb, condition, size):
    effect, stacks = CONDITIONS[condition]
    for n in range(1, size + 1):
        if effect:
            sb.ok("ge %d %s%s.%s_C wait=1" % (n, EFFECTS, effect, effect), timeout=60)
        for _ in range(stacks):
            sb.ok("ge %d %s wait=1" % (n, ACCURACY), timeout=60)


def one_run(sb, args, condition, run_index):
    squad = [s.strip() for s in args.squad.split(",") if s.strip()]
    # `ai on` and `speed` persist across missions: start every run with the squad in our hands, so setup
    # (trimming enemies, applying tiers) happens on the player's turn, a "safe moment" for the sandbox.
    sb.send("ai off")
    sb.send("speed 1")
    sb.ok("campaign reset", timeout=300)
    sb.ok("wait phase=hub settled=1 timeout=240000")
    sb.ok('mission launch %s squad="%s" enemies=%s' % (args.mission, ",".join(squad), args.enemies), timeout=120)
    log_offset = log_size()
    sb.ok("wait phase=mission settled=1 timeout=300000")
    apply_condition(sb, condition, len(squad))
    start_health = squad_health(sb)
    status, text = sb.send("foes")
    if args.keep is not None:
        # Same fight every run: remove all but `keep` enemies, the strongest kinds first (B1s are kept last).
        entries = foe_entries(text)
        entries.sort(key=lambda e: (e[2] == "B1 Battle Droid", e[0]))
        # By actor name: the e-numbers are renumbered after every kill.
        for _, actor, _ in entries[:max(0, len(entries) - args.keep)]:
            sb.send("kill %s wait=1" % actor, timeout=60)
        status, text = sb.send("foes")
    start_foes = count_foes(text)
    seen = {actor for _, actor, _ in foe_entries(text)}
    starting = set(seen)  # the fight's own enemies; with --no-reinforcements anyone else is removed
    removed = 0
    sb.ok("speed %s" % args.speed)
    sb.ok("ai camera off")
    start = time.time()
    result, foes, health = "timeout", start_foes, start_health
    living = set(seen)

    def ended():
        state = mission_status(sb)
        return {"Failed": "loss", "Succeeded": "win"}.get(state)

    def give_turn_to_ai():
        # `ai on` plays the current player turn; `ai off` straight after takes effect from the NEXT player turn,
        # which then waits for input: a guaranteed safe moment for the harness at every round start.
        sb.ok("ai on")
        if args.no_reinforcements:
            sb.ok("ai off")

    def check_enemies():
        """Read the enemies; with --no-reinforcements, remove arrivals (call only on a paused player turn)."""
        nonlocal foes, seen, living, removed
        status, text = sb.send("foes")
        if status != "ok":
            return
        entries = foe_entries(text)
        if args.no_reinforcements:
            for actor in [a for _, a, _ in entries if a not in starting]:
                k_status, _ = sb.send("kill %s wait=1 timeout=60000" % actor, timeout=80)
                if k_status == "ok":
                    removed += 1
            entries = [e for e in entries if e[1] in starting]
        foes = len(entries) if args.no_reinforcements else count_foes(text)
        seen |= {actor for _, actor, _ in entries}
        living = {actor for _, actor, _ in entries}

    give_turn_to_ai()
    rounds_seen = log_lines_since(log_offset, "Round ")
    last_poll = 0.0
    while time.time() - start < args.wall_cap:
        time.sleep(1.0)
        rounds = log_lines_since(log_offset, "Round ")
        new_round = rounds > rounds_seen
        if not new_round and time.time() - last_poll < args.poll:
            continue
        last_poll = time.time()
        outcome = ended()
        if outcome:
            result = outcome; break
        # Only read the squad and enemies while the mission is live (afterwards they read as restored).
        if new_round or not args.no_reinforcements:
            check_enemies()
        reading = squad_health(sb)
        outcome = ended()
        if outcome:
            result = outcome; break
        health = reading or health
        if foes == 0:
            result = "win"; break
        if rounds > args.turn_cap:
            result = "turn cap"; break
        if new_round:
            rounds_seen = rounds
            if args.no_reinforcements:
                give_turn_to_ai()  # the paused turn goes to the AI; the next one pauses again
    row = {
        "condition": condition, "run": run_index, "mission": args.mission, "enemies": args.enemies,
        "result": result, "rounds": log_lines_since(log_offset, "Round "),
        "foes_start": start_foes, "foes_left": foes, "foes_seen": len(seen),
        "kills": len(seen - living) if result != "win" else len(seen),
        "reinforcements_removed": removed,
        "squad_size": len(squad), "squad_alive": len(squad) - downed_since(log_offset)[0],
        "downed_end": downed_since(log_offset)[0], "downed_ever": downed_since(log_offset)[1],
        "health_start": round(sum(start_health)), "health_end": round(sum(max(h, 0) for h in health)),
        "ap_losses": log_lines_since(log_offset, "AP loss |"), "seconds": round(time.time() - start),
    }
    return row


def cmd_run(args):
    for c in args.conditions.split(","):
        if c not in CONDITIONS:
            sys.exit("unknown condition %r (have %s)" % (c, ", ".join(CONDITIONS)))
    out, stamp, transcript = open_transcript("run")
    sb = Sandbox(transcript=transcript)
    print(require_session(sb))
    if args.neutralise:
        neutralise_offduty()
    csv_path = out / ("%s-results.csv" % stamp)
    try:
        with open(csv_path, "w", newline="") as f:
            writer = None
            for run_index in range(1, args.runs + 1):
                for condition in args.conditions.split(","):
                    print("run %d/%d | %s ..." % (run_index, args.runs, condition), flush=True)
                    try:
                        row = one_run(sb, args, condition, run_index)
                    except SandboxError as error:
                        print("  ERROR: %s" % error)
                        row = {"condition": condition, "run": run_index, "result": "error: %s" % error}
                    finally:
                        for line in ("ai off", "speed 1"):
                            try:
                                sb.send(line)
                            except SandboxError:
                                pass
                    print("  %s" % row)
                    if writer is None:
                        writer = csv.DictWriter(f, fieldnames=list(row.keys()) + ["error"], extrasaction="ignore")
                        writer.writeheader()
                    writer.writerow(row)
                    f.flush()
    finally:
        if args.neutralise:
            restore_offduty()
    print("results: %s\ntranscript: %s" % (csv_path, transcript.name))


def cmd_report(args):
    """Per-condition summary of one or more results CSVs (default: every file in dist/simtest)."""
    files = [Path(f) for f in args.files] or sorted((ROOT / "dist" / "simtest").glob("*-results.csv"))
    rows = []
    for path in files:
        with open(path, newline="") as f:
            rows += [r for r in csv.DictReader(f) if r.get("result") in ("win", "loss", "turn cap", "timeout")]
    if not rows:
        sys.exit("no finished runs in %s" % ", ".join(map(str, files)) if files else "no results files")

    def mean(values):
        values = [float(v) for v in values if v not in (None, "")]
        return sum(values) / len(values) if values else float("nan")

    print("%-10s %4s %6s %7s %6s %7s %8s %9s %7s" % ("condition", "runs", "win %", "rounds", "kills", "downed",
                                                        "alive", "hp lost%", "AP lost"))
    order = [c for c in CONDITIONS if any(r["condition"] == c for r in rows)]
    for condition in order:
        group = [r for r in rows if r["condition"] == condition]
        wins = sum(1 for r in group if r["result"] == "win")
        lost = [1 - float(r["health_end"]) / float(r["health_start"]) for r in group
                if r.get("health_start") not in (None, "", "0")]
        print("%-10s %4d %5.0f%% %7.1f %6.1f %7.2f %8.2f %8.0f%% %7.1f" % (
            condition, len(group), 100.0 * wins / len(group), mean(r.get("rounds") for r in group),
            mean(r.get("kills") for r in group), mean(r.get("downed_ever") for r in group),
            mean(r.get("squad_alive") for r in group), 100.0 * mean(lost), mean(r.get("ap_losses") for r in group)))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("info"); p.add_argument("filter", nargs="?", default="")
    p.set_defaults(func=cmd_info)
    p = sub.add_parser("send"); p.add_argument("line"); p.add_argument("--timeout", type=float, default=None)
    p.set_defaults(func=cmd_send)
    p = sub.add_parser("restore-settings", help="put Off Duty's MXM settings back after an interrupted run")
    p.set_defaults(func=cmd_restore_settings)
    p = sub.add_parser("report"); p.add_argument("files", nargs="*")
    p.set_defaults(func=cmd_report)
    p = sub.add_parser("run")
    p.add_argument("--mission", required=True); p.add_argument("--enemies", required=True)
    p.add_argument("--squad", required=True, help="comma-separated roster names")
    p.add_argument("--conditions", default="baseline,tired,exhausted,spent")
    p.add_argument("--runs", type=int, default=3)
    p.add_argument("--turn-cap", type=int, default=15)
    p.add_argument("--wall-cap", type=float, default=1800, help="seconds per mission before giving up")
    p.add_argument("--poll", type=float, default=5.0)
    p.add_argument("--speed", default="4")
    p.add_argument("--keep", type=int, default=None, help="enemies to keep at the start (the rest are removed)")
    p.add_argument("--no-reinforcements", action="store_true",
                   help="remove enemies that arrive after the start (same-sized fight every run)")
    p.add_argument("--neutralise", action="store_true", help="set Off Duty's fatigue gain to 0 during the runs")
    p.set_defaults(func=cmd_run)
    args = parser.parse_args()
    return args.func(args) or 0


if __name__ == "__main__":
    sys.exit(main())
