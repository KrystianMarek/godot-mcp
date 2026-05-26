extends Node

# godot-mcp capture_screenshot runner.
#
# Loaded by capture_runner.tscn. Reads custom CLI args (everything after a "--"
# token, parsed via OS.get_cmdline_user_args), instantiates the target scene,
# optionally promotes a Camera2D/Camera3D, waits a configurable number of
# rendered frames so physics/animation/camera lerp can settle, then exports the
# viewport texture to PNG and quits.
#
# Recognised args (all key/value pairs, space-separated):
#   --target-scene  res://path/to/scene.tscn   (required)
#   --out-path      /abs/path/to/out.png        (required)
#   --warmup-frames 10                          (optional, default 10)
#   --camera-node   NodePath/inside/scene       (optional)
#
# stdout protocol consumed by the Node.js handler:
#   CAPTURE_RESULT_OK  <out_path>
#   CAPTURE_RESULT_ERR <reason>

const RESULT_OK := "CAPTURE_RESULT_OK"
const RESULT_ERR := "CAPTURE_RESULT_ERR"

var _target_scene_path: String = ""
var _out_path: String = ""
var _warmup_frames: int = 10
var _camera_node_path: String = ""

var _frames_rendered: int = 0
var _captured: bool = false


func _ready() -> void:
	if not _parse_args():
		return

	var packed: PackedScene = load(_target_scene_path)
	if packed == null:
		_fail("could not load target scene at " + _target_scene_path)
		return

	var instance: Node = packed.instantiate()
	if instance == null:
		_fail("could not instantiate target scene " + _target_scene_path)
		return

	add_child(instance)

	if _camera_node_path != "":
		_promote_camera(instance, _camera_node_path)


func _process(_delta: float) -> void:
	if _captured:
		return

	_frames_rendered += 1
	if _frames_rendered >= _warmup_frames:
		_captured = true
		_capture_and_quit()


func _parse_args() -> bool:
	# OS.get_cmdline_user_args() returns everything after the first "--" token,
	# which is exactly the pass-through list godot-mcp sends.
	var args: PackedStringArray = OS.get_cmdline_user_args()

	var i: int = 0
	while i < args.size():
		var key: String = args[i]
		var value: String = args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--target-scene":
				_target_scene_path = value
				i += 2
			"--out-path":
				_out_path = value
				i += 2
			"--warmup-frames":
				_warmup_frames = int(value)
				if _warmup_frames < 1:
					_warmup_frames = 1
				i += 2
			"--camera-node":
				_camera_node_path = value
				i += 2
			_:
				i += 1

	if _target_scene_path == "":
		_fail("missing --target-scene argument")
		return false
	if _out_path == "":
		_fail("missing --out-path argument")
		return false
	return true


func _promote_camera(scene_root: Node, relative_path: String) -> void:
	var node: Node = scene_root.get_node_or_null(NodePath(relative_path))
	if node == null:
		# Try absolute lookup as a fallback (NodePath rooted at the runner)
		node = get_node_or_null(NodePath(relative_path))
	if node == null:
		push_warning("capture_runner: cameraNodePath '" + relative_path + "' not found; using scene default camera")
		return

	if node is Camera3D:
		(node as Camera3D).make_current()
	elif node is Camera2D:
		(node as Camera2D).make_current()
	else:
		push_warning("capture_runner: node at '" + relative_path + "' is not a Camera2D/Camera3D; ignoring")


func _capture_and_quit() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		_fail("get_viewport() returned null")
		return

	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		_fail("viewport had no texture")
		return

	var image: Image = texture.get_image()
	if image == null:
		_fail("viewport texture had no image")
		return

	var err: int = image.save_png(_out_path)
	if err != OK:
		_fail("save_png failed with error code " + str(err))
		return

	print(RESULT_OK + " " + _out_path)
	get_tree().quit(0)


func _fail(reason: String) -> void:
	push_error("capture_runner: " + reason)
	print(RESULT_ERR + " " + reason)
	get_tree().quit(1)
