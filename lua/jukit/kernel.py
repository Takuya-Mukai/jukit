import sys
import json
import os
import io
import traceback
import glob

# バックエンド設定
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# 設定
CACHE_ROOT = ".jukit_cache"

class JukitKernel:
    def __init__(self):
        self.current_cell_id = "unknown"
        self.current_filename = "scratchpad"
        self.output_counter = 0
        
        self.stdout_buffer = io.StringIO()
        self.original_stdout = sys.stdout
        self.original_stderr = sys.stderr
        
        # Monkey Patches
        sys.stdout = self
        sys.stderr = self
        
        self._original_show = plt.show
        
        def custom_show_wrapper(*args, **kwargs):
            return self._custom_show(*args, **kwargs)
            
        plt.show = custom_show_wrapper

    def write(self, text):
        self.stdout_buffer.write(text)

    def flush(self):
        self.flush_stdout_to_file()

    def _get_save_dir(self, filename=None):
        if filename is None:
            filename = self.current_filename
        safe_script_name = os.path.basename(filename)
        if not safe_script_name: safe_script_name = "scratchpad"
        return os.path.join(CACHE_ROOT, safe_script_name)

    def _get_output_path(self, ext):
        save_dir = self._get_save_dir()
        os.makedirs(save_dir, exist_ok=True)
        filename = f"{self.current_cell_id}_{self.output_counter:02d}.{ext}"
        return os.path.join(save_dir, filename)

    # ★ 追加機能1: 特定のセルのキャッシュのみ削除 (実行前に呼ぶ)
    def _purge_cell_cache(self, cell_id, filename):
        save_dir = self._get_save_dir(filename)
        if not os.path.exists(save_dir):
            return
            
        # cell_id_*.txt や cell_id_*.png を削除
        pattern = os.path.join(save_dir, f"{cell_id}_*")
        for filepath in glob.glob(pattern):
            try:
                os.remove(filepath)
            except OSError:
                pass

    # ★ 追加機能2: 不要なIDのキャッシュを一括削除 (同期用)
    def _sync_cache(self, filename, valid_ids):
        save_dir = self._get_save_dir(filename)
        if not os.path.exists(save_dir):
            return

        valid_ids_set = set(valid_ids)
        
        for filepath in os.listdir(save_dir):
            # ファイル名形式: id_num.ext
            # '_' で分割してIDを取得
            parts = filepath.split('_')
            if len(parts) > 0:
                fid = parts[0]
                # 有効なIDリストになければ削除
                if fid not in valid_ids_set:
                    full_path = os.path.join(save_dir, filepath)
                    try:
                        os.remove(full_path)
                    except OSError:
                        pass

    def flush_stdout_to_file(self):
        content = self.stdout_buffer.getvalue()
        if not content:
            return

        filepath = self._get_output_path("txt")
        self.stdout_buffer.close()
        self.stdout_buffer = io.StringIO()
        
        try:
            with open(filepath, "w", encoding="utf-8") as f:
                f.write(content)
            self._send_json("text_file", filepath)
            self.output_counter += 1
        except Exception as e:
            self.original_stderr.write(f"Error writing output: {e}\n")

    def _send_json(self, msg_type, payload):
        msg = {
            "type": msg_type,
            "payload": payload,
            "cell_id": self.current_cell_id
        }
        self.original_stdout.write(json.dumps(msg) + "\n")
        self.original_stdout.flush()

    def _custom_show(self, *args, **kwargs):
        self.flush_stdout_to_file()
        fig = plt.gcf()
        filepath = self._get_output_path("png")
        try:
            fig.savefig(filepath, format='png', bbox_inches='tight')
            self._send_json("image_file", filepath)
            self.output_counter += 1
        except Exception as e:
            self.stdout_buffer.write(f"\n[Jukit Error] Image save failed: {e}\n")
            self.flush_stdout_to_file()
            return
        finally:
            plt.close(fig)

    def run_code(self, code, cell_id, filename):
        # ★ 実行前に、そのセルの既存キャッシュを全削除
        self._purge_cell_cache(cell_id, filename)

        self.current_cell_id = cell_id
        self.current_filename = filename
        self.output_counter = 0
        
        self.stdout_buffer.close()
        self.stdout_buffer = io.StringIO()

        try:
            exec(code, globals())
        except Exception:
            self.stdout_buffer.write(traceback.format_exc())
        finally:
            self.flush_stdout_to_file()

    def start(self):
        while True:
            try:
                line = sys.stdin.readline()
                if not line: break
                
                cmd = json.loads(line)
                command_type = cmd.get('command')
                
                if command_type == 'execute':
                    filename = cmd.get('filename', 'scratchpad')
                    self.run_code(cmd['code'], cmd['cell_id'], filename)
                    
                # ★ Syncコマンドの処理
                elif command_type == 'clean_cache':
                    filename = cmd.get('filename', 'scratchpad')
                    valid_ids = cmd.get('valid_ids', [])
                    self._sync_cache(filename, valid_ids)
                    
            except json.JSONDecodeError:
                pass
            except KeyboardInterrupt:
                break

if __name__ == "__main__":
    kernel = JukitKernel()
    kernel.start()
