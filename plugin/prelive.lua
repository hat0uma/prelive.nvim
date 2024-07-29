vim.api.nvim_create_user_command("PreLiveGo", function(opts)
  local params = vim.split(opts.args, "%s+", { trimempty = true })
  if #params > 2 then
    print("Too many arguments")
    return
  end

  local dir, file ---@type string?,string?
  dir, file = params[1], params[2]
  dir = dir or vim.uv.cwd()
  file = file or vim.fn.expand("%:~:.")

  -- check directory
  local err
  dir, err = vim.uv.fs_realpath(vim.fs.normalize(dir))
  if not dir then
    vim.notify(err or (dir .. " is not found."))
    return
  end
  if vim.fn.isdirectory(dir) == 0 then
    vim.notify("Not a Directory " .. dir)
    return
  end

  -- check file
  if file == "" or not file then
    file = nil
  else
    file, err = vim.uv.fs_realpath(vim.fs.normalize(file))
    if not file then
      -- can't access to the file
      vim.notify(err or (file .. " is not found."))
    elseif file:sub(1, #dir) == dir then
      -- `file` is in the `dir`
      file = file:sub(#dir + 1)
    else
      file = nil
    end
  end
  require("prelive.api").go(dir, file)
end, { nargs = "*", complete = "file" })

vim.api.nvim_create_user_command("PreLiveStatus", function()
  require("prelive.api").status()
end, {})

vim.api.nvim_create_user_command("PreLiveClose", function()
  require("prelive.api").select_close()
end, {})

vim.api.nvim_create_user_command("PreLiveCloseAll", function()
  require("prelive.api").close(nil)
end, {})

vim.api.nvim_create_user_command("PreLiveLog", function()
  require("prelive.api").open_log()
end, {})
