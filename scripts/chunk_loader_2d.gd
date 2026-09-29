class_name ChunkLoader2D
extends GaeaChunkLoader
## [GaeaChunkLoader] for 2D worlds: keeps a square of chunks loaded around the actor, sized to
## cover everything the active [Camera2D] can see, so zooming out loads more chunks.
## Requires a [GaeaChunkLoaderTilemapActor] to convert chunks to world units.
##
## Differences from the base loader:
## - Only loads chunks on z = 0. The base class always loads at least one extra layer above and
##   below, which triples the work for 2D maps.
## - Chunks generate nearest-first, and keep that order as the camera moves.
## - Unloading a chunk whose generation hasn't finished never leaves its tiles behind: queued
##   tasks are cancelled, and running ones are erased as soon as their result arrives. (Cancelling
##   a running task would make every Gaea graph node log "Could not get data from previous node".)

## Render distance used when zoomed in.
@export_range(1, 16) var min_render_distance: int = 1
## Safety cap: [code](2 * max_render_distance + 1)²[/code] chunks can be loaded at once.
## Zooming out further shows unloaded (empty) space instead of generating more.
@export_range(1, 64) var max_render_distance: int = 16
## How many chunks can generate in parallel. Without a limit, every chunk is sent to the thread
## pool at once and nearest-first ordering can't apply. 0 uses CPU threads - 2.
@export_range(0, 64) var max_parallel_chunks: int = 0

@export_group("Debug")
## Keeps every generated chunk's result in memory. Chunks out of view are still removed from the
## tile map, but come back from memory instead of being generated again.
## Memory grows with every new chunk visited and is never freed while enabled.
@export var debug_keep_generated_chunks: bool = false:
	set(value):
		debug_keep_generated_chunks = value
		if not value:
			_chunk_cache.clear()

## Chunks currently loaded in each direction from the actor's chunk.
var render_distance: int = 0

## Loaded chunks and the generation task that fills each one
## (null for chunks drawn from [member _chunk_cache]).
var _chunk_tasks: Dictionary[Vector3i, GaeaTask] = {}
## Generated results kept by [member debug_keep_generated_chunks].
var _chunk_cache: Dictionary[Vector3i, GaeaResult] = {}
## Unloaded chunks whose task was already running; erased once the task finishes.
var _orphan_tasks: Dictionary[Vector3i, GaeaTask] = {}


func _ready() -> void:
	if max_parallel_chunks > 0:
		generator.task_pool.task_limit = max_parallel_chunks
	else:
		generator.task_pool.task_limit = maxi(1, OS.get_processor_count() - 2)
	# Connected after the generator's own handler (made when task_pool is first accessed above),
	# so the erasure is queued after the result's render.
	generator.task_pool.task_finished.connect(_on_task_finished)
	super()


func _try_loading() -> void:
	var chunk_position: Vector3i = actor.get_actor_chunk_position(self, chunk_size)
	var distance: int = _get_needed_render_distance()
	if chunk_position == _last_chunk_position and distance == render_distance:
		return
	render_distance = distance
	_update_loading(chunk_position)


func _update_loading(chunk_position: Vector3i) -> void:
	var required: Array[Vector3i] = _get_chunks_in_loading_radius(chunk_position)
	var required_set: Dictionary[Vector3i, bool] = {}
	for chunk in required:
		required_set[chunk] = true

	if unload_chunks:
		for chunk: Vector3i in _chunk_tasks.keys():
			if required_set.has(chunk):
				continue
			var task: GaeaTask = _chunk_tasks[chunk]
			if task == null or task.finish_time != -1:
				generator.request_area_erasure(_get_area_at(chunk))
			elif task.run_time == -1:
				# Still queued: it never runs, so there is nothing to erase.
				generator.task_pool.cancel(task)
			else:
				_orphan_tasks[chunk] = task
			_chunk_tasks.erase(chunk)

	required.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return (a - chunk_position).length_squared() < (b - chunk_position).length_squared()
	)
	for chunk in required:
		if _chunk_tasks.has(chunk):
			continue
		if _orphan_tasks.has(chunk):
			# Came back before its running task finished: keep that result instead of regenerating.
			_chunk_tasks[chunk] = _orphan_tasks[chunk]
			_orphan_tasks.erase(chunk)
			continue
		if _chunk_cache.has(chunk):
			# Deferred like the generator's own results, so it stays ordered with erasures.
			generator.generation_finished.emit.call_deferred(_chunk_cache[chunk])
			_chunk_tasks[chunk] = null
			continue
		var task: GaeaGenerationTask = generator.generate_area(_get_area_at(chunk))
		# GaeaGenerator.generate_area ignores non-Object origins, so set the priority here.
		# A Callable origin is re-evaluated on every queue sort, following the camera.
		task.set_priority_origin(_get_priority_origin)
		_chunk_tasks[chunk] = task

	_last_chunk_position = chunk_position
	generator.task_pool.notify_priority_changed()


func _on_task_finished(task: GaeaTask) -> void:
	if not task is GaeaGenerationTask:
		return
	var chunk: Vector3i = Vector3i(task.pouch.area.position) / chunk_size
	if debug_keep_generated_chunks:
		_chunk_cache[chunk] = task.results
	if _orphan_tasks.get(chunk) == task:
		_orphan_tasks.erase(chunk)
		generator.request_area_erasure(_get_area_at(chunk))


## Chunk position the queue is sorted around, in the same units as GaeaGenerationPriority's areas.
func _get_priority_origin() -> Vector3i:
	return _last_chunk_position


## Smallest distance whose chunks cover the visible area wherever the camera is inside its chunk.
func _get_needed_render_distance() -> int:
	var tilemap: TileMapLayer = get_node(actor.tilemap)
	var camera: Camera2D = get_viewport().get_camera_2d()
	var zoom: Vector2 = camera.zoom if camera else Vector2.ONE
	var half_view: Vector2 = get_viewport().get_visible_rect().size / zoom / 2.0
	var chunk_world_size: Vector2 = (
		Vector2(chunk_size.x, chunk_size.y) * Vector2(tilemap.tile_set.tile_size) * tilemap.global_scale
	)
	var needed: Vector2 = (half_view / chunk_world_size).ceil()
	return clampi(int(maxf(needed.x, needed.y)), min_render_distance, max_render_distance)


func _get_chunks_in_loading_radius(chunk_position: Vector3i) -> Array[Vector3i]:
	var chunks: Array[Vector3i] = []
	for y in range(chunk_position.y - render_distance, chunk_position.y + render_distance + 1):
		for x in range(chunk_position.x - render_distance, chunk_position.x + render_distance + 1):
			chunks.append(Vector3i(x, y, 0))
	return chunks
