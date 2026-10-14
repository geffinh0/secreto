import json
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools"))

import pacing_sim  # noqa: E402

MSG = pacing_sim.MESSAGE_PATH


class SimulatorModelTests(unittest.TestCase):
    """The model must agree with the real dispatcher on the rules that matter."""

    def _head_of_line_case(self, mode):
        # t=0 message goes out (done 0.5); the 2nd message arrives at t=1.0 with the line
        # idle, so it is taken at once and must sleep until 3 s after the first; a mute
        # arrives at t=1.2 while that message is waiting
        arrivals = [(0.0, 5, True, 0.5), (1.0, 5, True, 0.5), (1.2, 0, False, 0.5)]
        waits, *_ = pacing_sim.simulate(arrivals, mode, spacing=0.35, msg_spacing=3.0)
        return waits["urgent"][0]

    def test_legacy_makes_the_mute_wait_for_the_message_window(self):
        self.assertGreater(self._head_of_line_case("legacy"), 2.5)

    def test_urgent_first_serves_the_mute_right_away(self):
        self.assertLess(self._head_of_line_case("urgent_first"), 1.0)

    def test_message_spacing_is_still_honoured(self):
        arrivals = [(0.0, 5, True, 0.1), (0.0, 5, True, 0.1)]
        waits, *_ = pacing_sim.simulate(arrivals, "urgent_first", spacing=0.35, msg_spacing=3.0)
        self.assertGreaterEqual(max(waits["message"]), 3.0)

    def test_from_start_shortens_the_cycle_without_overlapping(self):
        arrivals = [(0.0, 0, False, 1.0)] * 4
        legacy, _b, end_legacy, _q = pacing_sim.simulate(arrivals, "legacy", 0.35, 3.0)
        fast, _b, end_fast, _q = pacing_sim.simulate(arrivals, "urgent_first_from_start", 0.35, 3.0)
        self.assertAlmostEqual(end_legacy, 1.0 + 3 * (1.0 + 0.35), places=6)   # L + spacing each
        self.assertAlmostEqual(end_fast, 4 * 1.0, places=6)                    # max(L, spacing) each


class SimulatorCliTests(unittest.TestCase):
    def _trace(self, minutes=20):
        rng = random.Random(7)
        rows, t = [], 1_700_000_000.0
        end = t + minutes * 60
        while t < end:
            rows.append({"te": t, "t": t, "prio": 9, "path": "users/profile", "L": 0.5 + rng.random() * 0.3,
                         "out": "ok"})
            t += 30
        t = 1_700_000_000.0 + 5
        while t < end:
            rows.append({"te": t, "t": t, "prio": 5, "path": MSG, "L": 0.6, "out": "ok"})
            t += 120
        t = 1_700_000_000.0 + 20
        while t < end:
            rows.append({"te": t, "t": t, "prio": 0, "path": "mute", "L": 0.5 + rng.random() * 0.4, "out": "ok"})
            t += rng.uniform(5, 40)
        rows.append({"ev": "cooldown", "t": t, "pause": 2})
        return rows

    def test_projection_runs_and_reports_urgent_waits(self):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False, encoding="utf-8") as fh:
            for r in self._trace():
                fh.write(json.dumps(r) + "\n")
            path = fh.name
        self.addCleanup(os.remove, path)
        calls = pacing_sim.load_trace([path])
        self.assertTrue(all("ev" not in c for c in calls))
        results, offered = pacing_sim.run_all(calls, lives=25, runs=3, seed=1, spacing=0.35,
                                              msg_spacing=3.0, modes=list(pacing_sim.MODES), sync=False)
        self.assertGreater(offered, 0)
        legacy_p95 = pacing_sim.summarize(results["legacy"]["urgent"], 0.95)[0]
        new_p95 = pacing_sim.summarize(results["urgent_first"]["urgent"], 0.95)[0]
        self.assertLessEqual(new_p95, legacy_p95)
        self.assertEqual(pacing_sim.main([path, "--lives", "25", "--runs", "2", "--json"]), 0)

    def test_too_little_data_is_refused(self):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False, encoding="utf-8") as fh:
            fh.write(json.dumps({"te": 1.0, "t": 1.0, "prio": 0, "path": "mute", "L": 0.5, "out": "ok"}) + "\n")
            path = fh.name
        self.addCleanup(os.remove, path)
        self.assertEqual(pacing_sim.main([path]), 2)


if __name__ == "__main__":
    unittest.main()
