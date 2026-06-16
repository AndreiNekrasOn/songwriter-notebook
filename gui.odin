package main

import "core:strings"
import "base:runtime"
import ma "vendor:miniaudio"
import "core:thread"
import ui "deps/libui-ng"
import "core:fmt"
import "core:os"
import "core:sync/chan"

Ui_State :: struct {
	playlists: [dynamic]string,
	songs: [dynamic]string,
	engine: ma.engine,
	ch: chan.Chan(string),
	playlists_ui: ^ui.Combobox,
	songs_ui: ^ui.Combobox,
	text_ui: ^ui.MultilineEntry,
	vbox: ^ui.Box,
}

rebuild_song_list :: proc(state: ^Ui_State, new_songs: [dynamic]string) {
	if state.songs != nil {
		delete(state.songs)
	}
	size := ui.ComboboxNumItems(state.songs_ui)
	ui.ComboboxClear(state.songs_ui)

	state.songs = new_songs
	for song in state.songs {
		ui.ComboboxAppend(state.songs_ui, stcs(os.base(song)))
	}
	ui.ComboboxOnSelected(state.songs_ui, proc "c" (btn: ^ui.Combobox, data: rawptr) {
		context = runtime.default_context()
		state := (^Ui_State)(data)
		name_builder: strings.Builder
		idx := ui.ComboboxSelected(btn)
		full_path := state.songs[idx]
		chan.send(state.ch, full_path)
		lyrics := get_lyrics(full_path)
		fmt.println(lyrics)
		ui.MultilineEntrySetText(state.text_ui, stcs(lyrics))
	}, state)
}

web_play :: proc() {
	opts : ui.InitOptions
	fmt.println("Init")
	err := ui.Init(&opts)
	if err != nil {
		ui.FreeInitError(&err)
		return
	}

	state := new(Ui_State)
	state.playlists = get_playlist()
	defer free(state)

	ma.engine_init(nil, &state.engine)
	defer ma.engine_uninit(&state.engine)
	state^.ch, _ = chan.create(chan.Chan(string), 1, context.allocator)
	defer chan.destroy(state^.ch)

	audio_thread := thread.create_and_start_with_poly_data(state, proc(pd: ^Ui_State) {
		is_playing := false
		sound: ma.sound
		command_loop: for {
			data, ok := chan.recv(pd.ch)
			if !ok || data == "" {
				break
			}
			if is_playing {
				ma.sound_stop(&sound)
				ma.sound_uninit(&sound)
				is_playing = false
			}
			play_sound(&pd.engine, data, &sound)
			is_playing = true
		}
	})
	defer thread.destroy(audio_thread)


	win := ui.NewWindow("Songwriter notebook", 100, 100, false)

	ui.WindowOnClosing(win, proc "c" (w: ^ui.Window, data: rawptr) -> bool {
		context = runtime.default_context()
		state := (^Ui_State)(data)
		chan.send(state.ch, "")
		ui.Quit()
		return true
	}, state)

	hbox := ui.NewHorizontalBox()
	state.vbox = ui.NewVerticalBox()
	ui.BoxAppend(hbox, state.vbox, false)

	state.text_ui = ui.NewMultilineEntry()
	ui.MultilineEntrySetReadOnly(state.text_ui, 1)
	ui.BoxAppend(hbox, state.text_ui, true)

	state.playlists_ui = ui.NewCombobox()
	state.songs_ui = ui.NewCombobox()

	for playlist in state.playlists {
		ui.ComboboxAppend(state.playlists_ui, stcs(playlist))
	}
	ui.BoxAppend(state.vbox, state.playlists_ui, false)
	ui.BoxAppend(state.vbox, state.songs_ui, true)

	ui.ComboboxOnSelected(state.playlists_ui, proc "c" (c: ^ui.Combobox, data: rawptr) {
		context = runtime.default_context()
		state := (^Ui_State)(data)
		idx: int = ui.ComboboxSelected(c)
		playlist := state.playlists[idx]
		songs := get_songs(playlist)
		rebuild_song_list(state, songs)
	}, state)

	ui.WindowSetChild(win, hbox)
	ui.ControlShow(win)
	fmt.println("Starting UI Main Loop...")
	ui.Main()
	fmt.println("Uninit")
	ui.Uninit()
}
