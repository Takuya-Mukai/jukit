# Developer Guide for Jovian.nvim

This document explains the internal architecture of `jovian.nvim`.

## Architecture

Jovian works on a **Client-Server model** communicating via standard I/O (stdio).

1.  **Client (Lua):**
    - Starts the Python kernel using `vim.fn.jobstart`.
    - Sends commands as JSON strings to `stdin`.
    - Receives results as JSON strings from `stdout`.
    - Manages Neovim UI (Windows, Virtual Text, Terminal buffers).
2.  **Server (Python):**
    - A standalone script (`kernel.py`) running `IPython.core.interactiveshell.InteractiveShell`.
    - Intercepts `stdout` and `stderr` to capture outputs.
    - Processes JSON commands and executes code.

## File Structure

- **`lua/jovian/init.lua`**: Entry point. Registers commands and autocommands.
- **`lua/jovian/core.lua`**: Core logic. Handles job control, SSH tunneling, and message dispatching.
- **`lua/jovian/ui.lua`**: UI components. Handles window management, TUI rendering, and syntax highlighting.
- **`lua/jovian/state.lua`**: Global state management (job IDs, buffer IDs, etc.).
- **`lua/jovian/kernel.py`**: The Python backend script.

## JSON Protocol

Communication uses line-delimited JSON.

### Commands (Lua -\> Python)

```json
{"command": "execute", "code": "print(1)", "cell_id": "id", "filename": "a.py"}
{"command": "get_variables"}
{"command": "view_dataframe", "name": "df"}
{"command": "profile", "code": "func()", "cell_id": "id"}
```

### Events (Python -\> Lua)

- **`stream`**: Real-time output text.
- **`result_ready`**: Execution finished.
- **`image_saved`**: Matplotlib plot saved.
- **`variable_list`**: Response for `:JovianVars`.
- **`dataframe_data`**: Response for `:JovianView`.
- **`input_request`**: Kernel is requesting user input.

## Kernel Implementation

The kernel leverages `IPython` for execution.

- **Colors:** Initialized with `colors='Linux'` to generate ANSI escape codes, which are rendered by Neovim's terminal API (`nvim_open_term`).
- **SSH:** If `ssh_host` is configured, `core.lua` uses `scp` to copy the kernel script to the remote machine and executes it via `ssh`.

## Troubleshooting

- **Kernel logs:** Check `:messages` in Neovim for Lua errors.
- **Process:** Ensure `python3` (or the SSH remote python) has `ipython` installed.
- **Reloading:** Use `:JovianRestart` to reload the Python kernel. Use `:luafile %` to reload Lua code changes.
