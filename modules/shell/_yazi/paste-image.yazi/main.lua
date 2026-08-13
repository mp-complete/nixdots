local cwd = ya.sync(function()
	local current = cx.active.current.cwd
	if current.scheme.is_virtual then
		return nil
	end
	return tostring(current)
end)

local function notify(content, level)
	ya.notify {
		title = "Paste clipboard image",
		content = content,
		level = level,
		timeout = 5,
	}
end

local function entry()
	if not os.getenv("WSL") and not os.getenv("WSL_DISTRO_NAME") and not os.getenv("WSL_INTEROP") then
		return notify("This plugin is only available in WSL", "warn")
	end

	local directory = cwd()
	if not directory then
		return notify("Images cannot be saved in a virtual directory", "warn")
	end

	local name = ya.input {
		pos = { "center", w = 50 },
		title = "Image name:",
		value = "image.png",
	}
	if not name then
		return
	end

	name = name:match("^%s*(.-)%s*$")
	if name == "" then
		return
	elseif name == "." or name == ".." or name:find("[/\\]") then
		return notify("Enter a filename, not a path", "error")
	elseif not name:lower():match("%.png$") then
		name = name .. ".png"
	end

	local target = Url(directory):join(name)
	if fs.cha(target) then
		local overwrite = ya.confirm {
			pos = { "center", w = 60, h = 10 },
			title = "Overwrite image?",
			body = ui.Text(string.format("%s already exists. Replace it?", name)):wrap(ui.Wrap.YES),
		}
		if not overwrite then
			return
		end
	end

	local output, err = Command("sh")
		:arg {
			"-c",
			[[
set -eu
target=$1
tmp=$(mktemp -- "${target}.tmp.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
clp --image >"$tmp"
mv -f -- "$tmp" "$target"
trap - EXIT
]],
			"paste-image",
			name,
		}
		:cwd(directory)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output then
		return notify(string.format("Failed to run clp: %s", err), "error")
	elseif not output.status.success then
		local message = output.stderr:gsub("%s+$", "")
		if message == "" then
			message = string.format("clp exited with status %s", output.status.code)
		end
		return notify(message, "error")
	end

	ya.emit("reveal", { target, raw = true })
	notify(string.format("Saved %s", name), "info")
end

return { entry = entry }
