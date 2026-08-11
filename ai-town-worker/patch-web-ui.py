from pathlib import Path

repo_root = Path(__file__).resolve().parent.parent
startup = repo_root / "game" / "ui" / "startup" / "StartupScreen.gd"
text = startup.read_text(encoding="utf-8")

required_layout = '''\t\tcontrol.scale = Vector2.ONE\n\t\tcontrol.position = canvas_offset + visual_rect.position * layout_scale\n\t\tcontrol.size = visual_rect.size * layout_scale\n'''
if required_layout not in text:
    raise SystemExit(
        "StartupScreen must use final position/size rectangles without Control.scale"
    )
print("Verified StartupScreen uses identical visual and input rectangles.")

# The browser is the only target where this CI patch is applied. Force the Web
# build to use logical CSS pixels instead of HiDPI backing pixels. On scaled
# Windows displays this keeps DOM pointer coordinates and Godot window/input
# coordinates in the same 1:1 space. Also allow the Web window to follow the
# browser viewport size.
project = repo_root / "game" / "project.godot"
project_text = project.read_text(encoding="utf-8")
replacements = {
    'window/dpi/allow_hidpi=true': 'window/dpi/allow_hidpi=false',
    'window/size/resizable=false': 'window/size/resizable=true',
    'window/stretch/mode="canvas_items"': 'window/stretch/mode="disabled"',
}
for before, after in replacements.items():
    if after in project_text:
        continue
    if before not in project_text:
        raise SystemExit(f"Expected Web display setting not found: {before}")
    project_text = project_text.replace(before, after, 1)
project.write_text(project_text, encoding="utf-8")
print("Patched Web build to low-DPI/resizable coordinates for exact pointer mapping.")
