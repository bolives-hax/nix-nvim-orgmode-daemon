function print_warning(msg)
	--error("ERROR:" .. msg)
	vim.api.nvim_echo({{"WARNING: " .. msg}}, true , {err = false})
end

-- TODO V rename this into print_dbg_verbose
local print_dbg_verbose = false -- true -- false --true --false


function print_error(msg)
	--error("ERROR:" .. msg)
	vim.api.nvim_echo({{"ERROR: " .. msg}}, true , {err = true})
end

local print_dbg = false
local dbg = function(dbg_msg)
	if print_dbg then
		print(dbg_msg)
	end
end
-- TODO decide to set the nvim printer only when configured/detected its running in vim
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


function run_command(command)
	dbg_section_enter("run_command")
	dbg(command)
	local openPop = assert(io.popen(command))
	local output = openPop:read('*all')
	openPop:close()
	if print_dbg_verbose then print(output) end
	dbg_section_leave("run_command")
end

local function write_file(path, content)
  dbg_section_enter("write_file")
  local f, err = io.open(path, "wb")
  if not f then
  	  print_error("while writing to file \"" .. err .. "\":" .. err )
	  return false, err
  end
  f:write(content)
  f:close()
  dbg("wrote to: " .. path)
  dbg_section_leave("write_file")
  return true
end

-- TODO this is very limited but we should
-- be able to accept trusted input unless
-- we allow calendar entries to have numbers
-- parsed out of them
function normalize_pstn_simple(str)
  dbg_section_enter("normalize_pstn_simple")
  -- remove all whitespace characters
  str = str:gsub("%s+", "")
  if str:sub(1,1) == "+" then
    dbg_section_leave("normalize_pstn_simple")
    return "00" .. str:sub(2)
  end
  dbg_section_leave("normalize_pstn_simple")
  return str
end

function get_channel(raw_target_str)
  if tostring(raw_target_str):match("^%d%d?%d?%d?$") then
    local channel = "PJSIP/" .. raw_target_str
    -- TODO V turn to vim notify
    if print_dbg_verbose then 
    	print(("Target detected as local extension: %s"):format(raw_target_str))
    end
    return channel, raw_target_str
  else
    local pstn = normalize_pstn_simple(raw_target_str)
    local channel = ("Local/%s@from-internal"):format(pstn)
    -- TODO V turn to vim notify
    if print_dbg_verbose then 
    	print(("Target detected as external number: %s via dialplan"):format(pstn))
    end
    return channel, pstn
  end
end



function pause_to_wav(wav_file_name)
dbg_section_enter("pause_to_wav")
run_command(
  table.concat({
    "sox",
    "-n",
    "-r",
    "8000",
    "-c",
    "1",
    "-b",
    "16",
    wav_file_name,
    "trim",
    "0.0 0.2"
  }, " ")
)
  dbg_section_leave("pause_to_wav")
  return wav_file_name

end

function deploy_files(cfg, wav_file_names, target,mv)
	dbg_section_enter("deploy_files")
	-- this is so you can set e.g 0660 the asterisk group can
	-- remove them again as well (unless you want to keep them)
	local group = ""
	if cfg.group ~= nil then
		group = cfg.group
	end

	local perms = "0640"
	if cfg.perms ~= nil then
		perms = cfg.perms
	end
	for _,f in pairs(wav_file_names) do
		-- had to add this as I observed a semingly random portion
		-- of calls getting lost ... the underlaying problem seems
		-- to be a race condition where asterisk spool directory
		-- is watched by inotify but the "install" command I guess
		-- first copies the file over AND THEN change the permissions?!
		-- IF now inotify ends up picking up the file BEFORE the permission
		-- change syscall is performed by "install" then asterisk complains
		-- of being unable to read the file and its being deleted.
		if mv then
			run_command(string.format("chown :%s %s",group ,f))
			run_command(string.format("chmod %s %s",perms ,f))
			run_command(string.format("mv %s %s/", f, target))
		else 
			local c = table.concat({
				"install",
				"-m",perms,
				-- "-o", "asterisk",
				-- TODO figure out a way in which asterisks deletes the
				-- audiofile if the call succeeded
				"-g " .. group,
				f,
				"--target-directory=" .. target
			}, " ")

			run_command(c)

			-- TODO install doesn't move like "mv" right ?!
			dbg("removing \"" .. f .. "\"")
			os.remove(f)
		end
		dbg_section_leave("deploy_files")
	end
end

function combine_wavs(wav_file_names,output_name)
	local output_file_name = output_name .. ".wav"
	run_command("sox "
	.. table.concat(wav_file_names, " ")
	..
	" "
	.. output_file_name)
	for _,f in pairs(wav_file_names) do
		assert(os.remove(f))
	end
	return output_file_name
end

-- TODO don't re-construct the same path multiple times
-- TODO remove anything thats hardcoded but doesn't make any
-- sense as a default if it wouldn't work out of the box or notify
-- the user about missing stuff
function say_text_to_wav(cfg,raw_text,output_name)
	dbg_section_enter("say_text_to_wav")

  	if (cfg.language_model_file == nil) then
  	        print_error("cfg.language_model_file not provided to say_text_to_wav(), required for callfile generation")
		-- TODO i don't believe it makes any sense to accept defaults here right?
		assert(false);
  	end
	local language_model_file = cfg.language_model_file

	local language_model_config_file = language_model_file .. ".json"
	if cfg.language_model_config_file == nil then
		print_warning("cfg.language_model_config_file unset, defaulting to: " ..
		language_model_config_file)
	end

	-- V TODO $(mktemp) as default

	if cfg.temp_audio_files_dir == nil then
	  print_error("temp_audio_files_dir not provided, required for callfile generation")
	  assert(true)
	end

	local temp_audio_files_dir = cfg.temp_audio_files_dir .. "/" -- add "/" for good measure
	-- TODO i don't think defaults make sense right?!
	--local temp_audio_files_dir = (cfg.temp_audio_files_dir or "/tmp/tempaudio")

	local temp_speech_file = temp_audio_files_dir .. "/speech.wav"
	local output_name = temp_audio_files_dir .. output_name .. ".wav"
	local temp_text_file  =  temp_audio_files_dir .. "temp_text.txt"

	write_file(temp_text_file, raw_text)

	run_command( table.concat({
		"bash",
		"-c",
		"\"cat " .. temp_text_file .. " | piper"
		.. " --model "
		.. language_model_file
		.. " --config "
		.. language_model_config_file
		.. " --output-file " .. temp_speech_file 
		.. "\""
	}, " "))


	run_command( table.concat({
		"bash",
		"-c",
		"\"cat " .. temp_speech_file  .. " | sox"
		.. " -t wavpcm - "
		.. " -r"
		.. " 8000"
		.. " -c"
		.. " 1"
		.. " -b"
		.. " 16"
		.. " " .. output_name
		.. "\""
	}, " "))

	assert(os.remove( temp_speech_file ))
	assert(os.remove( temp_text_file ))
	dbg_section_leave("say_text_to_wav")
	return output_name 
end


function make_callfile_content(cfg,_target) 
-- defaults / vars for callfile
  local callfile_dir = cfg.callfile_dir 
  local channel,_ptsn_maybe = get_channel(_target)
  local callerid = cfg.callerid or "\"Notifier\" <1000>"
  local max_retries = cfg.max_retries or 0
  local retry_time = cfg.retry_time or 60
  local wait_time = cfg.wait_time or 30
  local context = cfg.context or "notify-challenge"
  -- TODO maybe we should force this instead of ever
  -- accepting defaults
  --                           V within the cfg.context e.g: [notify-challenge] this is the specific extension
  --                             we call into like
  --                             "exten => provide_challenges,1,NoOp(provide challenges start)"
  --                             in my case.

  local extension = cfg.extension or "provide_challenges"
  local priority = cfg.priority or 1

  if cfg.challenge_enabled then
	  challenge_enabled = 1
  else
	  -- if nil OR 0
	  challenge_enabled = 0
  end


  if cfg.challenge_enabled then
	  challenge_enabled = "1"
  else
	  -- if nil OR 0
	  challenge_enabled = "0"
  end

  if (cfg.dynamic_sounds_dir == nil) then
	  print_error("dynamic_sounds_dir not provided, required for callfile generation")
  end

  if (cfg.static_sounds_dir == nil) then
	  print_error("static_sounds_dir not provided,required for callfile generation")
  end

  if (cfg.task_count == nil) then
	  print_error("task_count not provided,required for callfile generation")
  end

  local setvars = {
	  -- TODO V make the makefile respecd CHALLENGE_ENABLED
	  -- 		OR ideally just call another extension
	  CHALLENGE_ENABLED = challenge_enabled,
	  DYNAMIC_SOUNDS_DIR = cfg.dynamic_sounds_dir,
	  -- TODO force this
	  STATIC_SOUNDS_DIR = cfg.static_sounds_dir,
	  TASK_COUNT = cfg.task_count,
  }
  
  local setvar_lines = {}
  for k, v in pairs(setvars) do
    table.insert(setvar_lines, string.format("Setvar: %s=%s", k, tostring(v)))
  end

  return table.concat({
    string.format("Channel: %s", channel),
    --string.format("CallerID: %s", callerid),
    string.format("MaxRetries: %s", tostring(max_retries)),
    string.format("RetryTime: %s", tostring(retry_time)),
    string.format("WaitTime: %s", tostring(wait_time)),
    string.format("Context: %s", context),
    string.format("Extension: %s", tostring(extension)),
    string.format("Priority: %s", tostring(priority)),
    -- V TODO make this optional
    string.format("Archive: %s", "yes"),
    table.concat(setvar_lines, "\n"),
    ""
  }, "\n")
end



return {
	say_text_to_wav = say_text_to_wav,
	make_callfile_content = make_callfile_content,
	deploy_files = deploy_files,
	write_file = write_file,
}
