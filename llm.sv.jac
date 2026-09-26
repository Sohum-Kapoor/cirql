"""One byLLM model for every server module.

OWNER: Person A. Import with `import from llm { llm }`. The model string comes from
`GEMINI_MODEL` in `.env` (auto-loaded by byLLM from cwd) and defaults to the pin in
jac.toml. Verified 2026-09-26: gemini/gemini-3.8-flash answers on our key; 2.0/2.5
models are retired. Free tier = 20 requests/day/model, so every walker makes ONE call.
"""

import from byllm.lib { Model }
import os;

glob llm: Model = Model(model_name=os.environ.get("GEMINI_MODEL", "gemini/gemini-3.8-flash"));
