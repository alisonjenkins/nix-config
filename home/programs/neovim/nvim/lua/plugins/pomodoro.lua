return {
	dir = "~/.local/share/nvim/nix/pomodoro",
	dependencies = { dir = "~/.local/share/nvim/nix/nui" },
	cmd = {
		"PomodoroStart",
		"PomodoroStop",
		"PomodoroStatus",
	},
	config = function()
		require("pomodoro").setup({
			time_work = 25,
			time_break_short = 5,
			time_break_long = 20,
			timers_to_long_break = 4,
		})
	end,
}
