# 🪐 Jovian.nvim

**Jovian.nvim** is a plugin that provides a Jupyter Notebook-like environment within Neovim.

It uses the **IPython** kernel to execute code, allowing you to use magic commands, visualize data in the terminal, and view plots, all without leaving your editor. It is designed to be a lightweight, keyboard-centric alternative to browser-based notebooks.

## Features

- **IPython Kernel:** Supports standard magic commands (`!ls`, `%time`, `%cd`) and execution.
- **Output Split:** Displays execution results (stdout/stderr) in a dedicated split window.
- **Data Viewer:** View `pandas` DataFrames and `numpy` arrays in a floating window (`:JovianView`).
- **Variable Explorer:** Displays a list of active variables, their types, and shapes (`:JovianVars`).
- **Inline Diagnostics:** Python errors are highlighted in the code buffer using Neovim's diagnostic interface.
- **Plotting:**
  - **TUI:** Renders charts directly in the terminal using Braille characters (`:JovianPlotTUI`).
  - **Image:** Saves `matplotlib` plots to disk and generates a Markdown preview.
- **SSH Remote:** Supports executing code on a remote server via SSH.
- **Session:** Saves/Loads the workspace variables using `dill` (`:JovianSaveSession`).
- **Profiling:** Runs `cProfile` on a cell and displays the statistics (`:JovianProfile`).

## Requirements

- **Neovim** (v0.9.0 or later)

- **Python 3**

- **Python Packages:**
  - **Required:** `ipython` (Required for the kernel).
  - **Recommended:** `pandas`, `numpy`, `matplotlib`.
  - **Optional:** `uniplot` (for terminal plotting), `dill` (for session saving).

  <!-- end list -->

  ```bash
  pip install ipython pandas numpy matplotlib uniplot dill
  ```

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "your-username/jovian.nvim", -- Or local path: dir = "~/path/to/jovian.nvim"
    ft = "python",
    config = function()
        require("jovian").setup({
            python_interpreter = "python3",
            -- notify_threshold = 10, -- Notification if execution takes > 10s
        })
    end
}
```

## Configuration

Default settings:

```lua
require("jovian").setup({
    -- UI
    preview_width_percent = 40,
    repl_height_percent = 30,

    -- Python Environment
    python_interpreter = "python3",

    -- SSH Remote (Optional)
    -- ssh_host = "user@hostname",
    -- ssh_python = "/usr/bin/python3",

    -- Visuals
    flash_highlight_group = "Visual",
    flash_duration = 300,

    -- Behavior
    notify_threshold = 10,
})
```

## Keybindings

This plugin does not define any keybindings by default. It is recommended to add the following to your `init.lua`:

```lua
local map = vim.keymap.set

-- Window Management
map("n", "<leader>jo", "<cmd>JovianOpen<cr>", { desc = "Open Windows" })
map("n", "<leader>jt", "<cmd>JovianToggle<cr>", { desc = "Toggle Windows" })

-- Execution
map("n", "<leader>r", "<cmd>JovianRun<cr>", { desc = "Run Cell" })
map("n", "<leader>R", "<cmd>JovianRunAll<cr>", { desc = "Run All" })
map("n", "<leader>rp", "<cmd>JovianProfile<cr>", { desc = "Profile Cell" })

-- Data & Tools
map("n", "<leader>jv", "<cmd>JovianVars<cr>", { desc = "Variables" })
map("n", "<leader>jd", "<cmd>JovianView<cr>", { desc = "Data Viewer" })
map("n", "<leader>jp", "<cmd>JovianPlotTUI<cr>", { desc = "TUI Plot" })
map("n", "<leader>ce", "<cmd>JovianClearDiag<cr>", { desc = "Clear Diagnostics" })

-- Session
map("n", "<leader>ss", "<cmd>JovianSaveSession<cr>", { desc = "Save Session" })
map("n", "<leader>sl", "<cmd>JovianLoadSession<cr>", { desc = "Load Session" })

-- Kernel Control
map("n", "<leader>kk", "<cmd>JovianRestart<cr>", { desc = "Restart Kernel" })
map("n", "<leader>ki", "<cmd>JovianInterrupt<cr>", { desc = "Interrupt Kernel" })
```

## Commands

| Command                | Description                                                      |
| :--------------------- | :--------------------------------------------------------------- |
| `:JovianOpen`          | Opens the Output/REPL windows. **Must be run before execution.** |
| `:JovianRun`           | Executes the current code cell.                                  |
| `:JovianView [var]`    | Opens a spreadsheet viewer for a DataFrame/Array.                |
| `:JovianVars`          | Displays a list of active variables.                             |
| `:JovianPlotTUI [var]` | plots a list/array in the REPL using Braille characters.         |
| `:JovianCopy [var]`    | Copies a DataFrame/Array to the clipboard as Markdown/CSV.       |
| `:JovianSaveSession`   | Saves variables to a file (requires `dill`).                     |
| `:JovianRestart`       | Restarts the kernel process.                                     |
| `:JovianInterrupt`     | Sends SIGINT to stop the current execution.                      |

## SSH Remote Execution

To execute code on a remote server:

1.  Set up password-less SSH (public key authentication).
2.  Configure `ssh_host` in `setup()`:
    ```lua
    require("jovian").setup({
        ssh_host = "user@192.168.1.50",
        ssh_python = "/usr/bin/python3", -- Remote python path
    })
    ```
3.  Jovian will automatically transfer the kernel script and tunnel the output back to Neovim.

## Known Issues

- **Focus on Toggle:** When running `:JovianToggle`, the cursor focus may occasionally remain in the REPL window instead of returning to the code buffer.
