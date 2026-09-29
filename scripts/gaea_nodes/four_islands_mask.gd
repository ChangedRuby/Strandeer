@tool
class_name GaeaNodeFourIslandsMask
extends GaeaNodeResource
## Mask with one island per quadrant of a square world: 1.0 at each island's core, fading to 0.0
## at its coast, and 0.0 everywhere else (including outside the world).
##
## Computed from absolute cell coordinates, so every chunk samples the same four islands.
## Each island stays inside its own quadrant (keeping [param edge_margin] away from the quadrant
## edges), so islands can never touch. Island centers and radii are jittered from the seed.


func _get_title() -> String:
	return "FourIslandsMask"


func _get_description() -> String:
	return """Creates a mask with one island per quadrant of a square world of [param world_size] cells.
Multiply it with a noise to confine land to the four islands."""


func _get_arguments_list() -> Array[StringName]:
	return [&"world_size", &"island_radius", &"coast_start", &"edge_margin", &"center_jitter", &"radius_jitter"]


func _get_argument_type(arg_name: StringName) -> GaeaValue.Type:
	return GaeaValue.Type.INT if arg_name == &"world_size" else GaeaValue.Type.FLOAT


func _get_argument_description(arg_name: StringName) -> String:
	match arg_name:
		&"world_size":
			return "Width and height of the world, in cells. The world spans (0, 0) to (world_size, world_size)."
		&"island_radius":
			return "Island radius as a fraction of the space available in its quadrant (0 to 1)."
		&"coast_start":
			return "Fraction of the radius where the mask starts fading. Inside it the mask is 1."
		&"edge_margin":
			return "Cells of guaranteed ocean between an island and its quadrant edges."
		&"center_jitter":
			return "Max random offset of each island's center, as a fraction of its quadrant's half size."
		&"radius_jitter":
			return "Max random change of each island's radius, as a fraction of it."
	return super(arg_name)


func _get_argument_default_value(arg_name: StringName) -> Variant:
	match arg_name:
		&"world_size":
			return 1024
		&"island_radius":
			return 0.9
		&"coast_start":
			return 0.35
		&"edge_margin":
			return 16.0
		&"center_jitter":
			return 0.15
		&"radius_jitter":
			return 0.15
	return super(arg_name)


func _get_argument_hint(arg_name: StringName) -> Dictionary[String, Variant]:
	match arg_name:
		&"world_size":
			return {"min": 2}
		&"island_radius", &"coast_start", &"center_jitter", &"radius_jitter":
			return {"min": 0.0, "max": 1.0, "step": 0.01}
		&"edge_margin":
			return {"min": 0.0, "step": 1.0}
	return super(arg_name)


func _get_output_ports_list() -> Array[StringName]:
	return [&"mask"]


func _get_output_port_type(_output_name: StringName) -> GaeaValue.Type:
	return GaeaValue.Type.SAMPLE


func _get_data(_output_port: StringName, pouch: GaeaGenerationPouch) -> GaeaValue.Sample:
	var world_size: int = _get_arg(&"world_size", pouch)
	var coast_start: float = clampf(_get_arg(&"coast_start", pouch), 0.0, 0.999)
	var islands: Array[Vector3] = _get_islands(pouch, world_size)
	var half: float = world_size * 0.5

	var result: GaeaValue.Sample = GaeaValue.Sample.new()
	for x in _get_axis_range(Vector3i.AXIS_X, pouch.area):
		for y in _get_axis_range(Vector3i.AXIS_Y, pouch.area):
			var value: float = 0.0
			if x >= 0 and y >= 0 and x < world_size and y < world_size:
				var island: Vector3 = islands[int(x >= half) + 2 * int(y >= half)]
				var distance: float = Vector2(x + 0.5, y + 0.5).distance_to(Vector2(island.x, island.y))
				value = 1.0 - smoothstep(coast_start, 1.0, distance / island.z)
			result.set_xyz(x, y, 0, value)
	return result


## Returns the 4 islands as (center_x, center_y, radius), ordered top-left, top-right,
## bottom-left, bottom-right. Deterministic for a given seed.
func _get_islands(pouch: GaeaGenerationPouch, world_size: int) -> Array[Vector3]:
	var island_radius: float = clampf(_get_arg(&"island_radius", pouch), 0.0, 1.0)
	var edge_margin: float = maxf(_get_arg(&"edge_margin", pouch), 0.0)
	var center_jitter: float = clampf(_get_arg(&"center_jitter", pouch), 0.0, 1.0)
	var radius_jitter: float = clampf(_get_arg(&"radius_jitter", pouch), 0.0, 1.0)
	var quadrant: float = world_size * 0.5

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pouch.settings.seed + salt)
	var islands: Array[Vector3] = []
	for i in 4:
		var quadrant_center := Vector2((i % 2 + 0.5) * quadrant, (i / 2 + 0.5) * quadrant)
		var offset := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * center_jitter * quadrant * 0.5
		var center: Vector2 = quadrant_center + offset
		# Largest radius that keeps edge_margin to every edge of this quadrant.
		var room: float = quadrant * 0.5 - maxf(absf(offset.x), absf(offset.y)) - edge_margin
		var radius: float = room * island_radius * (1.0 - rng.randf() * radius_jitter)
		islands.append(Vector3(center.x, center.y, maxf(radius, 1.0)))
	return islands
