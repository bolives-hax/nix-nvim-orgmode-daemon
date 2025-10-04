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


return function(tasks)
	check_requirements()
	
	for _, task in ipairs(tasks) do
	  local title = string.format('%s (%s)', task.category, task.humanized_duration)
	  local subtitle = string.format('%s %s %s', string.rep('*', task.level), task.todo, task.title)
	  local date = string.format('%s: %s', task.type, task.time:to_string())
	
	  
	  local urgency = "--urgency=normal"
	  --if task.priority ~= nil then
	  --        urgency = ({
	  --      	  "A" = "critical",
	  --      	  "B" = "normal",
	  --      	  "C" = "low"
	  --        })[task.priority]
	  --end
	
	  
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
			  

			  perform_task_call({
				  audio_files_output_dir = vim.env.AUDIO_DIR or  os.getenv("AUDIO_DIR"),
				  temp_callfile_dir  = vim.env.TEMP_DIR or  os.getenv("TEMP_DIR"),
				  temp_audio_files_dir = vim.env.TEMP_DIR or  os.getenv("TEMP_DIR"),
			  },tasks,call_utils,vim.env.CALL_TARGET or os.getenv("CALL_TARGET"),
			  vim.env.STATIC_SOUNDS_DIR or os.getenv("STATIC_SOUNDS_DIR"))



	          end
	  end
	end
end
