# Luud

*Luud* is Estonian for broom.

A Mac cleaner and system monitor for macOS 15+: live system monitor in the menu bar, junk cleanup, uninstaller with leftover detection, Space Lens disk map, large-file finder and maintenance tools.

## Build

Requires the Xcode Command Line Tools. With Command Line Tools 26 or later (macOS 26 SDK), the build includes the Apple Intelligence **Explain** button, which describes any file or folder and whether it's safe to delete. It runs on-device and needs Apple Intelligence turned on; with older tools the button is left out.

```sh
./build.sh            # builds build/Luud.app
./build.sh --install  # installs to ~/Applications and launches it
```

The app is ad-hoc signed. For the Trash and Mail attachments to be scanned, grant Full Disk Access in System Settings → Privacy & Security.

## What gets removed, and how

| Category | Disposal |
| --- | --- |
| Caches, logs, Xcode and developer caches | Deleted (apps rebuild them) |
| Installers in Downloads, Mail attachments, apps, leftovers, large files | Moved to the Trash |
| Trash | Deleted |

Caches belonging to running apps, Xcode archives and the Maven repository are found but left unticked.

## Layout

- `Stats/` — CPU, memory, network, process, battery sampling (Mach/sysctl/IOKit/libproc)
- `Cleanup/` — junk rules and the scan/clean model
- `Uninstaller/` — installed apps, related files, orphaned leftovers
- `SpaceLens/` — disk map and large files
- `Performance/` — maintenance tasks, launch agents/daemons
- `AI/` — on-device explanations (Foundation Models); location rules decide the verdict, the model explains it
- `Views/` — SwiftUI; `Theme.swift` holds the palette, corner and motion tokens
