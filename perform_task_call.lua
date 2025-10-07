function print_warning(msg)
	--error("ERROR:" .. msg)
	vim.api.nvim_echo({{"WARNING: " .. msg}}, true , {err = false})
end

-- TODO avoid double definitions from gen_callfile.lua
function print_error(msg)
	--error("ERROR:" .. msg)
	vim.api.nvim_echo({{"ERROR: " .. msg}}, true , {err = true})
	assert(false)
end


local print_dbg = false
local dbg = function(dbg_msg)
	if print_dbg then
		print(dbg_msg)
	end
end

dbg = function(dbg_msg)
	if print_dbg then
		vim.api.nvim_echo({{"\tdbg:" .. dbg_msg}}, true , {err = false})
	end
end

function dbg_section_enter(section_name)
	if print_dbg then
		vim.api.nvim_echo({{"dbg START section[" .. section_name .."]:" }}, true , {err = false})
	end
end
function dbg_section_leave(section_name)
	if print_dbg then
		vim.api.nvim_echo({{"dbg END section[" .. section_name .."]:" }}, true , {err = false})
	end
end

-- TODO add more complex behaviors
function vocalize_tasks(tasks,say_text_to_wav,audio_files_dir,language_model_file)
	local vocalized_tasks = {}
	local say_text_to_wav_cfg = {
	        language_model_file = language_model_file,
	        temp_audio_files_dir = audio_files_dir,
	}
	for taskno,task in ipairs(tasks) do
		local hour = task.time:format("%H")
		local minute =  task.time:format("%M")
	  	local date = string.format('%s: at %s o %s', task.type, hour, minute)
	        task_title_vocal = say_text_to_wav(
	      	  say_text_to_wav_cfg , task.title, "task_" .. taskno .. "_title")
	
	        task_time_vocal = say_text_to_wav(
	      	  say_text_to_wav_cfg, date , "task_" .. taskno .. "_time")
	
	        table.insert( vocalized_tasks, task_title_vocal)
	        table.insert( vocalized_tasks, task_time_vocal)
	end
	return vocalized_tasks
end

-- target = the number to call (sip / pstn)
return function(cfg,tasks,call_utils,target,static_sounds_dir)

	-- location any temporary files created=>required  for the audio synthesis go

	local temp_audio_files_dir =  vim.env.XDG_RUNTIME_DIR or os.getenv("XDG_RUNTIME_DIR")
	if cfg.temp_audio_files_dir ~= nil then
		temp_audio_files_dir = cfg.temp_audio_files_dir
	else
		fallback_var = "XDG_RUNTIME_DIR"
		print_warning("neither cfg.temp_audio_files_dir nor environment variable TEMP_CALLFILE_DIR is unset, defaulting to: " .. fallback_var)
	end

	-- this is the location referenced by the callfile, asterisk will
	-- try to get the audio from after initiating the call ... thus asterisks
	-- needs to at least have rx permission on the dir and r on the file
	local audio_files_output_dir = vim.env.XDG_STATE_HOME or  os.getenv("XDG_STATE_HOME")
	if cfg.audio_files_output_dir ~= nil then
		-- TODO install command will fail if runtime/state dir are the same
		-- do something about this
		audio_files_output_dir = cfg.audio_files_output_dir
	else
		print_warning("neither cfg.audio_files_output_dir nor AUDIO_DIR is set, defaulting to XDG_STATE_HOME")
		if audio_files_output_dir == nil then
			print_error("XDG_STATE_HOME unavailable .. running as a sytemd service?")
		end
	end

	-- where the callfile will be placed BEFORE being moved into the
	-- asterisk spool dir. (useful in case one wants to debug it)
	local temp_callfile_dir  =  vim.env.TEMP_CALLFILE_DIR or os.getenv("TEMP_CALLFILE_DIR")

	if cfg.temp_callfile_dir ~= nil then
		temp_callfile_dir  = cfg.temp_callfile_dir
	end

	if temp_callfile_dir == nil then
		local fallback_var = "XDG_RUNTIME_DIR"
		print_warning("neither cfg.temp_callfile_dir nor environment variable TEMP_CALLFILE_DIR is unset, defaulting to: " .. fallback_var)
		temp_callfile_dir  =  vim.env.XDG_RUNTIME_DIR or os.getenv(fallback_var)

		if temp_callfile_dir == nil then
			print_warning("TEMP_CALLFILE_DIR is UNSET!!")
			-- TODO maybe fallback to some /tmp path 
			assert(false)
		end
	end


	local language_model_file = vim.env.LANGUAGE_MODEL_FILE or os.getenv("LANGUAGE_MODEL_FILE")
	-- TODO decide if it would make sense to panic instead
	if language_model_file == nil then
		print_warning("environment variable LANGUAGE_MODEL_FILE is UNSET!!")
	end
	-- TODO append the date to the callfile
	local temp_callfile_path  = temp_callfile_dir .. os.date("%w_%m_%H_%M_%S_%Y") .. "_orgmode.cf"



	local spool_dir = "/var/spool/asterisk/outgoing/"

	
	local vocalized_tasks = vocalize_tasks(
		tasks,
		call_utils.say_text_to_wav,
		temp_audio_files_dir,
		language_model_file
	);
	
	
	call_utils.deploy_files({
		group = "asterisk",
		-- TODO use 066 if you want asterisk to be able to remove it
		-- if you configured it to do so
	        perms = "0660",
	}, vocalized_tasks, audio_files_output_dir, false)




	
	callfile_content = call_utils.make_callfile_content({
	        task_count = table.getn(tasks),
	        dynamic_sounds_dir = audio_files_output_dir,
	        static_sounds_dir = static_sounds_dir,
	}, target );

	
	--call_utils.write_file(temp_callfile, callfile)
	local f, err , code = io.open(temp_callfile_path, "wb")
	if not f then
		print_error("writing to file \"" .. temp_callfile_path .. "\":" .. "\"err\"")
	        return false, err
	end
	f:write(callfile_content)
	f:close()
	
	-- vim.api.nvim_echo({{callfile_content}}, true , {err = false})
	
	
	call_utils.deploy_files({
		-- TODO it appears as if setting the group to asterisk doens't make it
		-- writable for asterisk automatically. It not being writeable will not cause
		-- asterisk to mark it as onging and thus after a few seconds it will re-dial
		-- eventhough the call is still onging. To prevent this ensure the file is
		-- readable
		group = "asterisk",
	        perms = "0777"
	}, {temp_callfile_path }, spool_dir, true)

	-- TODO introduce more advanced debug settings
	if true then
		print("     CALLFILE BEGIN     ");
		print("------------------------");
		print(callfile_content)
		print("------------------------");
		print("      CALLFILE END      ");
	end

	dbg("callfile/audio COMPLETED moving \"" .. temp_callfile_path .. "\" to \"" .. spool_dir .. "\"")
	

end
