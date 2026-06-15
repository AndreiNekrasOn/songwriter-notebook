package main

import "base:runtime"

import ui "deps/libui-ng"
import "core:fmt"

web_play :: proc() {
	opts : ui.InitOptions
	fmt.println("Init")
	err := ui.Init(&opts)
	if err != nil {
		ui.FreeInitError(&err)
		return
	}

	win := ui.NewWindow("hello world", 100, 100, false)
	ui.WindowOnClosing(win, proc "c" (w: ^ui.Window, data: rawptr) -> bool {
		ui.Quit()
		return true
	}, nil)
	vb := ui.NewVerticalBox()
	l := ui.NewButton("hello")
	ui.ButtonOnClicked(l, proc "c" (b: ^ui.Button, data: rawptr) {
		context = runtime.default_context()
		play_playlist("content")
	}, win)
	ui.BoxAppend(vb, l, true)
	ui.WindowSetChild(win, vb)
	ui.ControlShow(win)
	ui.Main()
	ui.Uninit()
}
