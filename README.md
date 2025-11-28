# 🚀 Jukit.nvim

**Jukit.nvim** is a blazing-fast, terminal-centric Jupyter Notebook alternative for Neovim.

It transforms Neovim into a professional scientific development environment, leveraging the power of **IPython** for magic commands, **Neovim Diagnostics** for inline error reporting, and **TUI-based viewers** for DataFrames and variables.

## ✨ Key Features

  * **⚡ IPython Kernel Integration:** Full support for magic commands (`!ls`, `%time`, `%cd`, `%whos`) and robust error handling.
  * **📊 Interactive Data Viewer:** Inspect `pandas` DataFrames and `numpy` arrays in a scrollable, spreadsheet-like floating window (`:JukitView`).
  * **🔎 Variable Explorer:** Visualize active variables, types, and shapes in a clean floating window (`:JukitVars`).
  * **🚨 Inline Diagnostics:** Python errors are displayed directly in your code buffer with red underlines and virtual text messages.
  * **📈 Plotting Support:**
      * **Image Plot:** Automatically captures `matplotlib` plots and generates Markdown previews.
      * **TUI Plot:** Render high-resolution Braille charts directly in the terminal (`:JukitPlotTUI`).
  * **💾 Session Management:** Save and load your entire workspace (variables) using `dill` (`:JukitSaveSession`).
  * **🔄 SSH Remote Execution:** Run your code on a remote GPU server seamlessly via SSH.
  * **📋 Smart Clipboard:** Copy DataFrames/Arrays to your system clipboard as Markdown tables or CSV (`:JukitCopy`).
  * **⏱️ Profiling:** Run `cProfile` on a cell and view execution statistics (`:JukitProfile`).
  * **👀 Live Status:** Real-time execution status (`⏳ Running...`, `✓ Done`, `✘ Error`) displayed next to cell headers.

## 📦 Requirements

  * **Neovim** (v0.9.0+)

  * **Python 3**

  * **Python Packages:**

      * **Mandatory:** `ipython` (The kernel relies on `InteractiveShell`).
      * **Recommended:** `pandas`, `numpy`, `matplotlib`.
      * **Optional:** `uniplot` (for TUI plotting), `dill` (for session save/load).

    <!-- end list -->

    ```bash
    pip install ipython pandas numpy matplotlib uniplot dill
    ```

    *(Note: For NixOS/Debian, install these via your system package manager or use `pip --break-system-packages` if necessary.)*

## 🛠️ Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    dir = "~/path/to/jukit", -- Point to your local path or git repo
    ft = "python",
    config = function()
        require("jukit").setup({
            -- Python Settings
            python_interpreter = "python3", 
            
            -- SSH Remote Settings (Optional)
            -- ssh_host = "user@gpu-server", 
            -- ssh_python = "/usr/bin/python3",

            -- UI Settings
            preview_width_percent = 40,
            notify_threshold = 10, -- Notify if task takes > 10s
        })
    end
}
```

## ⚙️ Configuration

The default configuration:

```lua
require("jukit").setup({
    -- Layout
    preview_width_percent = 40,
    repl_height_percent = 30,
    preview_image_ratio = 0.6,
    repl_image_ratio = 0.3,
    
    -- Python & Remote
    python_interpreter = "python3",
    ssh_host = nil,    -- Set "user@host" to run remotely
    ssh_python = "python3",
    
    -- Visuals
    flash_highlight_group = "Visual",
    flash_duration = 300,
    
    -- Behavior
    notify_threshold = 10,
})
```

## ⌨️ Recommended Keybindings

Jukit does not define keybindings by default. Add these to your `init.lua`:

```lua
local map = vim.keymap.set

-- 1. Window Management (REQUIRED to run code)
map("n", "<leader>jo", "<cmd>JukitOpen<cr>", { desc = "Open Jukit Windows" })
map("n", "<leader>jt", "<cmd>JukitToggle<cr>", { desc = "Toggle Jukit Windows" })

-- 2. Execution
map("n", "<leader>r", "<cmd>JukitRun<cr>", { desc = "Run Current Cell" })
map("n", "<leader>R", "<cmd>JukitRunAll<cr>", { desc = "Run All Cells" })
map("n", "<leader>rp", "<cmd>JukitProfile<cr>", { desc = "Profile Cell" })

-- 3. Data & Debugging
map("n", "<leader>jv", "<cmd>JukitVars<cr>", { desc = "Variable Explorer" })
map("n", "<leader>jd", "<cmd>JukitView<cr>", { desc = "View DataFrame" })
map("n", "<leader>jp", "<cmd>JukitPlotTUI<cr>", { desc = "Plot TUI" })
map("n", "<leader>ce", "<cmd>JukitClearDiag<cr>", { desc = "Clear Diagnostics" })

-- 4. Session
map("n", "<leader>jss", "<cmd>JukitSaveSession<cr>", { desc = "Save Session" })
map("n", "<leader>jsl", "<cmd>JukitLoadSession<cr>", { desc = "Load Session" })

-- 5. Navigation & Editing
map("n", "]j", "<cmd>JukitNextCell<cr>", { desc = "Next Cell" })
map("n", "[j", "<cmd>JukitPrevCell<cr>", { desc = "Prev Cell" })
map("n", "<leader>cn", "<cmd>JukitNewCellBelow<cr>", { desc = "New Cell Below" })
```

## 🚀 Commands Reference

| Command | Description |
| :--- | :--- |
| `:JukitOpen` / `:JukitToggle` | **Must be run first.** Opens the Output/REPL split windows. |
| `:JukitRun` | Execute the current cell (`# %%`). |
| `:JukitView [var]` | Opens a TUI spreadsheet viewer for the variable (DataFrame/Array). |
| `:JukitVars` | Shows a list of all active variables in the kernel. |
| `:JukitPlotTUI [var]` | Plots a variable directly in the REPL using Braille characters. |
| `:JukitCopy [var]` | Copies a DataFrame/Array to system clipboard as Markdown/CSV. |
| `:JukitProfile` | Runs the current cell with `cProfile` and shows stats. |
| `:JukitSaveSession [file]` | Saves current variables to a file (requires `dill`). |
| `:JukitLoadSession [file]` | Loads variables from a file. |
| `:JukitInterrupt` | Sends SIGINT to the kernel (stops execution). |
| `:JukitRestart` | Restarts the IPython kernel (clears memory). |

## ⚠️ Known Issues

  * **Window Focus on Toggle:** When running `:JukitToggle` or `:JukitOpen`, the cursor focus might occasionally remain in the newly opened REPL/Output window instead of returning to your code buffer, depending on your specific Neovim version or conflicting plugins. You may need to manually switch back (e.g., `<C-w>h`).
