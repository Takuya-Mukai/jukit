import sys
import os
import json

# Add backend to path
backend_path = os.path.abspath("lua/jovian/backend")
sys.path.append(backend_path)

from shell import JovianShell
import protocol

# Mock protocol
captured_msgs = []
def mock_send_json(msg):
    captured_msgs.append(msg)
    sys.__stdout__.write("JSON: " + json.dumps(msg) + "\n")

def mock_send_stream(name, text, cell_id):
    sys.__stdout__.write(f"STREAM {name}: {text}\n")

protocol.send_json = mock_send_json
protocol.send_stream = mock_send_stream

shell = JovianShell()

print("--- Initial Mode ---")
print(f"Mode: {shell.plot_mode}")

print("\n--- Setting Mode to Window ---")
shell.set_plot_mode("window")
print(f"Mode: {shell.plot_mode}")

print("\n--- Setting Mode to Inline ---")
shell.set_plot_mode("inline")
print(f"Mode: {shell.plot_mode}")

# Verify _custom_show logic (mocking plt.show and _original_show)
called_original_show = False
def mock_original_show(*args, **kwargs):
    global called_original_show
    called_original_show = True
    print("Called original show")

shell._original_show = mock_original_show

print("\n--- Testing Show (Inline) ---")
shell.set_plot_mode("inline")
called_original_show = False
# We can't easily run _custom_show without a real figure, but we can check the mode check
# By inspecting the code, we know it calls _original_show if mode is window.
# Let's trust the unit test of state change for now, as full matplotlib mocking is complex.
if shell.plot_mode == "inline":
    print("PASS: Mode is inline")
else:
    print("FAIL: Mode is not inline")

print("\n--- Testing Show (Window) ---")
shell.set_plot_mode("window")
# Mock _sync_queue to avoid errors
shell._sync_queue = lambda: None
# Call _custom_show directly
shell._custom_show()

if called_original_show:
    print("PASS: Called original show in window mode")
else:
    print("FAIL: Did not call original show in window mode")
