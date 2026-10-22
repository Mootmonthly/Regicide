class_name VoiceChat
extends Node
## Push-to-talk voice chat.
##   T: proximity - everyone within PROXIMITY_RANGE hears you, positioned in 3D at your
##      character and fading with distance (enemies too).
##   Y: team radio - your whole team hears you, wherever they are.
##
## The microphone is captured from an audio bus, mixed to mono, resampled to 16 kHz and
## mu-law compressed to 8 bits per sample (~16 KB/s while talking). Packets go to the
## server, which relays them only to the players who should hear them (so proximity
## chat costs nothing for players far away). Listeners play each speaker through an
## AudioStreamGenerator.

enum Channel { PROXIMITY, TEAM }

const RATE := 16000
const CHUNK := 640  ## samples per packet (40 ms)
const PROXIMITY_RANGE := 45.0
const MU := 255.0
const SPEAKING_HOLD := 0.35

var world: World
var talking := -1  ## the channel you're transmitting on, or -1
var enabled := false
## peer id -> [game time last heard, channel]
var speaking: Dictionary = {}

var _capture: AudioEffectCapture
var _mic: AudioStreamPlayer
var _pending := PackedFloat32Array()
var _resample_pos := 0.0
var _voices: Dictionary = {}  ## "peer:channel" -> [player node, AudioStreamGeneratorPlayback]


func _ready() -> void:
	world = get_parent() as World
	if Net.is_dedicated() or DisplayServer.get_name() == "headless":
		return
	_setup_microphone()


func _setup_microphone() -> void:
	var bus := AudioServer.get_bus_index("Mic")
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "Mic")
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new())
		# Silence the bus after capturing, so you never hear yourself.
		var quiet := AudioEffectAmplify.new()
		quiet.volume_db = -80.0
		AudioServer.add_bus_effect(bus, quiet)
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	enabled = _capture != null


func _process(_delta: float) -> void:
	_expire_speakers()
	if not enabled:
		return
	var channel := -1
	var me := world.local_player()
	if me and (world.hud == null or not world.hud.menu_open):
		if Input.is_action_pressed("voice_proximity"):
			channel = Channel.PROXIMITY
		elif Input.is_action_pressed("voice_team"):
			channel = Channel.TEAM
	if channel >= 0 and not _mic.playing:
		_mic.play()
	talking = channel
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	var buffer := _capture.get_buffer(frames)
	if talking < 0:
		_pending.clear()
		return
	var step := RATE / AudioServer.get_mix_rate()
	for f in buffer:
		_resample_pos += step
		if _resample_pos >= 1.0:
			_resample_pos -= 1.0
			_pending.append((f.x + f.y) * 0.5)
	while _pending.size() >= CHUNK:
		var packet := encode(_pending.slice(0, CHUNK))
		_pending = _pending.slice(CHUNK)
		_send(packet, talking)


func _send(packet: PackedByteArray, channel: int) -> void:
	if multiplayer.is_server():
		_relay(multiplayer.get_unique_id(), packet, channel)
	else:
		_voice_up.rpc_id(1, packet, channel)


# --- Server relay -----------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _voice_up(packet: PackedByteArray, channel: int) -> void:
	if multiplayer.is_server() and packet.size() <= CHUNK * 2:
		_relay(multiplayer.get_remote_sender_id(), packet, channel)


func _relay(speaker: int, packet: PackedByteArray, channel: int) -> void:
	for peer in recipients(speaker, channel):
		if peer == multiplayer.get_unique_id():
			_voice_down(speaker, packet, channel)
		else:
			_voice_down.rpc_id(peer, speaker, packet, channel)


## Who hears `speaker` on `channel`: teammates for team radio, or every (human) player
## within range for proximity chat. Never the speaker themselves.
func recipients(speaker: int, channel: int) -> Array[int]:
	var out: Array[int] = []
	var gm := world.game_mode
	var rec: PlayerRecord = gm.records.get(speaker)
	var me := world.get_player(speaker)
	if rec == null or me == null:
		return out
	for other: PlayerRecord in gm.records.values():
		if other.peer_id == speaker or other.is_bot:
			continue
		if channel == Channel.TEAM:
			if other.team == rec.team:
				out.append(other.peer_id)
		else:
			var p := world.get_player(other.peer_id)
			if p and p.sync_pos.distance_to(me.sync_pos) <= PROXIMITY_RANGE:
				out.append(other.peer_id)
	return out


# --- Playback ------------------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _voice_down(speaker: int, packet: PackedByteArray, channel: int) -> void:
	speaking[speaker] = [world.game_mode.clock, channel]
	var speaker_node := world.get_player(speaker)
	if speaker_node:
		speaker_node.set_speaking(true)
	if not enabled and DisplayServer.get_name() == "headless":
		return
	var playback := _voice_for(speaker, channel)
	if playback == null:
		return
	for v in decode(packet):
		if not playback.can_push_buffer(1):
			break
		playback.push_frame(Vector2(v, v))


func _voice_for(speaker: int, channel: int) -> AudioStreamGeneratorPlayback:
	var key := "%d:%d" % [speaker, channel]
	if _voices.has(key) and is_instance_valid(_voices[key][0]):
		return _voices[key][1]
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = RATE
	generator.buffer_length = 0.5
	var node: Node
	if channel == Channel.PROXIMITY:
		var p := world.get_player(speaker)
		if p == null:
			return null
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = generator
		p3.unit_size = 10.0
		p3.max_distance = PROXIMITY_RANGE
		p3.position = Vector3(0, 1.6, 0)
		p.add_child(p3)
		p3.play()
		node = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = generator
		p2.volume_db = -3.0
		add_child(p2)
		p2.play()
		node = p2
	var playback: AudioStreamGeneratorPlayback = node.get_stream_playback()
	_voices[key] = [node, playback]
	return playback


func _expire_speakers() -> void:
	var now := world.game_mode.clock
	for peer: int in speaking.keys():
		if now - float(speaking[peer][0]) > SPEAKING_HOLD:
			speaking.erase(peer)
			var p := world.get_player(peer)
			if p:
				p.set_speaking(false)


# --- Codec ---------------------------------------------------------------------------------

## mu-law: 8 bits per sample with more precision for quiet sounds.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		var x := clampf(samples[i], -1.0, 1.0)
		var y := signf(x) * log(1.0 + MU * absf(x)) / log(1.0 + MU)
		out[i] = clampi(roundi((y + 1.0) * 127.5), 0, 255)
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		var y := data[i] / 127.5 - 1.0
		out[i] = signf(y) * (pow(1.0 + MU, absf(y)) - 1.0) / MU
	return out
