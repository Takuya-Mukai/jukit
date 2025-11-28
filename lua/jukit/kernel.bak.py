import sys
import json
import os
import io
import traceback
import glob
import re
import builtins
import types
import subprocess # ★追加
import time       # ★追加

# バックエンド設定
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

CACHE_ROOT = ".jukit_cache"

class StreamCapture:
    def __init__(self, stream_name, parent_kernel):
        self.stream_name = stream_name
        self.parent = parent_kernel
        self.buffer = io.StringIO()

    def write(self, text):
        self.buffer.write(text)
        self.parent._send_stream(self.stream_name, text)

    def flush(self):
        pass

    def get_value(self):
        return self.buffer.getvalue()
    
    def reset(self):
        self.buffer.truncate(0)
        self.buffer.seek(0)

class JukitKernel:
    def __init__(self):
        self.current_cell_id = "unknown"
        self.current_filename = "scratchpad"
        self.output_counter = 0
        self.output_queue = [] 
        
        self.original_stdout = sys.stdout
        self.original_stderr = sys.stderr
        
        self.stdout_proxy = StreamCapture('stdout', self)
        self.stderr_proxy = StreamCapture('stderr', self)
        
        sys.stdout = self.stdout_proxy
        sys.stderr = self.stderr_proxy
        
        self.original_input = builtins.input
        builtins.input = self._custom_input

        self._original_show = plt.show
        def custom_show_wrapper(*args, **kwargs):
            return self._custom_show(*args, **kwargs)
        plt.show = custom_show_wrapper

    def _custom_input(self, prompt=""):
        if prompt:
            print(prompt, end='')
        
        msg = {
            "type": "input_request",
            "prompt": str(prompt),
            "cell_id": self.current_cell_id
        }
        self.original_stdout.write(json.dumps(msg) + "\n")
        self.original_stdout.flush()

        while True:
            line = sys.stdin.readline()
            if not line:
                raise EOFError("Kernel stream ended during input()")
            try:
                cmd = json.loads(line)
                if cmd.get('command') == 'input_reply':
                    return cmd.get('value', '')
            except (json.JSONDecodeError, ValueError):
                pass
        return ""

    def _get_variables(self):
        var_list = []
        for name, value in list(globals().items()):
            if name.startswith("_"): continue
            if isinstance(value, (types.ModuleType, types.FunctionType, type)): continue
            
            type_name = type(value).__name__
            info = str(value)
            if len(info) > 50: info = info[:47] + "..."

            if hasattr(value, 'shape') and hasattr(value, 'dtype'):
                shape_str = str(value.shape).replace(" ", "")
                info = f"{shape_str} | {value.dtype}"
            elif isinstance(value, (list, dict, set, tuple)):
                info = f"len: {len(value)}"

            var_list.append({"name": name, "type": type_name, "info": info})
            
        var_list.sort(key=lambda x: x['name'])
        msg = {"type": "variable_list", "variables": var_list}
        self.original_stdout.write(json.dumps(msg) + "\n")
        self.original_stdout.flush()

    def _get_dataframe_data(self, var_name):
        if var_name not in globals():
            return
        val = globals()[var_name]
        try:
            import pandas as pd
            import numpy as np
            
            df = None
            if isinstance(val, pd.DataFrame):
                df = val
            elif isinstance(val, pd.Series):
                df = val.to_frame()
            elif isinstance(val, np.ndarray):
                if val.ndim > 2: raise ValueError("Only 1D/2D arrays supported")
                df = pd.DataFrame(val)
            else:
                return 

            df_view = df.head(100)
            data_json = df_view.to_json(orient='split', date_format='iso')
            parsed = json.loads(data_json)
            
            msg = {
                "type": "dataframe_data",
                "name": var_name,
                "columns": parsed.get('columns', []),
                "index": parsed.get('index', []),
                "data": parsed.get('data', [])
            }
            self.original_stdout.write(json.dumps(msg) + "\n")
            self.original_stdout.flush()
        except Exception:
            self.stderr_proxy.write(f"Error viewing {var_name}:\n{traceback.format_exc()}")

    def _send_stream(self, stream_name, text):
        msg = {
            "type": "stream",
            "stream": stream_name,
            "text": text,
            "cell_id": self.current_cell_id
        }
        self.original_stdout.write(json.dumps(msg) + "\n")
        self.original_stdout.flush()

    def _get_save_dir(self, filename=None):
        if filename is None: filename = self.current_filename
        safe_name = os.path.basename(filename) or "scratchpad"
        return os.path.join(CACHE_ROOT, safe_name)

    def _sync_queue(self):
        out = self.stdout_proxy.get_value()
        if out: 
            self.output_queue.append({"type": "text", "content": out})
            self.stdout_proxy.reset()
        err = self.stderr_proxy.get_value()
        if err: 
            self.output_queue.append({"type": "text", "content": err})
            self.stderr_proxy.reset()

    def _custom_show(self, *args, **kwargs):
        self._sync_queue()
        save_dir = self._get_save_dir()
        os.makedirs(save_dir, exist_ok=True)
        filename = f"{self.current_cell_id}_{self.output_counter:02d}.png"
        filepath = os.path.join(save_dir, filename)
        abs_path = os.path.abspath(filepath)
        try:
            fig = plt.gcf()
            fig.savefig(filepath, format='png', bbox_inches='tight')
            plt.close(fig)
            self.output_queue.append({"type": "image", "path": abs_path})
            self.output_counter += 1
            msg = {"type": "image_saved", "path": abs_path, "cell_id": self.current_cell_id}
            self.original_stdout.write(json.dumps(msg) + "\n")
            self.original_stdout.flush()
        except Exception:
            self.stderr_proxy.write(traceback.format_exc())

    def _clean_text_for_markdown(self, text):
        text = re.sub(r'\x1b\[[0-9;]*m', '', text) 
        lines = text.split('\n')
        cleaned_lines = []
        for line in lines:
            if '\r' in line:
                parts = line.split('\r')
                final_part = parts[-1]
                if not final_part and len(parts) > 1:
                    final_part = parts[-2]
                cleaned_lines.append(final_part)
            else:
                cleaned_lines.append(line)
        return '\n'.join(cleaned_lines)

    def _save_markdown_result(self):
        self._sync_queue()
        save_dir = self._get_save_dir()
        os.makedirs(save_dir, exist_ok=True)
        md_filename = f"{self.current_cell_id}.md"
        md_path = os.path.join(save_dir, md_filename)
        plain_text_output = ""
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(f"# Output: {self.current_cell_id}\n\n")
            if not self.output_queue: f.write("*(No output)*\n")
            for item in self.output_queue:
                if item["type"] == "text":
                    raw_content = item["content"]
                    plain_text_output += raw_content
                    clean_content = self._clean_text_for_markdown(raw_content)
                    safe_content = clean_content.replace("```", "'''")
                    if safe_content.strip(): f.write(f"```text\n{safe_content}\n```\n\n")
                elif item["type"] == "image":
                    f.write(f"![Result]({item['path']})\n\n")
                    plain_text_output += f"\n[Image: {os.path.basename(item['path'])}]\n"
        return os.path.abspath(md_path), plain_text_output

    # ★ 追加: マジックコマンド処理
    def _preprocess_magic(self, code):
        lines = code.split('\n')
        processed_lines = []
        
        for line in lines:
            stripped = line.strip()
            # !command -> subprocess
            if stripped.startswith('!'):
                cmd = stripped[1:]
                # シェルコマンドを実行して出力をprintするPythonコードに変換
                escaped_cmd = cmd.replace('"', '\\"')
                py_line = f'import subprocess; p=subprocess.run("{escaped_cmd}", shell=True, capture_output=True, text=True); print(p.stdout, end=""); print(p.stderr, end="")'
                processed_lines.append(py_line)
                escaped_cmd = cmd.replace('"', '\\"')
                py_line = f'import subprocess; subprocess.run("{escaped_cmd}", shell=True)'
                processed_lines.append(py_line)
            
            # %cd path -> os.chdir
            elif stripped.startswith('%cd'):
                path = stripped[3:].strip()
                # パスの引用符を処理（簡易版）
                if (path.startswith('"') and path.endswith('"')) or (path.startswith("'") and path.endswith("'")):
                    path = path[1:-1]
                py_line = f'import os; os.chdir(r"{path}"); print(f"cwd: {{os.getcwd()}}")'
                processed_lines.append(py_line)
                
            # %time code -> 計測
            elif stripped.startswith('%time '):
                stmt = stripped[6:]
                py_line = f'__t_start=__import__("time").time(); {stmt}; print(f"Wall time: {{__import__("time").time()-__t_start:.4f}}s")'
                processed_lines.append(py_line)
                
            else:
                processed_lines.append(line)
                
        return '\n'.join(processed_lines)

    def run_code(self, code, cell_id, filename):
        self.current_cell_id = cell_id
        self.current_filename = filename
        self.output_counter = 0
        self.output_queue = []
        self.stdout_proxy.reset()
        self.stderr_proxy.reset()

        has_error = False
        error_line = None
        error_msg = ""

        # ★ マジックコマンドの変換
        transpiled_code = self._preprocess_magic(code)

        try:
            exec(transpiled_code, globals())
        except Exception:
            has_error = True
            exc_type, exc_value, exc_traceback = sys.exc_info()
            tb_list = traceback.extract_tb(exc_traceback)
            
            for frame in tb_list:
                if frame.filename == "<string>":
                    error_line = frame.lineno
                    break
            
            if error_line is None and isinstance(exc_value, SyntaxError):
                error_line = exc_value.lineno

            error_msg = f"{exc_type.__name__}: {exc_value}"
            self.stderr_proxy.write(traceback.format_exc())
        finally:
            md_path, text_log = self._save_markdown_result()
            
            msg = {
                "type": "result_ready",
                "cell_id": cell_id,
                "file": md_path,
                "text_output": text_log 
            }
            
            if has_error and error_line is not None:
                msg["error"] = {
                    "line": error_line,
                    "msg": error_msg
                }

            self.original_stdout.write(json.dumps(msg) + "\n")
            self.original_stdout.flush()
            
    def _purge_cache(self, valid_ids, filename):
        save_dir = self._get_save_dir(filename)
        if not os.path.exists(save_dir): return
        valid_set = set(valid_ids)
        for f in os.listdir(save_dir):
            parts = f.replace('.', '_').split('_')
            if parts and parts[0] not in valid_set:
                 try: os.remove(os.path.join(save_dir, f))
                 except: pass

    def start(self):
        while True:
            try:
                line = sys.stdin.readline()
                if not line: break
                cmd = json.loads(line)
                if cmd.get('command') == 'execute':
                    self.run_code(cmd['code'], cmd['cell_id'], cmd.get('filename', 'scratchpad'))
                elif cmd.get('command') == 'clean_cache':
                    self._purge_cache(cmd.get('valid_ids', []), cmd.get('filename', 'scratchpad'))
                elif cmd.get('command') == 'input_reply': pass 
                elif cmd.get('command') == 'get_variables': self._get_variables()
                elif cmd.get('command') == 'view_dataframe': self._get_dataframe_data(cmd.get('name'))

            except (json.JSONDecodeError, KeyboardInterrupt):
                pass

if __name__ == "__main__":
    kernel = JukitKernel()
    kernel.start()
