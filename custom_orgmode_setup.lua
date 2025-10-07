-- TODO when we call functions that are nil (like due to a typo) 
-- nvim just seems to swallow them without notice / throwing errors
-- this can be a pain to debug thus this function tries to do a small
-- sanity check
function check_requirements()
	local found_util_count = 0
  local required_utils = {
  	"say_text_to_wav",
  	"make_callfile_content",
  	"deploy_files",
  	"write_file",
  }
  
  for _,util_name in pairs(required_utils) do
	  local found = false
          for matched_util_name,_ in pairs(call_utils) do
        	  if util_name == matched_util_name then
			  found = true
        	  end
          end
	  if not found then
        	vim.api.nvim_echo(
        	        {{"Could not find utility function: \"" .. util_name .. "\""}},
        	        true , {err = true})
	  else
		  found_util_count = found_util_count + 1
	  end
  end

  assert(found_util_count == table.getn(required_utils), string.format(
		  "utility function count = %u while %u utils were expected."
		   , found_util_count, table.getn(required_utils) ))
end

function dbg(s)
        	vim.api.nvim_echo(
        	        {{"debug point \"" .. s .. "\" reached"}},
        	        true , {err = false})
end


function run(tasks)

	-- TODO V in theory we souldn't need this function anymore since
	-- 		i figured out how error handling works now
	check_requirements()
	
	for _, task in ipairs(tasks) do
	  local title = string.format('%s (%s)', task.category, task.humanized_duration)
	  local subtitle = string.format('%s %s %s', string.rep('*', task.level), task.todo, task.title)
	  local date = string.format('%s: %s', task.type, task.time:to_string())
	
	  
	  -- TODO in theory no needed as we can iterate over it when empty
	  -- and then the inner code won't be executed but whatever
	  tagcount = table.getn(task.tags)
	  if tagcount > 0 then
	          --presence of tags may indicate that the task(or muliple if triggered at the same time) requires extra care/handling  
	          local force_count = false
	
	          for _, v in pairs(task.tags) do
	        	  if v == "FORCE_COUNT" then
	        		  force_count = true
	        	  end
	          end
	
	          if force_count then
			  local tasks = require('orgmode').get_agenda_tasks_today()
			  
			  local temp_dir = vim.env.TEMP_DIR or  os.getenv("TEMP_DIR")
			  if temp_dir == nil then
				  print_error("TEMP_DIR is unset!")
				  -- TODO make it so that if we are NOT running as a systemd service
				  -- 		we create a dir under /tmp/ and use that ... but systemd
				  -- 			provides /run/
			  end

			  local static_sounds_dir = vim.env.STATIC_SOUNDS_DIR or os.getenv("STATIC_SOUNDS_DIR")
			  if static_sounds_dir == nil then
				  print_error("STATIC_SOUNDS_DIR is unset!")
				  -- TODO make it so that if we are NOT running as a systemd service
				  -- 		we create a dir under /tmp/ and use that ... but systemd
				  -- 			provides /run/
			  end

			  local call_target = vim.env.CALL_TARGET or os.getenv("CALL_TARGET")
			  if call_target == nil then
				  print_error("CALL_TARGET is unset!")
				  -- TODO make it so that if we are NOT running as a systemd service
				  -- 		we create a dir under /tmp/ and use that ... but systemd
				  -- 			provides /run/
			  end

			  local audio_files_output_dir = vim.env.AUDIO_DIR or  os.getenv("AUDIO_DIR")
			  if audio_files_output_dir == nil then
				  print_error("AUDIO_DIR is unset!!")
			  end

			  perform_task_call(
				{
					audio_files_output_dir = audio_files_output_dir,
					temp_callfile_dir  = temp_dir,
					temp_audio_files_dir = temp_dir,
			  	},
			  	tasks,
			  	call_utils,
			  	call_target,
			  	static_sounds_dir
			  )



	          end
	  end
	end
end

function print_error(error_msg)
	vim.api.nvim_echo(
	        {{"error: \"" .. error_msg .. "\""}},
	        true , {err = true})
	assert(false)
end
-- makeshift try_run()
return function(tasks)
	if tasks == nil then
		print_error("function called with tasks == nil")
	elseif table.getn(tasks) < 1 then
		--print_error("function called with under 1 task")
		print("function called without any tasks ... doing nothing")
	else
		local ok,result = pcall(function()
			run(tasks)
		end)

		if not ok then
			print_error("run(tasks) failed with: \"" .. result.. "\"")
		end
	end
end
