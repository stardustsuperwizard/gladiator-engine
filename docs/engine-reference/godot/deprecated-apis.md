# Godot — deprecated APIs

Old spelling on the left, current spelling on the right. If a session suggests
anything in the left column, it is reasoning from stale training data.

Sourced from the official migration pages listed in `README.md`. Rows are
filtered to what can reach this project — see that file for the filter.

## Renamed or replaced

| Do not use | Use instead | Since | Notes |
| --- | --- | --- | --- |
| `Resource.duplicate(true)` for a deep copy that must include external resources | `Resource.duplicate_deep(DEEP_DUPLICATE_ALL)` | 4.5 | `duplicate(true)` still exists and still deep-copies, but **only resources internal to the file it is called on**. External sub-resources are now shared, not copied. |
| `Node.get_rpc_config()` | `Node.get_node_rpc_config()` | 4.5 | Not GDScript-compatible — the old name is gone, not deprecated. No caller in this repo; listed because networking is a deferred item. |
| `JSONRPC.set_scope()` | `JSONRPC.set_method()` | 4.5 | Same: removed, not soft-deprecated. |
| `randi()` / `randf()` / `randi_range()` inside `rules/` | `DeterministicRng` threaded through `GameState` | — | Not an engine deprecation. A project rule, enforced by `rules/tests/ambient_rng_contract_test.gd`. Listed here because it is the ambient-API habit a model is most likely to reach for. |

## Behaviour changed under the same name

These are worse than renames: the call still compiles and still runs.

| API | What changed | Since |
| --- | --- | --- |
| `AStar2D.get_point_path`, `AStar3D.get_point_path`, `AStarGrid2D.get_id_path`, `AStarGrid2D.get_point_path` | Return an **empty path** when `from_id` is a disabled/solid point. Previously they did not. | 4.6 |
| `FileAccess.store_*` (`store_8`, `store_16`, `store_32`, `store_64`, `store_buffer`, `store_line`, `store_string`, `store_var`, …) | Return `bool` instead of `void`. GDScript-compatible, but a discarded return value is now a silently ignored failure. | 4.4 |
| `FileAccess.get_as_text` | The `skip_cr` parameter was removed. | 4.6 |
| `Object.is_class` | `class` parameter is `StringName`, was `String`. GDScript-compatible. | 4.7 |
| `ProjectSettings.add_property_info` | Now prints a warning for missing or invalid dictionary keys, including `usage` — previously ignored silently. | 4.5 |
