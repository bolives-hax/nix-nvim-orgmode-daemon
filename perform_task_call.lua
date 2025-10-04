
function vocalize_tasks(tasks,say_text_to_wav,audio_files_dir)
	local vocalized_tasks = {}
	local say_text_to_wav_cfg = {
	        -- TODO language_model_file,
	        -- TODO
	        temp_audio_files_dir = audio_files_dir,
	}
	for taskno,task in ipairs(tasks) do
	        task_title_vocal = say_text_to_wav(
	      	  say_text_to_wav_cfg , task.title, "task_" .. taskno .. "_title")
	
	        task_time_vocal = say_text_to_wav(
	      	  say_text_to_wav_cfg, "13 54", "task_" .. taskno .. "_time")
	
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
	end
	vim.api.nvim_echo(
	        {{"moved " .. temp_audio_files_dir }},
	        true , {err = false})

	-- this is the location referenced by the callfile, asterisk will
	-- try to get the audio from after initiating the call ... thus asterisks
	-- needs to at least have rx permission on the dir and r on the file
	local audio_files_output_dir = vim.env.XDG_STATE_HOME or  os.getenv("XDG_STATE_HOME")
	if cfg.audio_files_output_dir ~= nil then
		-- TODO install command will fail if runtime/state dir are the same
		-- do something about this
		audio_files_output_dir = cfg.audio_files_output_dir
	end

	-- where the callfile will be placed BEFORE being moved into the
	-- asterisk spool dir. (useful in case one wants to debug it)
	local temp_callfile_dir  =  vim.env.XDG_RUNTIME_DIR or os.getenv("XDG_RUNTIME_DIR")
	if cfg.temp_callfile_dir ~= nil then
		temp_callfile_dir  = cfg.temp_callfile_dir
	end
	-- TODO append the date to the callfile
	local temp_callfile_path  = temp_callfile_dir .. os.date("%w_%m_%H_%M_%S_%Y") .. "_orgmode.cf"

	local spool_dir = "/var/spool/asterisk/outgoing/"
	
	local vocalized_tasks = vocalize_tasks(
		tasks,
		call_utils.say_text_to_wav,
		temp_audio_files_dir
	);
	
	
	
	
	
	call_utils.deploy_files({
		group = "asterisk",
		-- TODO use 066 if you want asterisk to be able to remove it
		-- if you configured it to do so
	        perms = "0660",
	}, vocalized_tasks, audio_files_output_dir)
	
	callfile_content = call_utils.make_callfile_content({
	        task_count = table.getn(tasks),
	        dynamic_sounds_dir = audio_files_output_dir,
	        static_sounds_dir = static_sounds_dir,
	}, target );

	
	--call_utils.write_file(temp_callfile, callfile)
	local f, err , code = io.open(temp_callfile_path, "wb")
	if not f then
		vim.api.nvim_echo({{"ERR writing da file"}}, true , {err = true})
	        return false, err
	end
	f:write(callfile_content)
	f:close()
	
	
	call_utils.deploy_files({
		-- TODO it appears as if setting the group to asterisk doens't make it
		-- writable for asterisk automatically. It not being writeable will not cause
		-- asterisk to mark it as onging and thus after a few seconds it will re-dial
		-- eventhough the call is still onging. To prevent this ensure the file is
		-- readable
		--group = "asterisk",
	        perms = "0666"
	}, {temp_callfile_path }, spool_dir)

	vim.api.nvim_echo(
	        {{"moved " .. temp_callfile_path .. " to " .. spool_dir }},
	        true , {err = false})
	

end
