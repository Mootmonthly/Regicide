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
## Client: password to send when joining. Server: password players must give ("" = open).
var password := ""
## Server settings (dedicated servers read them from server.cfg).
var server_name := "Regicide server"
var motd := ""
## Dedicated servers: humans needed before a match starts (0 = start right away), and
## the countdown once they are here.
var min_players := 2
var lobby_countdown := 60.0
var max_players := MAX_PEERS
var _config_path := ""
## Settings given as command-line flags; these win over server.cfg.
var _cli_flags: Dictionary = {}
## Shown on the main menu after being sent back there.
var last_error := ""


func _ready() -> void:
	_parse_command_line()
	if mode == Mode.DEDICATED:
		load_server_config()
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


## The game's version ("0.2.0"; "dev" for builds made outside a release). Clients and
## servers must match to play together.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


## Dedicated servers: read server.cfg (from --config, or next to the executable). If it
## doesn't exist yet, write one with the defaults so it's easy to edit.
func load_server_config() -> void:
	var path := _config_path
	if path == "":
		var exe_dir := OS.get_executable_path().get_base_dir()
		path = exe_dir.path_join("server.cfg") if not OS.has_feature("editor") else "user://server.cfg"
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		cfg.set_value("server", "name", server_name)
		cfg.set_value("server", "port", port)
		cfg.set_value("server", "password", password)
		cfg.set_value("server", "max_players", max_players)
		cfg.set_value("server", "min_players", min_players)
		cfg.set_value("server", "lobby_countdown", lobby_countdown)
		cfg.set_value("server", "bots_per_team", team_fill)
		cfg.set_value("server", "motd", "Welcome! Steal their crown, defend your own.")
		if cfg.save(path) == OK:
			print("[server] Wrote a default config to %s; edit it and restart to change settings." % path)
	server_name = str(cfg.get_value("server", "name", server_name))
	# Flags given on the command line win over the file.
	if not _cli_flags.has("port"):
		port = int(cfg.get_value("server", "port", port))
	if not _cli_flags.has("password"):
		password = str(cfg.get_value("server", "password", ""))
	max_players = clampi(int(cfg.get_value("server", "max_players", max_players)), 1, MAX_PEERS)
	min_players = clampi(int(cfg.get_value("server", "min_players", min_players)), 0, MAX_PEERS)
	lobby_countdown = clampf(float(cfg.get_value("server", "lobby_countdown", lobby_countdown)), 0.0, 600.0)
	if not _cli_flags.has("bots"):
		team_fill = clampi(int(cfg.get_value("server", "bots_per_team", team_fill)), 0, GameData.TEAM_SIZE)
	motd = str(cfg.get_value("server", "motd", ""))
	print("[server] %s · version %s · port %d · up to %d players · %s · bots per team: %d" % [
		server_name, game_version(), port, max_players, "password required" if password != "" else "open", team_fill])


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
				_cli_flags[a.trim_prefix("--")] = true
				port = int(next)
				i += 1
			"--name":
				player_name = next
				i += 1
			"--bots":
				_cli_flags[a.trim_prefix("--")] = true
				team_fill = clampi(int(next), 0, GameData.TEAM_SIZE)
				i += 1
			"--config":
				_config_path = next
				i += 1
			"--password":
				_cli_flags[a.trim_prefix("--")] = true
				password = next
				i += 1
		i += 1
