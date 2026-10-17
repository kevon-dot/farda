#!/usr/bin/env python3
"""Unit tests for fail-closed iOS release configuration generation."""

from pathlib import Path
import plistlib
import tempfile
import unittest

from configure_release import (
    validate_release_versions,
    validated_environment,
    write_export_options,
    write_xcconfig,
)


VALID = {
    "FARDA_IOS_APP_BUNDLE_ID": "com.farda.mobile",
    "FARDA_IOS_EXTENSION_BUNDLE_ID": "com.farda.mobile.LiveActivity",
    "FARDA_IOS_TEAM_ID": "AB12CD34EF",
    "FARDA_IOS_APP_PROFILE": "Farda App Store",
    "FARDA_IOS_EXTENSION_PROFILE": "Farda Live Activity App Store",
    "FARDA_IOS_EXPORT_METHOD": "app-store-connect",
    "FARDA_RELEASE_COMMIT": "a" * 40,
    "FARDA_BUILD_NUMBER": "1.2.3",
    "FARDA_VERSION_NAME": "1.2.0",
    "FLUTTER_BUILD_NUMBER": "1.2.3",
}


class ReleaseConfigurationTests(unittest.TestCase):
    def test_generates_manual_export_mapping_and_xcconfig(self) -> None:
        values = validated_environment(VALID)
        with tempfile.TemporaryDirectory() as directory:
            xcconfig = Path(directory) / "ReleaseSigning.xcconfig"
            export = Path(directory) / "ExportOptions.plist"
            write_xcconfig(xcconfig, values)
            write_export_options(export, values)

            self.assertIn("FARDA_RELEASE_COMMIT = " + "a" * 40, xcconfig.read_text())
            options = plistlib.loads(export.read_bytes())
            self.assertEqual(options["signingStyle"], "manual")
            self.assertEqual(options["method"], "app-store-connect")
            self.assertEqual(
                options["provisioningProfiles"],
                {
                    "com.farda.mobile": "Farda App Store",
                    "com.farda.mobile.LiveActivity": "Farda Live Activity App Store",
                },
            )

    def test_rejects_placeholder_app_bundle_id(self) -> None:
        values = VALID | {"FARDA_IOS_APP_BUNDLE_ID": "com.example.farda"}
        with self.assertRaisesRegex(ValueError, "non-placeholder"):
            validated_environment(values)

    def test_rejects_unrelated_extension_bundle_id(self) -> None:
        values = VALID | {"FARDA_IOS_EXTENSION_BUNDLE_ID": "com.other.LiveActivity"}
        with self.assertRaisesRegex(ValueError, "child"):
            validated_environment(values)

    def test_rejects_build_number_mismatch(self) -> None:
        values = VALID | {"FLUTTER_BUILD_NUMBER": "1.2.4"}
        with self.assertRaisesRegex(ValueError, "does not match"):
            validated_environment(values)

    def test_rejects_missing_external_setting(self) -> None:
        values = VALID.copy()
        del values["FARDA_IOS_APP_PROFILE"]
        with self.assertRaisesRegex(ValueError, "FARDA_IOS_APP_PROFILE"):
            validated_environment(values)

    def test_accepts_platform_version_boundaries(self) -> None:
        validate_release_versions("1.2.0", "9999.99.99", "2100000000")
        validate_release_versions("0.9.0", "1.2.3", "1")

    def test_rejects_non_store_marketing_versions(self) -> None:
        for value in ("1", "1.2", "1.2.3.4", "1.2.0-beta", "01.2.0"):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "version_name"):
                validate_release_versions(value, "1", "1")

    def test_rejects_invalid_apple_bundle_versions(self) -> None:
        for value in ("0", "0.1", "10000", "1.100", "1.2.100", "01", "1-beta"):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "ios_build_number"):
                validate_release_versions("1.2.0", value, "1")

    def test_rejects_play_version_codes_over_limit(self) -> None:
        with self.assertRaisesRegex(ValueError, "2100000000"):
            validate_release_versions("1.2.0", "1", "2100000001")


if __name__ == "__main__":
    unittest.main()
