vim.api.nvim_create_user_command("PreliveGo", function()
  local dir = vim.uv.cwd() or ""
  local file = vim.api.nvim_buf_get_name(0)
  if file ~= "" then
    file = vim.fn.fnamemodify(file, ":~:.")
  end
  require("prelive.api").go(dir, file)
end, {})

vim.api.nvim_create_user_command("PreliveStatus", function()
  require("prelive.api").status()
end, {})

vim.api.nvim_create_user_command("PreliveClose", function()
  require("prelive.api").select_close()
end, {})

vim.api.nvim_create_user_command("PreliveCloseAll", function()
  require("prelive.api").close(nil)
end, {})

vim.api.nvim_create_user_command("PreliveLog", function()
  require("prelive.api").open_log()
end, {})
