# prelive.nvim

**The plugin is currently a work in progress (WIP).**

`prelive.nvim` is a luv-based server that automatically reloads static pages.

## Features

- Provides a file server function with automatic reloading, ensuring your changes are immediately reflected in the browser.
- Implemented in Lua using `vim.uv`, eliminating the need for Node.js or other external tools.
- Requests are processed asynchronously, so they won't interrupt your editing.
- Offers an API for integration with other plugins, allowing you to build more advanced workflows.

> [!WARNING]
> For security reasons, it is strongly recommended to use this plugin only in a trusted environment.

## Requirements

- Neovim Nightly

## Installation

Install the plugin using your favorite package manager:

lazy.nvim:

```lua
{
  dir = "hat0uma/prelive.nvim",
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
    host = '127.0.0.1',
    port = 2255
  },
  logger = {
    notify_level = vim.log.levels.INFO,
    file_level = vim.log.levels.DEBUG,
    notify = {
      title = 'prelive'
    },
    file = {
      file_path = vim.fn.stdpath('data') .. '/prelive.log',
      max_backups = 3,
      max_file_size = 1024 * 1024
    }
  }
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
