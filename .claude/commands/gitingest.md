---
description: Analyze Git repository for LLM context with optimized file selection
allowed-tools: Bash(mkdir:*), Bash(gitingest:*), Bash(uvx:*)
argument-hint: <repo-url> [output-path]
---

# GitIngest - Repository Analysis for NixOS Packaging

Analyze the repository at `$1` and generate an optimized digest for LLM context.

## Output Location

- **Default**: `./docs/<repo-name>.txt` (extract repo name from URL)
- **Custom**: Use `$2` if provided
- **Stdout**: Use `-o -` if user says "stdout" or "print"

Create output directory if needed: `mkdir -p ./docs`

## Command Template

```bash
uvx gitingest $1 \
  -i "*.nix" -i "flake.*" -i "*.md" \
  -i "meson*" -i "CMakeLists.txt" -i "Makefile" \
  -i "*.toml" -i "*.yaml" -i "*.json" \
  -i "*.conf" -i "*.desktop" -i "*.service" \
  -i "LICENSE*" -i "*.h" \
  -e "*.o" -e "*.so" -e "*.a" \
  -e "build/*" -e "dist/*" -e "target/*" -e "bin/*" \
  -e "tests/*" -e "test_*" -e "*_test.*" \
  -e ".git/*" -e ".vscode/*" -e ".idea/*" \
  -e "*.png" -e "*.jpg" -e "*.svg" \
  -e "*.c" -e "*.cpp" -e "*.cc" -e "*.rs" -e "*.go" -e "*.py" -e "*.js" -e "*.ts" \
  -s 100000 \
  -o <OUTPUT_PATH>
```

## Flags Reference

| Flag | Long Form | Purpose |
|------|-----------|---------|
| `-i` | `--include-pattern` | Include files matching pattern |
| `-e` | `--exclude-pattern` | Exclude files matching pattern |
| `-s` | `--max-size` | Max file size in bytes (100KB default) |
| `-o` | `--output` | Output path (`-` for stdout) |
| `-b` | `--branch` | Specific branch to analyze |
| `-t` | `--token` | GitHub token for private repos |

## File Selection Rationale

**INCLUDE** (high signal for NixOS packaging):
- Nix files (`*.nix`, `flake.*`) - packaging config
- Docs (`*.md`) - build/install instructions
- Build systems (`meson*`, `CMakeLists.txt`, `Makefile`)
- Dependencies (`*.toml`, `*.yaml`, `*.json`)
- Desktop integration (`*.desktop`, `*.service`)
- Headers (`*.h`) - API/dependency info for C/C++ projects

**EXCLUDE** (low signal, high tokens):
- Source files (`*.c`, `*.cpp`, `*.rs`, etc.) - implementation not needed for packaging
- Build artifacts (`*.o`, `*.so`, `build/`, `dist/`)
- Tests (`tests/`, `test_*`)
- IDE/editor files (`.vscode/`, `.idea/`)
- Binary assets (`*.png`, `*.jpg`, `*.svg`)

## After Running

Report to user:
1. Output file path and token count
2. Build system detected (meson/cmake/make/cargo/etc.)
3. Key dependencies found
4. NixOS packaging considerations (licenses, runtime deps, patches needed)

## Token Budget

Target <150K tokens (75% of 200K safe zone). Current patterns typically yield 80-130K tokens depending on project size.
