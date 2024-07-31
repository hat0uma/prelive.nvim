vim.api.nvim_create_user_command("PreLiveGo", function(opts)
  local params = vim.split(opts.args, "%s+", { trimempty = true })
  if #params > 2 then
    print("Too many arguments")
    return
  end

  local dir, file ---@type string?,string?
  dir, file = params[1], params[2]
  dir = dir or vim.uv.cwd()
  file = file or vim.api.nvim_buf_get_name(0)
  require("prelive").go(dir, file)
end, {
  nargs = "*",
  complete = "file",
})

vim.api.nvim_create_user_command("PreLiveStatus", function()
  require("prelive").status()
end, {})

vim.api.nvim_create_user_command("PreLiveClose", function()
  require("prelive").select_close()
end, {})

vim.api.nvim_create_user_command("PreLiveCloseAll", function()
  require("prelive").close(nil)
end, {})

vim.api.nvim_create_user_command("PreLiveLog", function()
  require("prelive").open_log()
end, {})
