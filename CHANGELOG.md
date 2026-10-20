# Changelog

All notable changes to Luud are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [0.1.1] - 2026-10-18

### Download

Download **Luud-0.1.1.dmg**, open it and drag Luud to Applications, replacing the old version. The first time you open it, macOS may ask you to allow it under System Settings → Privacy & Security → **Open Anyway**.

### Changed

- **Smart Care** no longer starts as an empty page. Before you scan, it shows what the scan checks and your live disk and memory, and the results appear in the same cards afterwards. A hand-drawn "start here" points at the Scan button until your first scan, and Luud remembers when you last cleaned and how much it freed.
- **Smart Care and the Live Dashboard fit the window** without scrolling. On smaller windows they switch to a compact layout, and only scroll if even that doesn't fit. The dashboard is now two columns.

### Fixed

- The Scan button shows a round focus ring instead of a square one, and the Smart Care page no longer jumps when the scan finishes.
- The Live Dashboard uses about a third less CPU (36% of one core instead of 52%), and Smart Care about half (5% instead of 11%). Only the rings and headline numbers still animate; small values and the process list update in place.

## [0.1.0] - 2026-10-18

The first release.

### Download

Download **Luud-0.1.0.dmg**, open it and drag Luud to Applications. It runs on macOS 15 or later, on Apple silicon and Intel Macs. Apple Intelligence features need macOS 26 on a Mac that supports Apple Intelligence.

Luud isn't notarized yet. The first time you open it, macOS will block it: go to System Settings → Privacy & Security and click **Open Anyway**. To check the download, run `shasum -a 256 Luud-0.1.0.dmg` and compare the result with the line in `SHA256SUMS`.

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

[0.1.1]: https://github.com/RobinJuul/luud/releases/tag/v0.1.1
[0.1.0]: https://github.com/RobinJuul/luud/releases/tag/v0.1.0
