#!/usr/bin/env python3
"""Ermittelt die naechste Version aus den Commits seit dem letzten Release.

Aufgerufen von .github/workflows/release.yml. Umgebung:
  BASE_VERSION  Version des letzten Releases (Tag ohne "v"), sonst leer
  BASE_REF      dessen Tag, sonst leer (dann zaehlen alle Commits)
  NOTES_PATH    Ziel der Release-Notizen (Markdown)

Ohne Tag gilt die Version aus pubspec.yaml als Basis.

Erhoehung (Betreffzeile, angelehnt an Conventional Commits):
  "typ!:" oder "BREAKING CHANGE" bzw. "[major]"  -> Major
  "feat:" bzw. "[minor]"                         -> Minor
  alles andere                                   -> Patch

Gibt auf stdout nur die neue Version aus, alles andere geht nach stderr.
"""
import os
import re
import subprocess
import sys

SUBJECT = re.compile(r"^(?P<type>[A-Za-z]+)(?:\([^)]*\))?(?P<bang>!)?:\s*(?P<text>.+)$")
SECTIONS = [("feat", "Neu"), ("fix", "Behoben")]


def log(msg):
    print(msg, file=sys.stderr)


def pubspec_version():
    with open("pubspec.yaml", encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^version:\s*(\d+\.\d+\.\d+)", line)
            if m:
                return m.group(1)
    return "0.0.0"


def commits(base_ref):
    rng = f"{base_ref}..HEAD" if base_ref else "HEAD"
    out = subprocess.run(
        ["git", "log", rng, "--no-merges", "--format=%s"], check=True, capture_output=True, text=True
    ).stdout
    return [s for s in out.splitlines() if s.strip() and "[skip ci]" not in s]


def main():
    base_version = os.environ.get("BASE_VERSION") or pubspec_version()
    base_ref = os.environ.get("BASE_REF") or ""
    notes_path = os.environ["NOTES_PATH"]

    subjects = commits(base_ref)
    log(f"{len(subjects)} Commits seit {base_ref or 'Beginn'}")

    major, minor, patch = (int(x) for x in base_version.split("."))
    bump = "patch"
    for s in subjects:
        m = SUBJECT.match(s)
        if "[major]" in s or (m and m.group("bang")) or "BREAKING CHANGE" in s:
            bump = "major"
            break
        if "[minor]" in s or (m and m.group("type").lower() == "feat"):
            bump = "minor"
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    version = f"{major}.{minor}.{patch}"
    log(f"{bump}: {base_version} -> {version}")

    grouped = {key: [] for key, _ in SECTIONS}
    other = []
    for s in subjects:
        m = SUBJECT.match(s)
        text = (m.group("text") if m else s).replace("[major]", "").replace("[minor]", "").strip()
        key = m.group("type").lower() if m else ""
        (grouped[key] if key in grouped else other).append(text)
    lines = []
    for key, title in SECTIONS:
        if grouped[key]:
            lines += [f"### {title}", *[f"- {t}" for t in grouped[key]], ""]
    if other:
        lines += ["### Sonstiges", *[f"- {t}" for t in other], ""]
    with open(notes_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) or "Keine Änderungen.\n")

    print(version)


if __name__ == "__main__":
    main()
