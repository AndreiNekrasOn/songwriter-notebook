package main

import ma "vendor:miniaudio"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

CONFIG_DIR_NAME :: ".ohsowrite"

print_help_message :: proc() {
	fmt.printf("Usage:\n")
	fmt.printf("\t- help: print this message\n")
	fmt.printf("\t- init: initialize project with necessary hidden files\n")
	fmt.printf("\t- bind <name> <file1> <file2> <file3>...: create directory <name> and symlinks to these files\n")
	fmt.printf("\t- play <name>: enter player selection mode and play\n")
}

setup_directories :: proc() -> os.Error {
	os.make_directory(CONFIG_DIR_NAME) or_return
	return os.ERROR_NONE
}

bind_files :: proc(name: string, files: ..string) {
	dir_path := strings.join([]string{CONFIG_DIR_NAME, name}, "/")
	defer delete(dir_path)
	err := os.make_directory(dir_path)
	if err != os.ERROR_NONE && err != os.General_Error.Exist {
		fmt.eprintf("Warning: Could not create directory '%s': %v\n", dir_path, err)
		return
	}
	for file in files {
		base_name := os.base(file)
		link_path := strings.join([]string{dir_path, base_name}, "/")
		defer delete(link_path)
		abs_file, err := filepath.abs(file, context.allocator)
		defer delete(abs_file)
		if err != os.ERROR_NONE {
			fmt.eprintf("Warning: Could not resolve absolute path for '%s': %v\n", file, err)
			continue
		}
		err = os.symlink(abs_file, link_path)
		if err != os.ERROR_NONE {
			fmt.eprintf("Warning: Failed to symlink '%s' to '%s': %v\n", file, link_path, err)
		} else {
			fmt.printf("Linked: %s -> %s\n", link_path, file)
		}
	}
}

play_sound_control :: proc(engine: ^ma.engine, name: string) {
	sound: ma.sound
	result :ma.result = ma.sound_init_from_file(engine, cstring(raw_data(name[:])), {.STREAM}, nil, nil, &sound)
	if result != ma.result.SUCCESS {
		fmt.eprintf("Failed to load '%s' (invalid or unsupported file)\n", name)
		return
	}
	defer ma.sound_uninit(&sound)
	ma.sound_start(&sound)
	for ma.sound_is_playing(&sound) {
		time.sleep(100 * time.Millisecond)
	}
}

play_playlist :: proc(name: string) -> os.Error {
	dir_path := strings.join([]string{CONFIG_DIR_NAME, name}, "/")
	defer delete(dir_path)
	if (!os.is_dir(dir_path)) {
		fmt.eprintln("Not a directory")
		return os.General_Error.Not_Exist
	}
	dir, err := os.open(dir_path)
	if err != os.General_Error.None {
		fmt.eprintln("Error opening directory %v", err)
	}
	files := os.read_all_directory(dir, context.allocator) or_return
	engine: ma.engine
	ma.engine_init(nil, &engine)
	defer ma.engine_uninit(&engine)
	for file in files {
		fmt.printf("Playing: %s\n", file.fullpath)
		play_sound_control(&engine, file.fullpath)
		fmt.println("Finished.")
	}
	return os.General_Error.None
}

main :: proc() {
	if len(os.args) < 2 {
		print_help_message()
		return
	}
	switch os.args[1] {
	case "help":
		print_help_message()
	case "init":
		err := setup_directories()
		if err != os.ERROR_NONE {
			fmt.printf("Error occured\n")
			fmt.println(err)
		}
	case "bind":
		if (len(os.args) < 4) {
			print_help_message()
			return
		}
		bind_files(os.args[2], ..os.args[3:])
	case "play":
		if (len(os.args) < 3) {
			print_help_message()
			return
		}
		play_playlist(os.args[2])
	case:
		print_help_message()
	}
}
