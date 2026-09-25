# OrcaSAQ2-27B on native exllamav3 (EXL3)

Run **OrcaSAQ2-27B** — a high-fidelity 3-bit EXL3 (QTIP trellis) quantization of
Qwen3.8-27B — on **native exllamav3**, with an OpenAI-compatible HTTP server.
No Docker, no vLLM. This is the exllamav3-only path; the Docker/vLLM route is not
included here.

## Headline

* **~60 tok/s decode at full context (262,144 tokens) with vision enabled**, on a
  single **NVIDIA RTX A4500 (20 GB)**.
* 262K-token context window, 4-bit KV cache, MTP speculative drafting (head inside
  the checkpoint), and a multimodal vision encoder (Qwen3.8-27B, EXL3-quantized).
* 54 GB → **12.3 GB** on disk. +0.02% PPL, 93.2% Top-1 agreement, 0.031 KLD vs the
  full-precision base.

## What this repo is

| Path | What it is |
|------|------------|
| `exl3_serve.py` | Launcher: applies the OrcaSAQ2 int8-embedding patch, registers the MTP head for the text-only class, then runs the OpenAI server in-process. |
| `tools/serve_openai.py` | OpenAI-compatible server (`/v1/models`, `/health`, `/v1/chat/completions` — streaming, tool calling, vision). |
| `OrcaSAQ2-kernel/` | The serving kernels: the int8-embedding patch (`orcasaq2/patches/int8_embedding.py`) plus the vLLM plugin and presets (kept for reference). |
| `setup.bat` | One-time setup: builds the venv, fetches the exllamav3 1.5.1 wheel, downloads the model, and (if the vision tower is present) builds the vision model. |
| `download_vision.bat` | Build the vision model (`model-vl`) from the text model + the shipped vision tower. |
| `start_exl3.bat` | Start the server (edit the knobs at the top). |
| `stop_exl3.bat` | Stop the server and free VRAM. |
| `bench.py` | Measure decode speed of the running server. |
| `vision/` | The EXL3-quantized Qwen3.8-27B vision tower (`vision.safetensors`, ~0.57 GB, via git-lfs) plus the VL `config.json` and safetensors index. |

## Requirements

* **Windows 10/11** (all scripts are `.bat`; validated on Windows 11).
* An NVIDIA GPU (validated on an **RTX A4500, 20 GB**).
* **git** and **git-lfs** on PATH (git-lfs carries the vision tower).
* **uv** on PATH (setup installs it via pip if it is missing).
* ~12.3 GB free for the model, ~2 GB for the exllamav3 wheel, ~0.6 GB for the vision tower.

## Setup (one time)

```bat
setup.bat
```

This:
1. Creates `.\venv` (Python 3.13) with `torch 2.10.0+cu128`, `transformers 5.17.0`,
   `aiohttp`, `pillow`, `safetensors`, and the other runtime deps.
2. Downloads the official **exllamav3 1.5.1** wheel (cu128 / torch 2.10.0 / cp313)
   into `.\wheels` and unpacks it into `.\exl3lib`.
3. Downloads the text model `orcarouter/OrcaSAQ-2-27B` into `.\model` (12.3 GB,
   resumes if interrupted).
4. If the vision tower is present in `.\vision`, builds the vision model into
   `.\model-vl` (calls `download_vision.bat`).

> **Cloning with the vision tower.** The tower is stored with git-lfs. Clone with
> `git lfs install` then `git clone <url>` (or `git lfs pull` after a plain clone).
> Without it, `setup.bat` skips vision and you run text-only (`VISION=0`).

## Vision (optional)

The vision model is **not a single HF repo**: it is the OrcaSAQ2 text model plus the
EXL3-quantized Qwen3.8-27B vision tower (987 trellis tensors, ~0.57 GB), which was
quantized locally with exllamav3's `convert_vision.py` + `transplant_vision.py`. This
repo ships the tower and the two VL config files under `.\vision`, so you can rebuild
the vision model on any machine:

```bat
download_vision.bat
```

This downloads the text model into `.\model-vl` (12.3 GB) and overlays the three
VL-specific files from `.\vision` — `config.json` (multimodal arch),
`model.safetensors.index.json` (maps the 987 vision tensors), and
`vision.safetensors` (the tower). The four text shards are byte-identical to the HF
text model, so only the tower and these two files are shipped.

To run **text-only** instead, set `VISION=0` in `start_exl3.bat` and use `.\model`.

## Run

```bat
start_exl3.bat
```

Defaults: 262,144-token context, 4-bit KV, MTP drafting on, vision on, port 8000,
served as `OrcaSAQ2-27B`. The server binds to `127.0.0.1` by default.

* Health: `GET http://127.0.0.1:8000/health`
* Models: `GET http://127.0.0.1:8000/v1/models`
* Chat:   `POST http://127.0.0.1:8000/v1/chat/completions`

### Knobs (top of `start_exl3.bat`)

| Var | Meaning |
|-----|---------|
| `VISION` | `1` = accept images (uses `model-vl`), `0` = text only (`model`). |
| `CTX` | Context length in tokens (KV cache size). |
| `MTP` | `1` = MTP speculative drafting on (head in the checkpoint), `0` = off. |
| `NDT` | Draft tokens per step (empty = drafter default, 4). Each +1 ≈ +144 MiB VRAM. |
| `DYN` | `1` = adapt draft length to the acceptance rate. |
| `CHUNK` | Prompt chunk size in tokens (empty = exllamav3 default). |
| `CQ` | KV cache quant bits: 4, 6, or 8 (or `"8,4"` for K,V). Lower = more context. |
| `PORT` / `HOST` | Bind address. `0.0.0.0` = reachable on your network. |
| `MAX_TOKENS` | Default max reply length when the client doesn't set it. |

### Stop

```bat
stop_exl3.bat
```

## Bench

With the server running:

```bat
venv\Scripts\python.exe bench.py 8000 3
```

Prints per-run decode tok/s and the average.

## Why the int8-embedding patch

exllamav3 won't quantize an embedding, so a plain pack keeps `embed_tokens.weight` in
bf16 — 2.54 GB for a 248,320-token vocabulary. The OrcaSAQ2 checkpoint instead stores
the table as int8 rows with a per-row scale (weight-domain relative error 0.0090,
ΔKLD within the noise floor), giving back ~1.27 GB. `exl3_serve.py` applies
`orcasaq2/patches/int8_embedding.py` at load time so the engine reads that packed form.

## Notes

* The 1.5.0 exllamav3 fork cannot unpack this checkpoint's 3.5-bit layers
  ("packed dimension 2 is incorrect size"); `exl3_serve.py` puts the official 1.5.1
  from `.\exl3lib` first on the path to shadow it for this process only.
* The MTP head is registered for the text-only `Qwen3_5Config` class (the fork only
  registers it for the multimodal class), so `-dm mtp` works on the text checkpoint.
* VRAM budget on 20 GB: weights ~15.5 GB + KV. 4-bit KV at 262K context fits with MTP
  and the vision tower loaded (~19.5 GB in use).
