class_name Crown
extends Node3D
## Visual for one team's crown. Follows its CrownState: on the pedestal, on the ground,
## or floating above whoever is carrying it.

var team := 0
var state: CrownState
var world: World


func _ready() -> void:
	var gold := Color(1.0, 0.8, 0.2)
	var band := CylinderMesh.new()
	band.top_radius = 0.5
	band.bottom_radius = 0.42
	band.height = 0.35
	add_child(Visuals.mesh_instance(band, gold, Vector3.ZERO, 0.6))
	for i in 5:
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.1
		spike.height = 0.3
		var a := TAU * i / 5.0
		add_child(Visuals.mesh_instance(spike, gold, Vector3(cos(a) * 0.45, 0.32, sin(a) * 0.45), 0.6))
	var gem := SphereMesh.new()
	gem.radius = 0.14
	gem.height = 0.28
	add_child(Visuals.mesh_instance(gem, GameData.team_color(team), Vector3(0, 0.05, 0.47), 2.0))
	var light := OmniLight3D.new()
	light.light_color = gold
	light.omni_range = 6.0
	light.light_energy = 1.5
	light.position.y = 0.5
	add_child(light)


func _process(delta: float) -> void:
	rotation.y += delta * 1.5
	if state == null:
		return
	if state.state == CrownRules.State.CARRIED and world:
		var carrier := world.get_player(state.carrier)
		if carrier:
			global_position = carrier.global_position + Vector3(0, 2.6, 0)
			return
	var lift := 0.5 if state.state == CrownRules.State.HOME else 0.4
	global_position = state.position + Vector3(0, lift + sin(Time.get_ticks_msec() / 400.0) * 0.08, 0)
