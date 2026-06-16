package main

import "base:runtime"

import ma "vendor:miniaudio"

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync/chan"
import "core:time"
import "core:thread"
import "core:sys/posix"

CONFIG_DIR_NAME :: ".ohsowrite"

Player_Command :: enum {
	None,
	Play,
	Quit,
}

print_help_message :: proc() {
	fmt.printf("Usage:\n")
	fmt.printf("\t- help: print this message\n")
	fmt.printf("\t- init: initialize project with necessary hidden files\n")
	fmt.printf("\t- bind <name> <file1> <file2> <file3>...: create directory <name> and symlinks to these files\n")
	fmt.printf("\t- play <name>: enter player selection mode and play\n")
	fmt.printf("\t- gui: launch player\n")
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

read_dir_to_filenames :: proc(dir_name: string) -> ([dynamic]string, os.Error) {
	dir_path := strings.join([]string{CONFIG_DIR_NAME, dir_name}, "/")
	defer delete(dir_path)
	if (!os.is_dir(dir_path)) {
		fmt.eprintln("Not a directory")
		return nil, os.General_Error.Not_Exist
	}
	dir, err := os.open(dir_path)
	if err != os.General_Error.None {
		fmt.eprintln("Error opening directory %v", err)
		return nil, err
	}
	defer os.close(dir)
	files, err2 := os.read_all_directory(dir, context.allocator)
	if err2 != nil {
		return nil, err2
	}

	filenames := make([dynamic]string, 0, len(files))
	for file in files {
		append(&filenames, file.fullpath)
	}
	return filenames, nil
}

input_listener :: proc(cmd_chan: chan.Chan(Player_Command)) {
	for {
		buf: [1]u8
		n, _ := os.read(os.stdin, buf[:])
		if n > 0 {
			if buf[0] == 'n' {
				chan.send(cmd_chan, Player_Command.Play)
			} else if buf[0] == 'q' {
				chan.send(cmd_chan, Player_Command.Quit)
				break
			}
		}
	}
}


play_sound :: proc(engine: ^ma.engine, name: string, out_sound: ^ma.sound) -> bool {
	cstr_name := cstring(raw_data(name[:]))
	result := ma.sound_init_from_file(engine, cstr_name, {.STREAM}, nil, nil, out_sound)
	if result != ma.result.SUCCESS {
		fmt.eprintf("Failed to load '%s'. Miniaudio error code: %v\n", name, result)
		return false
	}
	ma.sound_start(out_sound)
	fmt.printf("SUCCESS: Miniaudio started playing '%s'\n", name)
	return true
}

check_and_stop_sound :: proc(sound: ^ma.sound, cmd_chan: chan.Chan(Player_Command)) -> Player_Command {
	defer ma.sound_uninit(sound)

	for ma.sound_is_playing(sound) {
		cmd, ok := chan.try_recv(cmd_chan)
		if ok {
			if cmd == Player_Command.Play {
				ma.sound_stop(sound)
				return Player_Command.Play
			}
			if cmd == Player_Command.Quit {
				ma.sound_stop(sound)
				return Player_Command.Quit
			}
		}
		time.sleep(100 * time.Millisecond)
	}

	return Player_Command.None
}

play_playlist :: proc(name: string) -> os.Error {
	files := read_dir_to_filenames(name) or_return

	old_termios: posix.termios
	posix.tcgetattr(0, &old_termios)
	new_termios := old_termios
	new_termios.c_lflag -= {
		posix.CLocal_Flag_Bits.ECHO,
		posix.CLocal_Flag_Bits.ICANON,
	}
	posix.tcsetattr(0, posix.TC_Optional_Action.TCSANOW, &new_termios)
	defer posix.tcsetattr(0, posix.TC_Optional_Action.TCSANOW, &old_termios)

	engine: ma.engine
	ma.engine_init(nil, &engine)
	defer ma.engine_uninit(&engine)

	cmd_chan, err := chan.create(chan.Chan(Player_Command), 1, context.allocator)
	defer chan.destroy(cmd_chan)

	t := thread.create_and_start_with_poly_data(cmd_chan, input_listener)
	defer thread.destroy(t)

	for file in files {
		sound: ma.sound
		if play_sound(&engine, file, &sound) {
			fmt.printf("Playing: %s\n", file)
			action := check_and_stop_sound(&sound, cmd_chan)
			if action == Player_Command.Quit {
				break
			}
			fmt.println("Finished.")
		}
	}
	fmt.println("Print 'q' to exit")
	for {
		cmd, ok := chan.try_recv(cmd_chan)
		if ok && cmd == .Quit {
			break
		}
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
	case "gui":
		web_play()
	case:
		print_help_message()
	}

}
