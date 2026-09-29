class_name BudgetedTileMapRenderer
extends TileMapGaeaRenderer
## [TileMapGaeaRenderer] that spreads tile placement and erasure over several frames, so a burst
## of finished chunks doesn't stall the main thread. Also has a fast path for square tile sets
## that skips the per-cell position conversion call.
##
## Renders and erasures run in the order they arrive. Erasing an area drops any pending render
## that falls inside it, so a chunk unloaded before it was drawn never shows up.

## Main-thread time per frame spent placing or erasing tiles. At least one chunk is
## processed each frame, so chunks bigger than the budget still make progress.
@export_range(0.5, 16.0, 0.5, "suffix:ms") var frame_budget_ms: float = 4.0

## Pending [GaeaResult]s to render and [AABB]s to erase, oldest first.
var _jobs: Array = []


func render(grid: GaeaResult) -> void:
	_jobs.append(grid)


func erase_area(area: AABB) -> void:
	_jobs = _jobs.filter(func(job: Variant) -> bool:
		return not (job is GaeaResult and _is_result_in_area(job, area))
	)
	_jobs.append(area)


func reset() -> void:
	_jobs.clear()
	super()


func _process(_delta: float) -> void:
	var deadline: int = Time.get_ticks_usec() + int(frame_budget_ms * 1000.0)
	while not _jobs.is_empty():
		var job: Variant = _jobs.pop_front()
		if job is GaeaResult:
			super.render(job)
		else:
			super.erase_area(job)
		if Time.get_ticks_usec() >= deadline:
			break


func _render(grid: GaeaResult) -> void:
	if not _all_layers_square():
		super(grid)
		return
	for layer_idx in grid.get_layers_count():
		var layer: Variant = grid.get_layer(layer_idx)
		if not layer is GaeaValue.Map or layer_idx >= tile_map_layers.size():
			continue
		var tile_map_layer: TileMapLayer = tile_map_layers[layer_idx]
		if not is_instance_valid(tile_map_layer):
			continue
		var terrains: Dictionary[TileMapGaeaMaterial, Array] = {}
		var patterns: Dictionary[TileMapGaeaMaterial, Array] = {}
		for cell: Vector3i in layer.get_cells():
			var value: GaeaMaterial = layer.get_cell(cell)
			if not value is TileMapGaeaMaterial:
				continue
			match value.type:
				TileMapGaeaMaterial.Type.SINGLE_CELL:
					tile_map_layer.set_cell(Vector2i(cell.x, cell.y), value.source_id, value.atlas_coord, value.alternative_tile)
				TileMapGaeaMaterial.Type.TERRAIN:
					terrains.get_or_add(value, []).append(Vector2i(cell.x, cell.y))
				TileMapGaeaMaterial.Type.PATTERN:
					var origin: Vector3i = cell + value.pattern_offset
					patterns.get_or_add(value, []).append(Vector2i(origin.x, origin.y))
		for terrain_material: TileMapGaeaMaterial in terrains:
			tile_map_layer.set_cells_terrain_connect(
				terrains[terrain_material], terrain_material.terrain_set, terrain_material.terrain, false
			)
		for pattern_material: TileMapGaeaMaterial in patterns:
			var pattern := tile_map_layer.tile_set.get_pattern(pattern_material.pattern_index)
			for cell: Vector2i in patterns[pattern_material]:
				tile_map_layer.set_pattern(cell, pattern)


func _erase_area(area: AABB) -> void:
	if not _all_layers_square():
		super(area)
		return
	for tile_map_layer in tile_map_layers:
		if not is_instance_valid(tile_map_layer):
			continue
		for x in range(area.position.x, area.end.x):
			for y in range(area.position.y, area.end.y):
				tile_map_layer.erase_cell(Vector2i(x, y))


## Square tile sets map Gaea cells to tile map cells 1:1, so the conversion call can be skipped.
func _all_layers_square() -> bool:
	for tile_map_layer in tile_map_layers:
		if is_instance_valid(tile_map_layer) and tile_map_layer.tile_set.tile_shape != TileSet.TILE_SHAPE_SQUARE:
			return false
	return true


## Every cell of a chunk's result lies inside that chunk, so checking one cell is enough.
func _is_result_in_area(result: GaeaResult, area: AABB) -> bool:
	for layer_idx in result.get_layers_count():
		var layer: Variant = result.get_layer(layer_idx)
		if layer is GaeaValue.GridType and not layer.is_empty():
			var cell: Vector3i = layer.get_cells()[0]
			return area.has_point(Vector3(cell) + Vector3(0.5, 0.5, 0.5))
	return false
