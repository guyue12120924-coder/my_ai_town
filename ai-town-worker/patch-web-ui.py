from pathlib import Path

repo_root = Path(__file__).resolve().parent.parent
startup = repo_root / "game" / "ui" / "startup" / "StartupScreen.gd"
text = startup.read_text(encoding="utf-8")

old = '''\t\tcontrol.position = canvas_offset + visual_rect.position * layout_scale\n\t\tcontrol.size = reference_rect.size\n\t\tcontrol.scale = Vector2.ONE * layout_scale * MAIN_MENU_SCALE\n'''
new = '''\t\t# Use the final pixel rect directly instead of CanvasItem.scale. This keeps\n\t\t# the rendered button rectangle and Godot's mouse hit rectangle identical\n\t\t# on Web/HiDPI/Adaptive canvases.\n\t\tcontrol.scale = Vector2.ONE\n\t\tcontrol.position = canvas_offset + visual_rect.position * layout_scale\n\t\tcontrol.size = visual_rect.size * layout_scale\n'''

if new in text:
    print("Startup Web input layout patch already applied.")
elif old in text:
    startup.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("Patched StartupScreen controls to use direct position/size hit rectangles.")
else:
    raise SystemExit("StartupScreen layout block changed; refusing to apply an unsafe Web input patch.")
