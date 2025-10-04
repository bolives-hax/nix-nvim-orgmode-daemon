
local print_dbg = false --true --false

function print_error(msg)
	--error("ERROR:" .. msg)
	vim.api.nvim_echo({{"ERROR: "},{msg}}, true , {err = true})
end

function run_command(command)
	local openPop = assert(io.popen(command))
	local output = openPop:read('*all')
	openPop:close()
	if print_dbg then print(output) end
end

local function write_file(path, content)
  local f, err = io.open(path, "wb")
  if not f then
	  return false, err
  end
  f:write(content)
  f:close()
  return true
end

-- TODO this is very limited but we should
-- be able to accept trusted input unless
-- we allow calendar entries to have numbers
-- parsed out of them
function normalize_pstn_simple(str)
  -- remove all whitespace characters
  str = str:gsub("%s+", "")
  if str:sub(1,1) == "+" then
    return "00" .. str:sub(2)
  end
  return str
end

function get_channel(raw_target_str)
  if tostring(raw_target_str):match("^%d%d?%d?%d?$") then
    local channel = "PJSIP/" .. raw_target_str
    -- TODO V turn to vim notify
    if print_dbg then 
    	print(("Target detected as local extension: %s"):format(raw_target_str))
    end
    return channel, raw_target_str
  else
    local pstn = normalize_pstn_simple(raw_target_str)
    local channel = ("Local/%s@from-internal"):format(pstn)
    -- TODO V turn to vim notify
    if print_dbg then 
    	print(("Target detected as external number: %s via dialplan"):format(pstn))
    end
    return channel, pstn
  end
end



function pause_to_wav(wav_file_name)
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
  return wav_file_name

end

function deploy_files(cfg, wav_file_names, target)
	-- this is so you can set e.g 0660 the asterisk group can
	-- remove them again as well (unless you want to keep them)
	local group = ""
	if cfg.group ~= nil then
		group = "-g asterisk"
	end

	local perms = "0640"
	if cfg.perms ~= nil then
		perms = cfg.perms
	end
	for _,f in pairs(wav_file_names) do
		run_command(table.concat({
			"install",
			"-m",perms,
			-- "-o", "asterisk",
			-- TODO set the GROUP!! <disabled as im nonroot rn >
			-- TODO figure out a way in which asterisks deletes the
			-- audiofile if the call succeeded
			group,
			f,
			target
		}, " "))
		-- TODO install doesn't move like "mv" right ?!
		os.remove(f)
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
	local language_model_file = 
		cfg.language_model_file or "/tmp/lm/en_US-amy-low.onnx"

	-- TODO V maybe allow external overriding
	local language_model_config_file = language_model_file .. ".json"
	-- V TODO $(mktemp) as default
	local temp_audio_files_dir = (cfg.temp_audio_files_dir or "/tmp/tempaudio")
	.. "/"

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
    table.concat(setvar_lines, "\n"),
    ""
  }, "\n")
end




--local dummy_tasks = {
--	{
--		title ="wash the dishes",
--		time = "twelve O two",
--	},
--	{
--		title ="Bring out the trash",
--		time = "fourteen thirtythree",
--	},
--	{
--		title ="make dinner",
--		time = "eighteen thirty",
--	},
--}



-- TODO V TODO use table.getn(tasks) instead ig, this is kinda ghetto
-- 		idk why its not here

function vocalize_tasks(tasks)
  local vocalized_tasks = {}
  local _task_count = 0
  for taskno,task in ipairs(tasks) do
  	-- TODO V TODO use getn instead ig, this is kinda ghetto
  	_task_count = _task_count + 1
  	-- rather use static pauses in the cal file,
  	-- speeds things up ...
  	--paused_frag1 = pause_to_wav("pause1.wav")
  	--paused_frag2 = pause_to_wav("pause2.wav")
  	task_title_vocal = say_text_to_wav({}, task.title, "task_".. taskno .. "_title")
  	task_time_vocal = say_text_to_wav({}, task.time, "task_".. taskno .. "_time")
  	-- task_final_vocal = combine_wavs( 
  	-- 	{
  	-- 		task_title_vocal,
  	-- 		--paused_frag1,
  	-- 		--paused_frag2,
  	-- 		task_time_vocal
  	-- 	})
  	table.insert( vocalized_tasks, task_title_vocal)
  	table.insert( vocalized_tasks, task_time_vocal)
  end
  return vocalized_tasks
end

--deploy_wavs({ perms = "0660"},vocalized_tasks , dynamic_sounds_dir)

--lol_frag = say_text_to_wav({},"L O L", "lol")
--
--
--lole_frag = say_text_to_wav({},"LOLE", "lole")
--
--final_frag = combine_wavs( { lol_frag, paused_frag, lole_frag }, "combined")



  --local callfile_name = string.format("%s/notify_%s_%d.call", callfile_dir, target, os.time())

--print(final_frag)

-- dialog_task_ack.wav  dialog_task_try_again.wav  goodbye.wav         greeting_part2.wav
-- dialog_task_ask.wav  gap_200ms.wav              greeting_part1.wav

--x = make_callfile_content({
--	task_count = _task_count,
--	dynamic_sounds_dir = dynamic_sounds_dir,
--	static_sounds_dir = "/nix/store/l747zs99y5x0w987z0kxm2rx1pl14341-asterisk_custom_piper_sounds",
--}, "+385<number>")

--write_file("callfile_test.cf",x)
return {
	say_text_to_wav = say_text_to_wav,
	make_callfile_content = make_callfile_content,
	deploy_files = deploy_files,
	write_file = write_file,
}
