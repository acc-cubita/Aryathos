class_name PropGroup
extends Node3D
## A set of camp props, one per child marker. The marker's name picks the prop
## ("Tent", "Tent2", "Crate3"... trailing digits are ignored), its rotation turns it,
## and its metadata holds extra settings (e.g. size for "Crate", radius/from/to for
## "FenceArc"). Move the markers in the editor to rearrange a camp.

@export_enum("watch", "gloomshard", "orebound") var style := "watch"


func build(terrain: Terrain) -> void:
	for marker in get_children():
		if not marker is Marker3D:
			continue
		var kind := String(marker.name).rstrip("0123456789")
		var at: Vector3 = marker.global_position
		at.y = terrain.get_height(at.x, at.z)
		var data := {}
		for key in marker.get_meta_list():
			data[String(key)] = marker.get_meta(key)
		var prop := Props.build(kind, style, data, terrain, at)
		marker.add_child(prop)
		prop.global_position = at
