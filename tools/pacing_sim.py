#!/usr/bin/env python3
"""Projects the SuperLive queue delay for N lives on ONE egress IP from a trace
measured with a single live.

Input: the JSON-lines trace written by the backend (SUPERLIVE_PACING_LOG_FILE, default
/data/pacing.jsonl on the VPS; rotated files pacing.jsonl.1 ... can be passed too).

How the projection works
  1. Takes the calls recorded for the ONE measured live (when each was queued, its
     priority/type) and its call-time distribution L.
  2. Builds N lives by replaying that same pattern N times, each rotated by a random
     offset so they are not artificially in sync (`--sync` keeps them aligned: the
     worst case of every live being raided at the same moment).
  3. Gives every call a service time drawn from the MEASURED L of its class.
  4. Runs them through a model of the dispatcher (one call in flight, spacing between
     calls, 3 s between chat messages, urgent mute/kick first) for several variants
     and many random seeds, and reports wait percentiles with the spread across seeds.

What it does NOT know: how L and SuperLive's 429s change when the load grows. A
projection whose offered rate is above 1/(L + spacing) says "this IP cannot sustain
that"; a clean projection says "no queueing problem", not "no 429". Treat the offered
request rate as the number to watch.

Usage:
  python tools/pacing_sim.py pacing.jsonl --lives 25
  python tools/pacing_sim.py pacing.jsonl* --lives 25 --runs 30 --sync
"""
from __future__ import annotations

import argparse
import glob
import heapq
import json
import random
import statistics
import sys

URGENT = 0
MESSAGE_PATH = "livestream/chat/send_text_message"

# name -> (urgent steps aside for nothing / waiting items yield, spacing from start)
MODES = {
    "legacy": {"yield_to_urgent": False, "from_start": False},
    "urgent_first": {"yield_to_urgent": True, "from_start": False},
    "urgent_first_from_start": {"yield_to_urgent": True, "from_start": True},
    # a chat message waiting out its 3 s gap lets ANY other ready call go first (own lane)
    "lanes": {"yield_to_urgent": True, "from_start": False, "lanes": True},
    "lanes_from_start": {"yield_to_urgent": True, "from_start": True, "lanes": True},
}


# ----------------------------------------------------------------------------- trace
def load_trace(paths):
    calls = []
    for pattern in paths:
        for path in sorted(glob.glob(pattern)) or [pattern]:
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        row = json.loads(line)
                    except ValueError:
                        continue
                    if "ev" in row or "te" not in row or "L" not in row:
                        continue
                    calls.append(row)
    calls.sort(key=lambda r: r["te"])
    return calls


def klass(row) -> str:
    if row["prio"] <= URGENT:
        return "urgent"
    if row["path"] == MESSAGE_PATH:
        return "message"
    return "other"


def percentile(values, q):
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, round(q * (len(ordered) - 1))))]


def describe_trace(calls):
    t0, t1 = calls[0]["te"], calls[-1]["te"]
    minutes = max((t1 - t0) / 60.0, 1e-9)
    out = {"calls": len(calls), "minutes": round(minutes, 1), "by_class": {}}
    for name in ("urgent", "message", "other"):
        rows = [r for r in calls if klass(r) == name]
        ls = [r["L"] for r in rows]
        out["by_class"][name] = {
            "n": len(rows), "per_min": round(len(rows) / minutes, 2),
            "L_p50": round(percentile(ls, 0.5), 3), "L_p95": round(percentile(ls, 0.95), 3),
        }
    out["errors"] = sum(1 for r in calls if r.get("out") not in (None, "ok"))
    out["throttled_429"] = sum(1 for r in calls if r.get("out") == "429")
    return out


# ------------------------------------------------------------------------ simulation
def build_arrivals(calls, lives, rng, sync):
    """[(time, prio, is_message, L)] for N lives built from the single measured one."""
    t0 = calls[0]["te"]
    span = max(calls[-1]["te"] - t0, 1.0)
    pools = {name: [r["L"] for r in calls if klass(r) == name] for name in ("urgent", "message", "other")}
    arrivals = []
    for _ in range(lives):
        offset = 0.0 if sync else rng.uniform(0, span)
        for r in calls:
            t = ((r["te"] - t0) + offset) % span
            name = klass(r)
            arrivals.append((t, r["prio"], name == "message", rng.choice(pools[name])))
    arrivals.sort(key=lambda a: a[0])
    return arrivals, span


def simulate(arrivals, mode, spacing, msg_spacing):
    """One call in flight; same rules as superlive._dispatcher."""
    cfg = MODES[mode]
    n = len(arrivals)
    i = 0
    heap = []
    seq = 0
    now = 0.0
    last_any = -1e9
    last_msg = -1e9
    waits = {"urgent": [], "message": [], "other": []}
    demand = 0.0   # time the calls would occupy a serial line: sum of their cycles
    max_queue = 0
    urgent_times = [a[0] for a in arrivals if a[1] <= URGENT]
    import bisect
    while i < n or heap:
        if not heap and i < n and arrivals[i][0] > now:
            now = arrivals[i][0]
        while i < n and arrivals[i][0] <= now:
            t, prio, is_msg, L = arrivals[i]
            heapq.heappush(heap, (prio, seq, t, is_msg, L))
            seq += 1
            i += 1
        max_queue = max(max_queue, len(heap))
        item = heapq.heappop(heap)
        prio, _s, t_arr, is_msg, L = item
        ready = max(now, last_any + spacing)
        if is_msg and prio > URGENT:
            ready = max(ready, last_msg + msg_spacing)
        if prio > URGENT and ready > now and cfg["yield_to_urgent"]:
            k = bisect.bisect_right(urgent_times, now)
            if k < len(urgent_times) and urgent_times[k] < ready:
                now = urgent_times[k]                 # an urgent call showed up: step aside
                heapq.heappush(heap, item)
                continue
        now = max(now, ready)
        start = now
        finish = start + L
        demand += max(L, spacing) if cfg["from_start"] else L + spacing
        name = "urgent" if prio <= URGENT else ("message" if is_msg else "other")
        waits[name].append(start - t_arr)
        last_any = start if cfg["from_start"] else finish
        if is_msg:
            last_msg = finish
        now = finish
    return waits, demand, now, max_queue


def simulate_lanes(arrivals, from_start, spacing, msg_spacing):
    """Same rules as simulate(), but chat messages wait in their own lane: while one is
    waiting out its gap, the line serves other ready calls (polls etc.) instead of idling."""
    import collections
    n = len(arrivals)
    i = 0
    urgent, other, msgs = [], [], collections.deque()
    seq = 0
    now = 0.0
    last_any = -1e9
    last_msg = -1e9
    waits = {"urgent": [], "message": [], "other": []}
    demand = 0.0
    max_queue = 0
    INF = float("inf")
    while i < n or urgent or other or msgs:
        while i < n and arrivals[i][0] <= now:
            t, prio, is_msg, L = arrivals[i]
            if prio <= URGENT:
                heapq.heappush(urgent, (seq, t, L))
            elif is_msg:
                msgs.append((t, L))
            else:
                heapq.heappush(other, (prio, seq, t, L))
            seq += 1
            i += 1
        max_queue = max(max_queue, len(urgent) + len(other) + len(msgs))
        if not (urgent or other or msgs):
            now = max(now, arrivals[i][0])
            continue
        base = max(now, last_any + spacing)
        if urgent:
            kind, start = "urgent", base
        else:
            t_msg = max(base, last_msg + msg_spacing) if msgs else INF
            t_oth = base if other else INF
            kind, start = ("message", t_msg) if t_msg <= t_oth else ("other", t_oth)
        # something may arrive before this call can start and change the choice
        if i < n and arrivals[i][0] < start:
            now = arrivals[i][0]
            continue
        if kind == "urgent":
            _s, t_arr, L = heapq.heappop(urgent)
        elif kind == "message":
            t_arr, L = msgs.popleft()
        else:
            _p, _s, t_arr, L = heapq.heappop(other)
        waits[kind].append(start - t_arr)
        finish = start + L
        demand += max(L, spacing) if from_start else L + spacing
        last_any = start if from_start else finish
        if kind == "message":
            last_msg = finish
        now = finish
    return waits, demand, now, max_queue


def run_all(calls, lives, runs, seed, spacing, msg_spacing, modes, sync):
    results = {m: {"urgent": [], "message": [], "other": [], "util": [], "maxq": []} for m in modes}
    offered = []
    for r in range(runs):
        rng = random.Random(seed + r)
        arrivals, span = build_arrivals(calls, lives, rng, sync)
        offered.append(len(arrivals) / span)
        for m in modes:
            if MODES[m].get("lanes"):
                waits, demand, _end, maxq = simulate_lanes(arrivals, MODES[m]["from_start"], spacing, msg_spacing)
            else:
                waits, demand, _end, maxq = simulate(arrivals, m, spacing, msg_spacing)
            for name in ("urgent", "message", "other"):
                results[m][name].append(waits[name])
            results[m]["util"].append(demand / span)
            results[m]["maxq"].append(maxq)
    return results, statistics.mean(offered)


def summarize(per_run, q):
    vals = [percentile(w, q) for w in per_run if w]
    if not vals:
        return None
    return statistics.mean(vals), (min(vals), max(vals))


def fmt(v):
    return "   -   " if v is None else f"{v[0]:6.2f}s ({v[1][0]:.1f}-{v[1][1]:.1f})"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("trace", nargs="+", help="pacing.jsonl (rotated files and globs accepted)")
    ap.add_argument("--lives", type=int, default=25)
    ap.add_argument("--runs", type=int, default=20, help="random seeds (spread shown as min-max)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--spacing", type=float, default=0.35, help="SUPERLIVE_REQUEST_SPACING")
    ap.add_argument("--msg-spacing", type=float, default=3.0, help="SUPERLIVE_MESSAGE_SPACING_SECONDS")
    ap.add_argument("--modes", default=",".join(MODES))
    ap.add_argument("--sync", action="store_true", help="all lives hit at the same instants (worst case)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    calls = load_trace(args.trace)
    if len(calls) < 20:
        print(f"Poucos dados ({len(calls)} chamadas): colete mais antes de projetar.", file=sys.stderr)
        return 2
    modes = [m.strip() for m in args.modes.split(",") if m.strip()]
    for m in modes:
        if m not in MODES:
            print(f"modo desconhecido: {m} (use {', '.join(MODES)})", file=sys.stderr)
            return 2

    base = describe_trace(calls)
    results, offered = run_all(calls, args.lives, args.runs, args.seed, args.spacing, args.msg_spacing,
                               modes, args.sync)
    l_all = [r["L"] for r in calls]
    capacity = 1.0 / (statistics.median(l_all) + args.spacing)
    report = {"measured_one_live": base, "lives": args.lives, "offered_calls_per_s": round(offered, 3),
              "serial_capacity_calls_per_s": round(capacity, 3), "modes": {}}
    for m in modes:
        rep = {}
        for name in ("urgent", "message", "other"):
            rep[name] = {f"p{int(q * 100)}": (summarize(results[m][name], q) or (None,))[0]
                         for q in (0.5, 0.95, 0.99)}
            rep[name]["max"] = (max((max(w) for w in results[m][name] if w), default=None))
        rep["utilization"] = round(statistics.mean(results[m]["util"]), 2)
        rep["max_queue"] = max(results[m]["maxq"])
        report["modes"][m] = rep

    if args.json:
        print(json.dumps(report, indent=2))
        return 0

    print(f"Medido com 1 live: {base['calls']} chamadas em {base['minutes']} min "
          f"(erros: {base['errors']}, 429: {base['throttled_429']})")
    for name, d in base["by_class"].items():
        print(f"  {name:8s} {d['n']:5d} chamadas, {d['per_min']:6.2f}/min, L p50/p95 = {d['L_p50']}/{d['L_p95']} s")
    print(f"\nProjecao: {args.lives} lives no MESMO IP{' (sincronizadas)' if args.sync else ''}, "
          f"{args.runs} sorteios")
    print(f"  carga oferecida: {offered:.2f} chamadas/s | capacidade serial ~ {capacity:.2f} chamadas/s "
          f"(1/(L p50 + {args.spacing}))")
    if offered > capacity:
        print("  ATENCAO: a carga oferecida passa da capacidade serial: a fila cresce sem parar.")
    print("\nEspera na fila (media dos sorteios; entre parenteses: menor-maior sorteio)")
    header = f"{'modo':26s} {'urgente p50':>20s} {'urgente p95':>20s} {'urgente p99':>20s} {'mensagem p95':>20s} {'carga':>6s} {'fila max':>8s}"
    print(header)
    for m in modes:
        u50 = summarize(results[m]["urgent"], 0.5)
        u95 = summarize(results[m]["urgent"], 0.95)
        u99 = summarize(results[m]["urgent"], 0.99)
        m95 = summarize(results[m]["message"], 0.95)
        rho = report["modes"][m]["utilization"]
        print(f"{m:26s} {fmt(u50):>20s} {fmt(u95):>20s} {fmt(u99):>20s} {fmt(m95):>20s} "
              f"{rho:5.2f}{'*' if rho > 1 else ' '} {report['modes'][m]['max_queue']:8d}")
    print("\ncarga = tempo que as chamadas ocupariam a fila / tempo disponivel. Acima de 1 (*) o IP satura:")
    print("as esperas acima crescem com o tempo medido e nao sao um valor estavel.")
    print("Limites: nao modela mudanca de L nem 429 sob mais carga. Use a carga oferecida como alerta.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
