#!/usr/bin/env python3

import pathlib
import unittest
import importlib.util
import sys


MODULE_PATH = pathlib.Path(__file__).with_name("audit.py")
SPEC = importlib.util.spec_from_file_location("nix_bloat_audit", MODULE_PATH)
audit = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = audit
SPEC.loader.exec_module(audit)


class AuditHelpersTest(unittest.TestCase):
    def test_parse_shell_command_strips_wrappers(self) -> None:
        self.assertEqual(
            audit.parse_shell_command("sudo env FOO=bar command kubectl get pods"),
            "kubectl",
        )

    def test_parse_shell_command_ignores_shell_c(self) -> None:
        self.assertIsNone(audit.parse_shell_command("bash -c 'echo hi'"))

    def test_normalize_package_key_drops_hash_and_version(self) -> None:
        self.assertEqual(
            audit.normalize_package_key("/nix/store/0123456789abcdefghijklmnopqrstuv-google-chrome-145.0.1"),
            "google-chrome",
        )


if __name__ == "__main__":
    unittest.main()
