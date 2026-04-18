# LD59

Godot project root for the LD59 game jam build.

## Structure

```text
ld59/
├── assets/
├── scenes/
├── scripts/
├── export_presets.cfg
└── project.godot
```

## Getting Started

1. Open the `ld59/` folder in Godot 4.6.
2. Run the project directly. The bootstrap scene is `res://scenes/main.tscn`.
3. Export with the built-in presets:
   - `Itch Web` writes `exports/itch/index.html`
   - `Windows Desktop` writes `exports/windows/ld59.exe`
   - `Linux Desktop` writes `exports/linux/ld59.x86_64`

## Notes

- `export_presets.cfg` is tracked so the team shares the same build targets.
- Export outputs stay in `exports/`, which is ignored by git.
- Assumption: itch.io target is a web build, while desktop presets cover downloadable jam builds.
