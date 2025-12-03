# %% [markdown]
# # Jovian.nvim Demo
# Welcome to the demo! This script showcases the key features of jovian.nvim.
# Make sure you have `pandas`, `numpy`, `matplotlib`, `seaborn`, and `tqdm` installed.

# %%
import time
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from tqdm import tqdm

# Set a nice theme for plots (especially for dark mode editors)
# sns.set_theme(style="darkgrid")

# %%
# ## 1. Variables Pane
# Define some variables. They will appear in the Variables Pane (right split).
# Try toggling it with `:JovianToggleVars`.
user = "Neovim User"
item_count = 42
price = 19.99
is_active = True
items = ["keyboard", "mouse", "monitor"]
config = {"theme": "dark", "font": "JetBrains Mono"}

print(f"Welcome, {user}!")

# %%
# ## 2. Result Preview (Text & DataFrames)
# Run this cell to see the output in the Preview Window.
# Pandas DataFrames are rendered as text tables.
df = pd.DataFrame({
    "Date": pd.date_range(start="2023-01-01", periods=5),
    "Sales": np.random.randint(100, 500, 5),
    "Category": ["Electronics", "Books", "Clothing", "Electronics", "Books"]
})

print("Here is a sample DataFrame:")
print(df)

# %%
# ## 3. Plotting (Matplotlib)
# If you have `image.nvim` configured, this plot will appear in the Preview Window!
x = np.linspace(0, 10, 100)
y1 = np.sin(x)
y2 = np.cos(x)

plt.figure(figsize=(8, 5))
plt.plot(x, y1, label="Sin", color="#61afef", linewidth=2)
plt.plot(x, y2, label="Cos", color="#98c379", linewidth=2, linestyle="--")
plt.title("Trigonometric Functions")
plt.legend()
plt.show()

# %%
# ## 5. Progress Bars (tqdm)
# Jovian.nvim supports real-time output updates, perfect for progress bars!
print("Training model...")
for i in tqdm(range(100), desc="Epochs"):
    time.sleep(0.05) # Simulate work
print("Training complete!")

# %%
# ## 6. Error Handling
# Errors are captured and displayed with a clear "Error" status.
def calculate_ratio(a, b):
    return a / b

print("Calculating ratio...")
calculate_ratio(10, 0)
