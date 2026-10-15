#!/usr/bin/env python3
"""Validate Xcode membership/assets on Linux; this is NOT a Swift compiler."""
from pathlib import Path
import json
import plistlib
import re


ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "Runner.xcodeproj/project.pbxproj").read_text()
pattern = r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+'
tokens = [token for token in re.findall(pattern, source) if not token.startswith(("//", "/*"))]
cursor = 0


def take(expected=None):
    global cursor
    token = tokens[cursor]
    cursor += 1
    if expected is not None:
        assert token == expected, (token, expected, cursor)
    return token


def parse():
    token = take()
    if token == "{":
        result = {}
        while tokens[cursor] != "}":
            key = parse()
            assert key not in result, f"Duplicate project key: {key}"
            take("=")
            result[key] = parse()
            take(";")
        take("}")
        return result
    if token == "(":
        result = []
        while tokens[cursor] != ")":
            result.append(parse())
            if tokens[cursor] == ",":
                take(",")
        take(")")
        return result
    if token.startswith('"'):
        return json.loads(token)
    return token


project = parse()
assert cursor == len(tokens), "Unexpected trailing project text"
objects = project["objects"]


def references(value):
    if isinstance(value, dict):
        for nested in value.values():
            yield from references(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from references(nested)
    elif re.fullmatch(r"[A-F0-9]{24}", value):
        yield value


assert all(ref in objects for ref in references(project)), "Dangling Xcode object reference"
targets = {obj["name"]: obj for obj in objects.values() if obj.get("isa") == "PBXNativeTarget"}
runner = targets["Runner"]
widget = targets["FardaLiveActivity"]
assert widget["productType"] == "com.apple.product-type.app-extension"
assert widget["productReference"] in objects
assert any(objects[dep]["target"] == next(key for key, value in objects.items() if value is widget)
           for dep in runner["dependencies"]), "Runner does not depend on extension"
embed = [objects[key] for key in runner["buildPhases"] if objects[key].get("name") == "Embed App Extensions"]
assert len(embed) == 1 and embed[0]["dstSubfolderSpec"] == "13"
assert any(objects[key]["fileRef"] == widget["productReference"] for key in embed[0]["files"])


def target_files(target, phase):
    files = set()
    for phase_id in target["buildPhases"]:
        value = objects[phase_id]
        if value["isa"] == phase:
            for build_id in value["files"]:
                files.add(objects[objects[build_id]["fileRef"]]["path"])
    return files


assert {"AppDelegate.swift", "LiveActivityBridge.swift", "FardaRoutineAttributes.swift"} <= target_files(runner, "PBXSourcesBuildPhase")
assert target_files(widget, "PBXSourcesBuildPhase") == {"FardaLiveActivity.swift", "FardaRoutineAttributes.swift"}
resources = target_files(widget, "PBXResourcesBuildPhase")
assert {"Assets.xcassets", "../assets/fonts/Outfit-Regular.ttf", "../assets/fonts/Outfit-SemiBold.ttf"} <= resources
for font in resources - {"Assets.xcassets"}:
    assert (ROOT / font).is_file(), f"Missing font: {font}"
for config_id in objects[widget["buildConfigurationList"]]["buildConfigurations"]:
    config = objects[config_id]
    settings = config["buildSettings"]
    assert settings["IPHONEOS_DEPLOYMENT_TARGET"] == "16.2"
    assert settings["APPLICATION_EXTENSION_API_ONLY"] == "YES"
    assert settings["SKIP_INSTALL"] == "YES"
    assert settings["PRODUCT_BUNDLE_IDENTIFIER"].startswith("com.example.farda.")
    assert (ROOT / settings["INFOPLIST_FILE"]).is_file()
runner_info = plistlib.loads((ROOT / "Runner/Info.plist").read_bytes())
widget_info = plistlib.loads((ROOT / "FardaLiveActivity/Info.plist").read_bytes())
assert runner_info["NSSupportsLiveActivities"] is True
assert "farda" in runner_info["CFBundleURLTypes"][0]["CFBundleURLSchemes"]
assert widget_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
assert set(widget_info["UIAppFonts"]) == {"Outfit-Regular.ttf", "Outfit-SemiBold.ttf"}
for catalog in (ROOT / "FardaLiveActivity/Assets.xcassets").rglob("Contents.json"):
    content = json.loads(catalog.read_text())
    for image in content.get("images", []):
        asset = catalog.parent / image["filename"]
        assert asset.is_file() and asset.stat().st_size > 0
        assert asset.read_text().startswith("<svg"), f"Invalid vector asset: {asset}"
print("PASS: Xcode project syntax/references, target embedding, source memberships, build configs, plists, fonts and vectors")
print("Not verified: Swift compilation, code signing, ActivityKit runtime or device rendering")
