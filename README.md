# prelive.nvim

`prelive.nvim` is a simple luv-based development server with live reloading for Neovim.

![prelive](https://github.com/user-attachments/assets/bc9b5ee5-22c8-4137-93c1-f0d964b67c72)

**The plugin is currently a work in progress (WIP).**

## Features

- Provides a file server function with automatic reloading, ensuring your changes are immediately reflected in the browser.
- Implemented in Lua using `vim.uv`, eliminating the need for Node.js or other external tools.
- Requests are processed asynchronously, so they won't interrupt your editing.
- Offers an API for integration with other plugins, allowing you to build more advanced workflows.

> [!IMPORTANT]
> For security reasons, it is recommended to use this plugin only in a trusted environment.

## Requirements

- Neovim Nightly

## Installation

Install the plugin using your favorite package manager:

lazy.nvim:

```lua
{
  "hat0uma/prelive.nvim"
  opts = {},
  cmd = {
    "PreLiveGo",
    "PreLiveStatus",
    "PreLiveClose",
    "PreLiveCloseAll",
    "PreLiveLog",
  },
}
```

vim-plug:

```vim
Plug 'hat0uma/prelive.nvim'
lua require('prelive').setup {}
```

## Configuration

The `setup` function accepts a table with the following options:

```lua
require('prelive').setup {
  server = {
    --- The host to bind the server to.
    --- It is strongly recommended not to expose it to the external network.
    host = "127.0.0.1",
    --- The port to bind the server to.
    --- If the value is 0, the server will bind to a random port.
    port = 2255,
  },
  log = {
    --- The log levels to print.
    --- The log levels are defined in `vim.log.levels`. see `vim.log.levels`.
    print_level = vim.log.levels.WARN,
    --- The log levels to write to the log file. see `vim.log.levels`.
    file_level = vim.log.levels.DEBUG,
    --- The maximum size of the log file in bytes.
    --- If 0, it does not output.
    max_file_size = 1 * 1024 * 1024,
    --- The maximum number of log files to keep.
    max_backups = 3,
  },
}
```

## Usage

### Commands

- `:PreLiveGo [dir] [file]`: Start the server and open the specified file in the browser. If no arguments are provided, the current working directory (cwd) is served and the current buffer file is opened in the browser.
- `:PreLiveStatus`: Show the status of the served directories and open one in the browser.
- `:PreLiveClose`: Select a directory to stop serving.
- `:PreLiveCloseAll`: Stop serving all directory.
- `:PreLiveLog`: Open the log file in a new tab.

### Example

Start the server with the current working directory and open the current buffer file in the browser:

```vim
:PreLiveGo
```

Start the server and serve a specific directory:

```vim
:PreLiveGo ./folder
```

Serve a specific file and open it in the browser:

```vim
:PreLiveGo ./folder file.html
```

## API

TODO

## License

This plugin is licensed under the MIT License.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request on GitHub.
