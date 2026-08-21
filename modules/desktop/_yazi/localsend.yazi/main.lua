-- Send the selected (or hovered) entries to LocalSend.
--
-- LocalSend's desktop entry is `localsend_app %U`: launching it with file
-- arguments opens the app pre-loaded with those files ready to send.

local selected_or_hovered = ya.sync(function()
	local tab, paths = cx.active, {}
	for _, url in pairs(tab.selected) do
		paths[#paths + 1] = tostring(url)
	end
	if #paths == 0 and tab.current.hovered then
		paths[1] = tostring(tab.current.hovered.url)
	end
	return paths
end)

local function notify(content, level)
	ya.notify {
		title = "LocalSend",
		content = content,
		level = level,
		timeout = 5,
	}
end

local function has_localsend()
	local output = Command("sh")
		:arg { "-c", "command -v localsend_app" }
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:output()
	return output and output.status.success
end

local function entry()
	local paths = selected_or_hovered()
	if #paths == 0 then
		return notify("Nothing selected or hovered", "warn")
	end

	if not has_localsend() then
		return notify("`localsend_app` is not on PATH; enable programs.localsend", "error")
	end

	-- `nohup` keeps the GUI alive when the terminal running yazi goes away;
	-- NULL stdio prevents it from writing a nohup.out next to the files.
	local child, err = Command("nohup")
		:arg("localsend_app")
		:arg(paths)
		:stdin(Command.NULL)
		:stdout(Command.NULL)
		:stderr(Command.NULL)
		:spawn()

	if not child then
		return notify(string.format("Failed to launch LocalSend: %s", err), "error")
	end

	notify(string.format("Sending %d item(s) via LocalSend", #paths), "info")
end

return { entry = entry }
