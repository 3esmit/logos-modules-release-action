"""Unit tests for build_index.py — the brittle parsing/retry bits.

Run: python3 -m unittest discover -s scripts -p 'test_*.py'

Kept dependency-free (stdlib unittest) so CI needs no pip install.
build_index.py guards its entrypoint with `if __name__ == "__main__"`,
so importing it here has no side effects.
"""

import importlib.util
import pathlib
import unittest

_SPEC = importlib.util.spec_from_file_location(
    "build_index", pathlib.Path(__file__).with_name("build_index.py")
)
build_index = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(build_index)  # type: ignore[union-attr]


class TagRegexTests(unittest.TestCase):
    def test_accepts_module_version_tags(self):
        m = build_index.TAG_RE.match("logos-wallet-module-v1.2.3")
        self.assertIsNotNone(m)
        self.assertEqual(m.group("name"), "logos-wallet-module")
        self.assertEqual(m.group("ver"), "1.2.3")

    def test_accepts_underscore_and_prerelease(self):
        m = build_index.TAG_RE.match("soulseek_ui-v0.1.0-rc.1")
        self.assertIsNotNone(m)
        self.assertEqual(m.group("name"), "soulseek_ui")
        self.assertEqual(m.group("ver"), "0.1.0-rc.1")

    def test_rejects_rolling_index_and_garbage(self):
        self.assertIsNone(build_index.TAG_RE.match("index"))
        self.assertIsNone(build_index.TAG_RE.match("v1.0.0"))
        self.assertIsNone(build_index.TAG_RE.match("Logos-Module-v1"))  # uppercase


class RetryConfigTests(unittest.TestCase):
    def test_retry_status_set(self):
        for code in (429, 500, 502, 503, 504):
            self.assertIn(code, build_index._RETRY_STATUS)
        self.assertNotIn(404, build_index._RETRY_STATUS)
        self.assertNotIn(200, build_index._RETRY_STATUS)

    def test_backoff_is_bounded(self):
        # Full-jitter backoff must never exceed the 30s cap regardless
        # of attempt number; numeric Retry-After is honoured + capped.
        import time as _t

        slept: list[float] = []
        orig = _t.sleep
        _t.sleep = slept.append  # type: ignore[assignment]
        try:
            for attempt in range(0, 8):
                build_index._sleep_for(attempt, None)
            build_index._sleep_for(0, "5")
            build_index._sleep_for(0, "99999")
        finally:
            _t.sleep = orig
        self.assertTrue(all(0 <= s <= 60 for s in slept))
        self.assertLessEqual(max(slept[:8]), 30.0)


if __name__ == "__main__":
    unittest.main()
