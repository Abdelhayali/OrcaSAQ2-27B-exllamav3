"""Run OrcaSAQ2-27B on native exllamav3 (no Docker, no vLLM).

Self-contained: uses the exllamav3 install in .\\exl3lib and the OpenAI server in
.\\tools\\serve_openai.py, both inside this repo. Applies the OrcaSAQ2 int8-embedding
patch, then runs the server in this same process. All command-line arguments are passed
straight through to it.
"""
import importlib.util, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PATCH = os.path.join(HERE, "OrcaSAQ2-kernel", "orcasaq2", "patches", "int8_embedding.py")
SERVER = os.path.join(HERE, "tools", "serve_openai.py")

# Official exllamav3 1.5.1, unpacked beside this file (see setup.bat). The 1.5.0 fork
# cannot unpack this checkpoint's 3.5-bit layers ("packed dimension 2 is incorrect size"),
# so 1.5.1 is put first on the path to shadow any other exllamav3 for this process only.
sys.path.insert(0, os.path.join(HERE, "exl3lib"))

# Load the patch file on its own: importing the orcasaq2 package would pull in its vLLM plugin.
spec = importlib.util.spec_from_file_location("orca_int8_embedding", PATCH)
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)
patch.apply()
import exllamav3
print(f" == exllamav3 from {os.path.dirname(exllamav3.__file__)}", flush=True)
print(" == OrcaSAQ2 int8-embedding patch applied", flush=True)

# This checkpoint is text-only (Qwen3_5ForCausalLM). The fork registers the MTP head only for
# the multimodal config class, though the mtp.* tensors are named identically in both, so
# `-dm mtp` fails with "does not define a 'mtp' component model". Register it here too.
from exllamav3.architecture import qwen3_5 as _q35

def _text_cfg_init(self, directory, **kwargs):
    _q35.Qwen3_5VLBaseConfig.__init__(
        self, directory, None, _q35.Qwen3_5Model, None, _q35.Qwen3_5MTPModel, **kwargs)

_q35.Qwen3_5Config.__init__ = _text_cfg_init
print(" == MTP head registered for the text-only model class", flush=True)

os.chdir(HERE)
sys.path.insert(0, os.path.dirname(SERVER))
sys.argv = [SERVER] + sys.argv[1:]

# The server caps a reply at 1024 tokens when the client sends no max_tokens. Swap in
# MAX_TOKENS from start_exl3.bat, in memory only - serve_openai.py itself is not changed.
src = open(SERVER, encoding="utf-8").read()
DEFAULT_CAP = 'body.get("max_completion_tokens") or 1024)'
max_tokens = os.environ.get("MAX_TOKENS", "").strip()
if max_tokens.isdigit():
    if DEFAULT_CAP in src:
        src = src.replace(DEFAULT_CAP, f'body.get("max_completion_tokens") or {int(max_tokens)})')
        print(f" == default max output tokens: {int(max_tokens)}", flush=True)
    else:
        print(" !! could not find the server's max_tokens default; keeping it", flush=True)
exec(compile(src, SERVER, "exec"), {"__name__": "__main__", "__file__": SERVER})
