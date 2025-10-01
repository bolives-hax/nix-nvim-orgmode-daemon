return function(tasks)
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
	
	          if force_count  then
			  local tasks = require('orgmode').get_agenda_tasks_today()

			  prog_name = "call_sip"
			  task_count = table.getn(tasks)
			  greeting = string.format(
				  "Rise and shine Mister freeman, you have %u tasks on your agenda today.",
				  task_count)
			  tasks_listing = ""

			  for taskno,task in ipairs(tasks) do
				  tasks_listing = 
				  string.format("%s Task number: %u: %s",
				  tasks_listing, taskno, task.title)
			  end
			  tasks_listing = tasks_listing .. " these were all tasks"


			  -- TODO allow this to be  passed via an env var or read in from a json file
			  number = "+3851580000000"
			  local res = vim.system({"call_sip", greeting, tasks_listing, number}, {text = true}):wait()
			  if res.code ~= 0 then
				-- for some reason this takes place 
				vim.api.nvim_echo({{"ERROR: "}, {res.stderr}}, true , {err = true})
			  else
			  	vim.api.nvim_echo({{"call to: "}, {number}, {"succeeded\n"} ,{res.stdout}}, true , {err = true})
			  end
	          end
	  end
	end
end
