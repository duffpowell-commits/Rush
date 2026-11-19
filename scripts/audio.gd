extends Node
## Autoload "Audio". Audio.sfx("good") plays assets/audio/good.wav on the SFX bus;
## Audio.music("music_loop") loops a track on the Music bus. Volumes live in Settings.
## Buses are in default_bus_layout.tres (web ignores buses added at runtime: add new ones there).

const DIR := "res://assets/audio/"
const VOICES := 6

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)


func _stream(name: String) -> AudioStream:
	if not _cache.has(name):
		var path := DIR + name + ".wav"
		_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[name]


func sfx(name: String, pitch: float = 1.0) -> void:
	var s := _stream(name)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = s
	p.pitch_scale = pitch
	p.play()


func music(name: String) -> void:
	var s := _stream(name)
	if s == null or (_music.stream == s and _music.playing):
		return
	# Looping is set in the track's .import (edit/loop_mode=2) or an .ogg's loop flag.
	_music.stream = s
	_music.play()


func stop_music() -> void:
	_music.stop()
