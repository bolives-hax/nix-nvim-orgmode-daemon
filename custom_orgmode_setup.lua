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
	        	  vim.system({
	        		  "notify-send",
				  string.format('RISE AND SHINE: %d Tasks on todays agenda',
				  	table.getn(tasks))
	        	  })
	          end
	  end
	  --local msg = "a"
	  -- Linux
	  if vim.fn.executable('notify-send') == 1 then
	    vim.system({
	      'notify-send',
	      	--msg
		title, 9
		--title .. msg,
		,string.format('%s\n%s', subtitle, date)
	    })
	
	    --vim.system({
	    --  'twinkle', '--immediate',
	    --  '--cmd',
	    --})
	  end
  	end
end
