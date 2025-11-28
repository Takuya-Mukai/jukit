Here is a comprehensive `README.md` file for your plugin. I have organized it to highlight the features we implemented (Inline Diagnostics, DataFrame Viewer, Virtual Text Status, etc.).

You can save this as `README.md` in the root of your plugin directory.

-----

# 🚀 Jukit.nvim

**Jukit.nvim** is a lightweight, blazing-fast Jupyter Notebook alternative for Neovim, written in Lua and Python. It transforms your Neovim into a powerful scientific development environment without the bloat of a browser.

It allows you to define code cells using `# %%`, execute them, view results in a split terminal, visualize `pandas` DataFrames in interactive TUI tables, and debug with inline error diagnostics.

## ✨ Features

  * **⚡ REPL & Output Split:** Execute code and see text output/logs in a dedicated split window.
  * **📊 Interactive Data Viewer:** View `pandas` DataFrames and `numpy` arrays in a scrollable, TUI-based spreadsheet view (`:JukitView`).
  * **🔎 Variable Explorer:** See all active variables, their types, and shapes/values in a floating window (`:JukitVars`).
  * **📈 Image Plotting:** Automatically captures `matplotlib` plots and generates Markdown previews.
  * **🚨 Inline Diagnostics:** Python errors are displayed directly in your code buffer with red underlines and virtual text (using Neovim's native LSP diagnostic interface).
  * **📝 Cell Management:** Commands to navigate, insert, merge, and fold code cells.
  * **👀 Live Status:** Virtual text indicators (`⏳ Running...`, `✓ Done`, `✘ Error`) appear next to cell headers.
  * **🔔 Notifications:** Desktop notifications for long-running tasks (\>10s).
  * **⌨️ Input Support:** Supports Python's `input()` function via Neovim's UI.

## 📦 Requirements

  * **Neovim** (v0.9.0 or later recommended)
  * **Python 3**
  * **Python Libraries:**
    To use the advanced features (plots, dataframe viewer), you need to install the following in your Python environment:
    ```bash
    pip install pandas numpy matplotlib
    ```
  * *(Optional)* **Image Viewer:** To see the generated plots inside Neovim, we recommend using a plugin like [image.nvim](https://github.com/3rd/image.nvim) or [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim). Jukit generates a Markdown file pointing to the saved images.

## 🛠️ Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

If you are developing this locally:

```lua
{
    dir = "~/path/to/jukit", -- Change this to your local path
    config = function()
        require("jukit").setup({
            -- Optional configuration settings
            python_interpreter = "python3",
            preview_width_percent = 40,
            notify_threshold = 10, -- Notify if task takes longer than 10s
        })
    end,
    ft = "python", -- Load only for Python files
}
```

## ⚙️ Configuration

You can customize Jukit by passing a table to the setup function. The defaults are:

```lua
require("jukit").setup({
    -- UI Dimensions
    preview_width_percent = 40,
    repl_height_percent = 30,
    
    -- Python Settings
    python_interpreter = "python3", -- or "/path/to/venv/bin/python"
    
    -- Visuals
    flash_highlight_group = "Visual", -- Highlight group for cell flash
    flash_duration = 300,             -- Flash duration in ms
    
    -- Behavior
    notify_threshold = 10,            -- Send desktop notification after this many seconds
})
```

## 🚀 Usage & Commands

Jukit does not set up keybindings by default. You can map the commands below to your preferred keys.

### Core Execution

| Command | Description |
| :--- | :--- |
| `:JukitStart` | Start the IPython kernel manually (auto-starts on first run). |
| `:JukitRun` | Execute the current cell (under cursor). |
| `:JukitRunAll` | Execute all cells in the buffer sequentially. |
| `:JukitSendSelection` | Execute visually selected code. |
| `:JukitRestart` | Restart the kernel (useful to clear memory). |

### Data & UI

| Command | Description |
| :--- | :--- |
| `:JukitView [var]` | Open the **DataFrame Viewer** for a variable (e.g., `df`). If no arg provided, uses word under cursor. |
| `:JukitVars` | Open the **Variable Explorer** showing types and shapes. |
| `:JukitOpen` | Open the REPL and Preview windows. |
| `:JukitToggle` | Toggle the REPL/Preview windows. |
| `:JukitClear` | Clear the text content of the REPL window. |

### Navigation & Editing

| Command | Description |
| :--- | :--- |
| `:JukitNextCell` | Jump to the next cell header (`# %%`). |
| `:JukitPrevCell` | Jump to the previous cell header. |
| `:JukitNewCellBelow` | Insert a new cell below the current one. |
| `:JukitNewCellAbove` | Insert a new cell above the current one. |
| `:JukitMergeBelow` | Merge the current cell with the one below. |

## ⌨️ Recommended Keybindings

Add this to your `init.lua` to enable a workflow similar to VS Code or Jupyter Lab:

```lua
local map = vim.keymap.set

-- Execution
map("n", "<leader>r", "<cmd>JukitRun<cr>", { desc = "Run Current Cell" })
map("n", "<leader>R", "<cmd>JukitRunAll<cr>", { desc = "Run All Cells" })
map("v", "<leader>r", "<cmd>JukitSendSelection<cr>", { desc = "Run Selection" })

-- Data Viewing
map("n", "<leader>jv", "<cmd>JukitVars<cr>", { desc = "Show Variables" })
map("n", "<leader>jd", "<cmd>JukitView<cr>", { desc = "View DataFrame under cursor" })

-- Navigation
map("n", "]j", "<cmd>JukitNextCell<cr>", { desc = "Next Cell" })
map("n", "[j", "<cmd>JukitPrevCell<cr>", { desc = "Previous Cell" })

-- Cell Management
map("n", "<leader>cn", "<cmd>JukitNewCellBelow<cr>", { desc = "New Cell Below" })
map("n", "<leader>cN", "<cmd>JukitNewCellAbove<cr>", { desc = "New Cell Above" })
map("n", "<leader>cm", "<cmd>JukitMergeBelow<cr>", { desc = "Merge Cell" })

-- Kernel
map("n", "<leader>kk", "<cmd>JukitRestart<cr>", { desc = "Restart Kernel" })
```

## 📸 Workflow Example

1.  Open a `.py` file.
2.  Define cells using `# %%`.
3.  Write some code:
    ```python
    # %%
    import pandas as pd
    import numpy as np
    import time

    # %%
    # Create a large DataFrame
    df = pd.DataFrame(np.random.randn(100, 5), columns=list('ABCDE'))

    # %%
    # This will trigger an error diagnostic
    print(unknown_variable)
    ```
4.  Place your cursor inside the DataFrame cell and run `:JukitRun`.
5.  Hover over `df` and run `:JukitView` to inspect the data.
6.  Run the error cell to see the red underline and virtual text error message.

-----

**License**: MIT
