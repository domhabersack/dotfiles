# Neovim with native LSP for TypeScript, Tailwind, and React

## What changed

The entire vim plugin stack has been overhauled for neovim. Vundle is gone, replaced by vim-plug (auto-installs itself). CtrlP is gone, replaced by fzf. UltiSnips is gone, replaced by LuaSnip. A full LSP stack is now wired up for neovim via Lua.

**This only activates when running `nvim`**, not `vim`. All existing vim behavior is preserved for plain vim sessions.

### Plugins added (neovim-only)

| Plugin | Role |
|---|---|
| `mason.nvim` | Installs and manages language servers |
| `mason-lspconfig.nvim` | Bridges Mason with neovim's LSP client |
| `nvim-lspconfig` | Configures each language server |
| `nvim-cmp` + sources | Completion engine (LSP, snippets, buffer, paths) |
| `LuaSnip` | Snippet engine |
| `nvim-treesitter` | Richer syntax highlighting and indentation |
| `conform.nvim` | Format on save with Prettier |

### Language servers installed automatically by Mason

`ts_ls` (TypeScript/JavaScript), `tailwindcss`, `eslint`, `cssls`, `html`, `jsonls`

### LSP keybindings (active inside any LSP-attached buffer)

| Key | Action |
|---|---|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gr` | Find all references |
| `gi` | Go to implementation |
| `K` | Show hover documentation / type info |
| `<leader>rn` | Rename symbol across the project |
| `<leader>ca` | Code actions (imports, fixes, refactors) |
| `[d` / `]d` | Jump to previous / next diagnostic |
| `<leader>e` | Open floating error detail |

### Completion (nvim-cmp)

| Key | Action |
|---|---|
| `Tab` / `S-Tab` | Navigate completion menu |
| `Enter` | Confirm selection |
| `Ctrl-Space` | Force-open completion menu |

### Format on save

Prettier runs automatically on save for: TypeScript, TSX, JavaScript, JSX, CSS, HTML, JSON, Markdown, YAML. Timeout is 1 second; if Prettier isn't available, LSP formatting is used as fallback.

## Why it helps

This replaces several independent plugins that each partially solved type checking, completion, and syntax with a single integrated stack. You get:

- **Real type errors** from the TypeScript compiler, inline as you type
- **Tailwind class completion** inside `className=""` strings
- **ESLint diagnostics** without running a separate terminal process
- **Go to definition** that works across the project, including into `node_modules`
- **Rename refactoring** that updates every reference in the codebase at once
- **Automatic formatting** so you never have to think about Prettier again

## When to use it

Open any `.ts`, `.tsx`, `.js`, or `.jsx` file in `nvim`. Mason installs the language servers in the background on the first launch — you'll see a progress indicator. After that first install, everything is ready on subsequent opens.

For Tailwind completion to work, the project needs a `tailwind.config.js` (or `.ts`) at the root. The LSP uses that to discover your theme.

## What to look out for

- **First launch takes time.** Mason downloads and compiles language servers (tsserver in particular is large). Let it finish before expecting completion to work.
- **Node.js is required** for most of these servers. They're installed by Mason but they run on Node. If `node` isn't in `$PATH` when you open nvim, Mason will report installation failures. The lazy NVM setup means `node` may not be loaded yet — run `node --version` once in the same shell to trigger the NVM load, then reopen nvim.
- **Prettier must be installed in the project** (or globally) for `conform.nvim` to call it. If Prettier isn't found, format-on-save skips silently and falls back to LSP formatting. Add it with `npm install --save-dev prettier` in the project.
- **Plain `vim` gets none of this.** The entire LSP block is guarded by `if has('nvim')`. If you open `vim` instead of `nvim`, you get the pre-existing config with the subset of plugins that work in both.
- **`conform.nvim` format-on-save can conflict** with ESLint autofix if both are running. The current config runs Prettier only; ESLint diagnostics appear inline but ESLint autofix is not wired up to save. You can trigger it manually with `<leader>ca` → "Fix all ESLint issues".
- **Treesitter grammars also install on first launch** (`:TSUpdate` runs automatically via the `do` hook). Expect a few seconds of compilation on a fresh machine.
