# 🛠️ Developer Guide for Jukit.nvim

This document outlines the internal architecture of `jukit.nvim` to assist contributors and developers.

## 🏗️ Architecture Overview

Jukit operates on a **Client-Server model** using standard I/O streams over a job channel:

1.  **Client (Neovim/Lua):**
      * Manages the UI (Splits, Floating Windows, Virtual Text).
      * Sends commands (JSON) to the Python process via `stdin`.
      * Receives results (JSON) via `stdout`.
      * Handles SSH tunneling for remote execution.
2.  **Server (Python/IPython):**
      * Runs an instance of `IPython.core.interactiveshell.InteractiveShell`.
      * Intercepts `stdout`/`stderr` to capture execution output.
      * Processes execution requests, magic commands, and introspection.

## 📂 File Structure

The plugin is modularized into specific responsibilities:

  * **`lua/jukit/init.lua`**: Entry point. Sets up user commands, autocommands, and keybindings.
  * **`lua/jukit/core.lua`**: The brain. Handles the Kernel process (`jobstart`), sends payloads, handles SSH logic, and processes incoming JSON events (`on_stdout`).
  * **`lua/jukit/ui.lua`**: The face. Manages Buffers, Windows, Highlights, Notifications, TUI DataFrame viewer, and ANSI-colored REPL output.
  * **`lua/jukit/state.lua`**: The memory. Holds global state like `job_id`, `cell_map` (cell ID to buffer mapping), namespace IDs, and configuration options.
  * **`lua/jukit/config.lua`**: Configuration defaults and setup logic.
  * **`lua/jukit/utils.lua`**: Pure helper functions (ID generation, text parsing).
  * **`lua/jukit/kernel.py`**: The backend. A standalone Python script running the IPython shell.

## 📡 JSON Protocol

Communication between Lua and Python is done via line-delimited JSON.

### Lua -\> Python (Commands)

```json
{"command": "execute", "code": "print('hello')", "cell_id": "abc", "filename": "test.py"}
{"command": "get_variables"}
{"command": "view_dataframe", "name": "df"}
{"command": "plot_tui", "name": "y", "width": 80}
{"command": "save_session", "filename": "sess.pkl"}
```

### Python -\> Lua (Events)

The kernel sends various event types back to Lua:

  * **`stream`**: Real-time text output (stdout/stderr).
  * **`result_ready`**: Execution finished. Contains metadata (markdown path) and error info.
      * Includes `error: { line: int, msg: string }` for inline diagnostics.
  * **`image_saved`**: A plot was generated and saved to disk.
  * **`variable_list`**: Response to `get_variables`.
  * **`dataframe_data`**: Response to `view_dataframe` (contains columns, index, data).
  * **`clipboard_data`**: Formatted text ready for system clipboard.
  * **`profile_stats`**: `cProfile` output text.

## 🐍 Kernel Implementation Details

The `kernel.py` uses `IPython` instead of raw `exec()` for better compatibility.

  * **Stdout Proxy:** We subclass `io.StringIO` to capture all output (including `print` and `display`) and forward it to Neovim as JSON events.
  * **Colors:** We initialize IPython with `colors='Linux'` to generate ANSI color codes, which are rendered natively by Neovim's terminal buffer API (`nvim_open_term`).
  * **SSH Support:** When `ssh_host` is set, `core.lua` uses `scp` to copy `kernel.py` to the remote machine and executes it via `ssh`. The JSON stream is piped back through the SSH connection transparently.

## 🐛 Debugging Tips

1.  **Logs:** Use `print(vim.inspect(...))` in Lua.
2.  **Kernel Output:** If the kernel crashes silently, check `:messages` in Neovim.
3.  **Restarting:** Always run `:JukitRestart` after modifying `kernel.py`. Lua changes usually require reloading Neovim or using `:luafile %`.

