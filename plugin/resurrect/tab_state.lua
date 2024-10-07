local wezterm = require("wezterm")
local pane_tree_mod = require("resurrect.pane_tree")
local pub = {}

---Function used to split panes when mapping over the pane_tree
---@param opts restore_opts
---@return fun(acc: {active_pane: Pane, is_zoomed: boolean}, pane_tree: pane_tree): {active_pane: Pane, is_zoomed: boolean}
local function make_splits(opts)
	if opts == nil then
		opts = {}
	end

	return function(acc, pane_tree)
		local pane = pane_tree.pane

		if opts.on_pane_restore then
			opts.on_pane_restore(pane_tree)
		end

		local bottom = pane_tree.bottom
		if bottom then
			local split_args = { direction = "Bottom", cwd = bottom.cwd }
			if opts.relative then
				split_args.size = bottom.height / (pane_tree.height + bottom.height)
			elseif opts.absolute then
				split_args.size = bottom.height
			end

			bottom.pane = pane:split(split_args)
		end

		local right = pane_tree.right
		if right then
			local split_args = { direction = "Right", cwd = right.cwd }
			if opts.relative then
				split_args.size = right.width / (pane_tree.width + right.width)
			elseif opts.absolute then
				split_args.size = right.width
			end

			right.pane = pane:split(split_args)
		end

		if pane_tree.is_active then
			acc.active_pane = pane_tree.pane
		end

		if pane_tree.is_zoomed then
			acc.is_zoomed = true
		end

		return acc
	end
end

---creates and returns the state of the tab
---@param tab MuxTab
---@return tab_state
function pub.get_tab_state(tab)
	local panes = tab:panes_with_info()

	local function is_zoomed()
		for _, pane in ipairs(panes) do
			if pane.is_zoomed then
				return true
			end
		end
		return false
	end

	local tab_state = {
		title = tab:get_title(),
		is_zoomed = is_zoomed(),
		pane_tree = pane_tree_mod.create_pane_tree(panes),
	}

	return tab_state
end

---restore a tab
---@param tab MuxTab
---@param tab_state tab_state
---@param opts restore_opts
function pub.restore_tab(tab, tab_state, opts)
	wezterm.emit("resurrect.tab_state.restore_tab.start")
	if opts.pane then
		tab_state.pane_tree.pane = opts.pane
	else
		tab_state.pane_tree.pane = tab:active_pane()
	end

	if tab_state.title then
		tab:set_title(tab_state.title)
	end

	local acc = pane_tree_mod.fold(tab_state.pane_tree, { is_zoomed = false }, make_splits(opts))
	acc.active_pane:activate()
	wezterm.emit("resurrect.tab_state.restore_tab.finished")
end

function pub.save_tab_action()
	return wezterm.action_callback(function(win, pane)
		local tab = pane:tab()
		if tab:get_title() == "" then
			win:perform_action(
				wezterm.action.PromptInputLine({
					description = "Enter new tab title",
					action = wezterm.action_callback(function(_, callback_pane, title)
						if title then
							callback_pane:tab():set_title(title)
							local state = pub.get_tab_state(tab)
							pub.save_state(state)
						end
					end),
				}),
				pane
			)
		elseif tab:get_title() then
			local state = pub.get_tab_state(tab)
			pub.save_state(state)
		end
	end)
end

--- Function to restore text or processes when restoring panes
---@param pane_tree pane_tree
function pub.default_on_pane_restore(pane_tree)
	local pane = pane_tree.pane

	-- Spawn process if using alt screen, otherwise restore text
	if pane_tree.alt_screen_active then
		pane:send_text(wezterm.shell_join_args(pane_tree.process.argv) .. "\r\n")
	else
		pane:inject_output(pane_tree.text:gsub("%s+$", ""))
	end
end

return pub
