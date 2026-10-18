# Changelog

All notable changes to Luud are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [1.0.0] - 2026-10-18

The first release.

### Download

Download **Luud-1.0.0.dmg**, open it and drag Luud to Applications. It runs on macOS 15 or later, on Apple silicon and Intel Macs. Apple Intelligence features need macOS 26 on a Mac that supports Apple Intelligence.

Luud isn't notarized yet. The first time you open it, macOS will block it: go to System Settings → Privacy & Security and click **Open Anyway**. To check the download, run `shasum -a 256 Luud-1.0.0.dmg` and compare the result with the line in `SHA256SUMS`.

### Features

- **Smart Care:** one scan for junk, apps you haven't opened in six months, disk space and memory.
- **System Junk:** user caches, logs and crash reports, Xcode and developer caches (npm, Gradle, Cargo, Yarn, pnpm, conda, CocoaPods, Maven), old installers in Downloads, Mail attachments and the Trash.
- **Uninstaller:** removes apps together with their related files, lists apps you don't use and finds leftovers from apps you've already deleted.
- **Space Lens:** every folder measured and sorted, with a ring chart.
- **Large Files:** everything over 100 MB, 500 MB, 1 GB or 5 GB in your home folder, with when you last opened it.
- **Live Dashboard:** CPU, memory breakdown, network, disk, battery health and the busiest processes, updated every second.
- **Menu bar:** live gauges, the busiest apps, and one-click Free up RAM.
- **Performance:** maintenance tasks (free up RAM, flush DNS, thin Time Machine snapshots, reindex Spotlight, rebuild Launch Services) and background launch agents and daemons you can switch off and on again.
- **Explain with Apple Intelligence:** every item can be explained on your Mac with Foundation Models, with a verdict of *Safe to delete*, *Check first* or *Keep*. Nothing is sent to a server.
- **Alerts** when the startup disk runs low, **Open at login**, and a choice of what the menu bar shows.

### Safeguards

- Nothing is removed until you've reviewed it.
- Anything you might want back goes to the Trash; only things apps rebuild by themselves are deleted.
- Admin tasks run only after the standard macOS password prompt.

[1.0.0]: https://github.com/RobinJuul/luud/releases/tag/v1.0.0
