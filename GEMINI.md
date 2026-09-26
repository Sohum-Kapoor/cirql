# Gemini CLI notes

Read `AGENTS.md` first — it is the working agreement for every agent and human on
this repo (ownership by file, the walker contract, Linear, git, and the Jac rules).
This file only adds what's specific to Gemini.

- Stay inside the files of the owner you're working for (A = `*.sv.jac`, B = client).
- Before writing any `.jac`, run `jac guide <name>` for the relevant area. Jac
  syntax is not Python and not JSX; do not generate it from memory.
- After every edit, run `jac check <file>` and show the output.
- `GOOGLE_API_KEY` is read from `.env` by the server via byLLM; never put it in a
  `cl` block or commit it.
