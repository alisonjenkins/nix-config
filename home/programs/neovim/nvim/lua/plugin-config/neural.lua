local Config = {
	use_neural = false,
}

local api = vim.api

local ok, cjson = pcall(require, "cjson")

if not ok then
	api.nvim_err_writeln("Error unable to load cjson")
end

-- Check if the directories exist
local config_dir = os.getenv("HOME") .. "/.config/openapi"
local success, mkdir_error_message = os.execute("mkdir -p " .. config_dir)
if not success then
	api.nvim_err_writeln("Error: " .. mkdir_error_message)
	return
end

-- Check if the file exists
local file_path = config_dir .. "/neural"

local file, read_file_error_message = io.open(file_path, "r")
if file then
	-- Read and deserialize the contents of the file
	local contents = file:read("*all")
	file:close()

	Config = cjson.decode(contents)
	if not Config then
		api.nvim_err_writeln("Error: Failed to deserialize config file")
		return
	end

	-- Check if neural should be used
	if not Config.use_neural then
		return
	end
else
	local response = ""

	-- Reprompt the user for input until they respond with 'y', 'n', or 's'
	while response:lower() ~= "y" and response:lower() ~= "n" and response:lower() ~= "s" do
		response = api.nvim_call_function(
			"input",
			{ "Do you want to use the Neural plugin? (https://github.com/dense-analysis/neural) [y/n/s] " }
		)
	end

	if response:lower() == "n" then
		-- Save the configuration to a serialized hash in the specified file
		Config = {
			use_neural = false,
		}
		local file, error_message = io.open(file_path, "w")
		if not file then
			api.nvim_err_writeln("Error: " .. error_message)
			return
		end
		file:write(cjson.encode(Config))
		file:close()
		return
	elseif response:lower() == "s" then
		return
	end

	-- Ask the user for the OpenAPI API key
	local api_key = api.nvim_call_function("input", { "Please enter your OpenAPI API key: " })

	-- Save the API key and configuration to a serialized hash in the specified file
	Config = {
		use_neural = true,
		api_key = api_key,
	}

	local file, error_message = io.open(file_path, "w")
	if not file then
		api.nvim_err_writeln("Error: " .. error_message)
		return
	end
	file:write(cjson.encode(Config))
	file:close()
end

require("neural").setup({
	mappings = {
		swift = "<C-n>", -- Context completion
		prompt = nil, -- Open prompt
	},
	open_ai = {
		api_key = Config.api_key,
	},
})
