"""Measure decode speed of the running server.  Usage: python bench.py [port] [runs]"""
import json, sys, time, urllib.request

PORT = sys.argv[1] if len(sys.argv) > 1 else "8000"
RUNS = int(sys.argv[2]) if len(sys.argv) > 2 else 3
URL = f"http://127.0.0.1:{PORT}/v1/chat/completions"
PROMPTS = [
    "Write a detailed explanation of how a CMOS inverter works, including its transfer curve.",
    "Write a Python function that parses a CSV file and computes per-column statistics, with comments.",
    "Explain the differences between TCP and UDP and when to use each, with examples.",
]


def one(prompt):
    body = json.dumps({
        "model": "OrcaSAQ2-27B", "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 600, "temperature": 1.0, "top_p": 0.95, "top_k": 20, "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(URL, body, {"Content-Type": "application/json"})
    t0 = time.perf_counter(); first = last = None; n = 0
    with urllib.request.urlopen(req, timeout=600) as r:
        for line in r:
            line = line.strip()
            if not line.startswith(b"data:") or line == b"data: [DONE]":
                continue
            d = json.loads(line[5:])
            if d.get("usage"):
                n = d["usage"]["completion_tokens"]
            if d.get("choices") and d["choices"][0]["delta"].get("content"):
                last = time.perf_counter()
                first = first or last
    return n, first - t0, n / (last - first) if last > first else 0.0


one("Say hi.")  # warm-up, not counted
rates = []
for i in range(RUNS):
    n, ttft, rate = one(PROMPTS[i % len(PROMPTS)])
    rates.append(rate)
    print(f"run {i + 1}: {n} tokens, first token {ttft:.2f}s, decode {rate:.1f} tok/s")
print(f"AVERAGE decode: {sum(rates) / len(rates):.1f} tok/s")
