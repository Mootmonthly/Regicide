extends Node
## Connection settings and lifecycle. The menu fills in the settings and loads the
## World scene; World calls start() once its spawners exist, so replication from the
## server always has somewhere to land.
##
## Command line (after "--"):  --server | --host | --join <address>   [--port N] [--name X] [--bots N]

const DEFAULT_PORT := 24565
const MAX_PEERS := 100
const MENU_SCENE := "res://scenes/main_menu.tscn"
const WORLD_SCENE := "res://scenes/world.tscn"

enum Mode { NONE, HOST, JOIN, DEDICATED }

var mode: Mode = Mode.NONE
var address := "127.0.0.1"
var port := DEFAULT_PORT
var player_name := "Peasant"
## Server: bots fill each team up to this many players.
var team_fill := GameData.DEFAULT_TEAM_FILL
## Shown on the main menu after being sent back there.
var last_error := ""


func _ready() -> void:
	_parse_command_line()
	if mode != Mode.NONE:
		get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)


func is_dedicated() -> bool:
	return mode == Mode.DEDICATED


func is_server_mode() -> bool:
	return mode == Mode.HOST or mode == Mode.DEDICATED


func play(new_mode: Mode) -> void:
	mode = new_mode
	last_error = ""
	get_tree().change_scene_to_file(WORLD_SCENE)


func start() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error
	if is_server_mode():
		err = peer.create_server(port, MAX_PEERS)
		if err == OK:
			print("[net] Listening on port %d" % port)
	else:
		err = peer.create_client(address, port)
		if err == OK:
			print("[net] Connecting to %s:%d" % [address, port])
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Close the connection and return to the main menu, optionally explaining why.
func leave(reason := "") -> void:
	last_error = reason
	if reason != "":
		print("[net] " + reason)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var was_dedicated := is_dedicated()
	mode = Mode.NONE
	if was_dedicated:
		get_tree().quit(1)
	else:
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _parse_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		var next := args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--server":
				mode = Mode.DEDICATED
			"--host":
				mode = Mode.HOST
			"--join":
				mode = Mode.JOIN
				if next != "" and not next.begins_with("--"):
					address = next
					i += 1
			"--port":
				port = int(next)
				i += 1
			"--name":
				player_name = next
				i += 1
			"--bots":
				team_fill = clampi(int(next), 0, GameData.TEAM_SIZE)
				i += 1
		i += 1
