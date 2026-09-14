## Smoke bootstrap autoload: plays the booted main scene through
## `SmokeMatchDriver` and makes the result the process exit code.
##
## Armed by one thing and nothing else: `--smoke` after a bare `--`, as
## `SmokeMatchDriver.requested()` reads it off `OS.get_cmdline_user_args()`.
## Without that argument `_ready()` returns having done nothing, so a run
## without the flag is the run this project has always had --
## `tests/test_bootstrap.gd` runs the suites and sets the exit code, and
## nothing here prints, quits or touches the scene.
##
## **It drives the scene the engine already booted.** `run/main_scene` is
## `res://scenes/main.tscn`, so by the time this runs there is a `HotseatMatch`
## in the tree with its match built; `get_tree().current_scene` is that node.
## Instantiating a second one would be a second match, sharing nothing with the
## one a player would have been looking at, and would prove less.
##
## **The work is deferred by one frame.** Autoloads are added to the root
## before the main scene is, so `current_scene` is still null inside `_ready()`.
## `call_deferred()` puts the run at the end of the first frame, by which point
## the main scene has entered the tree and been through its own `_ready()`.
##
## **One line out, and the exit code carries the verdict.** A completed match
## prints `SmokeMatchDriver.completion_marker()` on stdout and quits 0; anything
## else prints `SmokeMatchDriver.failure_line()` on stderr and quits 1. The
## marker's text is defined once, on `SmokeMatchDriver`, because T2's shell
## script greps for that exact shape.
##
## Deliberately carries no `class_name` -- a global class sharing an autoload's
## name is a parse error in Godot 4 ("hides an autoload singleton"), the same
## constraint `tests/test_bootstrap.gd` documents for itself. The driving logic
## lives in `SmokeMatchDriver` instead, where a suite can reach it.
extends Node

## What the run is looking for in the tree. Named for the failure message; the
## scene itself is reached through `get_tree().current_scene`, never loaded
## again.
const MAIN_SCENE_PATH := "res://scenes/main.tscn"

const FAILURE_NO_MAIN_SCENE := "the booted main scene is not a HotseatMatch (%s)"


func _ready() -> void:
	if not SmokeMatchDriver.requested():
		return

	# The main scene is not in the tree yet -- see the class docstring.
	call_deferred("_run")


## Plays the match and quits with the verdict.
func _run() -> void:
	var scene := get_tree().current_scene as HotseatMatch
	if scene == null:
		_quit_failed(FAILURE_NO_MAIN_SCENE % MAIN_SCENE_PATH)
		return

	var result := SmokeMatchDriver.new(scene).run()
	if not result.success:
		_quit_failed(result.reason)
		return

	print(SmokeMatchDriver.completion_marker(result))
	get_tree().quit(0)


## Reports `reason` on stderr and quits non-zero. No completion marker is
## printed on this path, on purpose: the marker means the match played.
func _quit_failed(reason: String) -> void:
	printerr(SmokeMatchDriver.failure_line(reason))
	get_tree().quit(1)
