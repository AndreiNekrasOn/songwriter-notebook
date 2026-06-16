package main

import "core:path/filepath"
import "core:os"
import "core:strings"

get_playlist :: proc() -> [dynamic]string {
	playlists := make([dynamic]string, 0)
	dir, err := os.open(CONFIG_DIR_NAME)
	if err != os.General_Error.None {
		return playlists
	}
	defer os.close(dir)
	files, err2 := os.read_all_directory(dir, context.allocator)
	if err2 != nil {
		return playlists
	}
	for file in files {
		if os.is_dir(file.fullpath) {
			append(&playlists, file.name)
		}
	}
	return playlists
}

get_songs :: proc(playlist_name: string) -> [dynamic]string {
	songs := make([dynamic]string, 0)
	dir_path := strings.join([]string{CONFIG_DIR_NAME, playlist_name}, "/")
	defer delete(dir_path)
	dir, err := os.open(dir_path)
	if err != os.General_Error.None {
		return songs
	}
	defer os.close(dir)
	files, err2 := os.read_all_directory(dir, context.allocator)
	if err2 != nil {
		return songs
	}
	for file in files {
		if strings.has_suffix(file.name, ".mp3") {
			// Store the full path for the audio engine
			append(&songs, file.fullpath)
		}
	}
	return songs
}

get_lyrics :: proc(mp3_fullpath: string) -> string {
	base := strings.trim_suffix(os.base(mp3_fullpath), ".mp3")
	dir := os.dir(mp3_fullpath)
	base_path, _ := filepath.join({dir, base})
	txt_path := strings.join({base_path, ".txt"}, "")
	md_path := strings.join({base_path, ".md"}, "")
	if os.exists(txt_path) {
		text, err := os.read_entire_file_from_path(txt_path, context.allocator)
		if err == os.General_Error.None {
			return string(text)
		}
	} else if os.exists(md_path) {
		text, err := os.read_entire_file_from_path(md_path, context.allocator)
		if err == os.General_Error.None {
			return string(text)
		}
	}
	return "No lyrics or notes found for this song."
}

stcs :: proc(s: string) -> cstring {
	return cstring(raw_data(s[:]))
}

