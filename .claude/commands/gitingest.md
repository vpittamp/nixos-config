---
description: Analyze Git repository for LLM context with optimized file selection
---

# GitIngest - Analyze Git Repository for LLM Context

You are helping the user analyze a Git repository and create optimized context for LLM consumption (like for NixOS packaging or configuration).

## Task

Use `uvx gitingest` to analyze the provided repository URL and generate an optimized text digest suitable for LLM context. Using `uvx` ensures we always have the latest version without requiring pre-installation.

## GitIngest Criteria for NixOS Packaging/Configuration

When analyzing repositories for NixOS packaging or configuration assistance, use these patterns:

### Files to INCLUDE:

**Nix-specific files** (highest priority):
- `*.nix` (flake.nix, default.nix, shell.nix, etc.)
- `flake.lock`
- Files in `nix/` directory

**Documentation**:
- `README.md`, `README`, `INSTALL.md`, `CONTRIBUTING.md`, `CHANGELOG.md`
- Files in `docs/` directory

**Build system files**:
- `meson.build`, `meson_options.txt`
- `CMakeLists.txt`
- `Makefile`, `*.mk`
- `configure.ac`, `configure`

**Configuration files**:
- `*.conf`, `*.config`
- `config.def.h` (suckless-style projects)
- `*.toml`, `*.yaml`, `*.yml`
- `*.json` (project configs, not build artifacts)

**Desktop integration**:
- `*.desktop`
- `*.service` (systemd)
- `*.target`

**License files** (important for packaging):
- `LICENSE*`, `COPYING*`, `COPYRIGHT`

**Dependency/package management**:
- `package.json`, `Cargo.toml`, `go.mod`, `requirements.txt`, `pyproject.toml`, `setup.py`

**Header files** (for C/C++ projects):
- `*.h` (defines APIs and dependencies)

### Files to EXCLUDE:

- Build artifacts: `*.o`, `*.a`, `*.so`, `build/`, `dist/`
- IDE files: `.vscode/`, `.idea/`, `*.swp`
- Large binary assets: `*.png`, `*.jpg`, `*.svg` (unless small/essential)
- Test files: `tests/`, `test_*`, `*_test.*`
- Git metadata: `.git/`
- Compiled binaries: `bin/`, `target/`

## Output Location Strategy

**Default behavior:**
- Extract repository name from URL (e.g., `mangowc` from `github.com/user/mangowc`)
- Save to: `./gitingest/<repo-name>-digest.txt` (current project directory)
- Create `./gitingest/` directory if it doesn't exist
- Use relative path for easy Claude Code navigation

**User can override:**
- If user specifies a path: use that path
- If user says "stdout" or "print": use `--output -`

**Benefits:**
- ✅ Project-local: Digest stays with project (portable)
- ✅ Easy navigation: Claude Code can reference relative path
- ✅ Version control: Can commit digest if desired
- ✅ Context-aware: Digest location implies project relationship

**Token Economy:**
- Target: <150K tokens (75% of 200K safe zone)
- Current approach: Selective files average 120-130K tokens
- Avoids: Context bloat & degraded performance
- Cost: Stays under 2x premium pricing threshold

## Command Execution

1. **Parse the repository URL** and optional output location from the user's request
2. **Determine output path:**
   - Extract repo name from URL (e.g., `github.com/user/mangowc` → `mangowc`)
   - Default: `./gitingest/<repo-name>-digest.txt` (current working directory)
   - Create `./gitingest/` directory if needed
   - Override if user specifies custom path
3. **Run gitingest** via uvx with appropriate include/exclude patterns:

```bash
uvx gitingest <REPO_URL> \
  --include-pattern "*.nix" \
  --include-pattern "*.md" \
  --include-pattern "meson*" \
  --include-pattern "CMakeLists.txt" \
  --include-pattern "Makefile" \
  --include-pattern "*.conf" \
  --include-pattern "*.desktop" \
  --include-pattern "LICENSE*" \
  --include-pattern "*.h" \
  --include-pattern "flake.*" \
  --include-pattern "*.toml" \
  --include-pattern "*.yaml" \
  --include-pattern "*.json" \
  --exclude-pattern "*.o" \
  --exclude-pattern "*.so" \
  --exclude-pattern "*.a" \
  --exclude-pattern "build/*" \
  --exclude-pattern "dist/*" \
  --exclude-pattern "tests/*" \
  --exclude-pattern "test_*" \
  --exclude-pattern "*_test.*" \
  --exclude-pattern ".git/*" \
  --exclude-pattern "bin/*" \
  --exclude-pattern "target/*" \
  --exclude-pattern ".vscode/*" \
  --exclude-pattern ".idea/*" \
  --exclude-pattern "*.swp" \
  --exclude-pattern "*.png" \
  --exclude-pattern "*.jpg" \
  --exclude-pattern "*.svg" \
  --exclude-pattern "*.c" \
  --exclude-pattern "*.cpp" \
  --exclude-pattern "*.cc" \
  --exclude-pattern "*.rs" \
  --exclude-pattern "*.go" \
  --exclude-pattern "*.py" \
  --exclude-pattern "*.js" \
  --exclude-pattern "*.ts" \
  --max-size 100000 \
  --output <OUTPUT_PATH>
```

**Note**: Implementation source files (`.c`, `.cpp`, `.rs`, etc.) are excluded to keep token count optimal. Header files (`.h`) are included for C/C++ projects as they reveal APIs and dependencies.

4. **Inform the user** of the saved location and provide summary:
   - File path where digest was saved
   - Summary of what was included and why
   - Key dependencies identified
   - Build system detected
   - Runtime dependencies
   - Any special considerations for NixOS packaging

## Example Usage

**Example 1: Default location (current project)**
```
User: "Analyze https://github.com/DreamMaoMao/mangowc for NixOS packaging"
Assistant actions:
1. Creates directory: mkdir -p ./gitingest
2. Runs: uvx gitingest https://github.com/DreamMaoMao/mangowc \
     --include-pattern "*.nix" --include-pattern "*.md" --include-pattern "meson*" --include-pattern "*.h" \
     --exclude-pattern "build/*" --exclude-pattern "*.c" --exclude-pattern "*.cpp" \
     --output ./gitingest/mangowc-digest.txt
3. Reports: "Saved digest to ./gitingest/mangowc-digest.txt (127.5k tokens, 44 files)"
```

**Example 2: Custom location**
```
User: "Analyze https://github.com/DreamMaoMao/mangowc and save to /tmp/mango.txt"

Assistant actions:
1. Runs: uvx gitingest https://github.com/DreamMaoMao/mangowc \
     --include-pattern "*.nix" --include-pattern "*.md" \
     --output /tmp/mango.txt
2. Reports: "Saved digest to /tmp/mango.txt"
```

**Example 3: Print to stdout**
```
User: "Analyze https://github.com/user/small-repo and show me the output"

Assistant actions:
1. Runs: uvx gitingest https://github.com/user/small-repo --output -
2. Displays output directly in conversation
```

## Usage Patterns

**Typical workflow:**
```bash
# 1. User requests analysis
/gitingest https://github.com/DreamMaoMao/mangowc

# 2. Assistant analyzes and saves to ./gitingest/mangowc-digest.txt

# 3. Claude Code can now reference: ./gitingest/mangowc-digest.txt
# 4. User can:
#    - Ask Claude to read the digest and create NixOS module
#    - Commit digest to version control if desired
#    - Reference specific sections for implementation
```

**Project structure after analysis:**
```
/current/project/
├── gitingest/
│   └── mangowc-digest.txt  (127.5k tokens, easy to reference)
├── flake.nix
├── configuration.nix
└── ... (your NixOS config)
```

## Why This File Selection Works

**Research-backed rationale:**

1. **Token Budget**: 127.5k tokens is 64% of 200K limit (safe zone <80%)
2. **Signal-to-Noise**: Build files + docs >> implementation source for packaging
3. **Performance**: Avoids context bloat that degrades LLM performance
4. **Cost**: Stays under 200K premium pricing threshold
5. **Navigation**: Directory tree + selective files = optimal context

**What we EXCLUDE and why:**
- `*.c`, `*.cpp`, `*.rs` files: Implementation details not needed for packaging
- Test files: Don't affect packaging decisions
- Already 44 files with 127.5k tokens - more would hurt performance

**For C/C++ projects like mangowc:**
- ✅ Include `.h` headers (36 files) - reveals API structure & dependencies
- ❌ Exclude `.c` source (~200+ files) - would add 500k+ tokens with no packaging value

## .gitignore Recommendations

Add gitingest digests to your project's `.gitignore` if they become stale quickly:

```gitignore
# Gitingest digests (regenerate as needed)
gitingest/
```

**When to commit digests:**
- ✅ Commit: If analyzing dependencies for a specific package version
- ✅ Commit: If digest is used in CI/CD for validation
- ❌ Don't commit: For exploratory analysis of external repos
- ❌ Don't commit: If repo changes frequently (will become stale)

## Performance Guidelines

**Token limits and behavior:**
- 0-160K tokens: Optimal performance
- 160K-180K tokens: Good performance (80-90% usage)
- 180K-200K tokens: Degraded performance, start new session
- >200K tokens: 2x input pricing, significant performance impact

**Current approach targets:**
- C/C++ projects: ~120-140K tokens (build files + headers)
- High-level languages: ~80-100K tokens (build files + docs only)
- Rationale: Leaves headroom for conversation context

**If digest is too large:**
1. Remove language-specific patterns (e.g., `--exclude-pattern "*.h"` for non-C projects)
2. Focus on specific subdirectories if repo is monolithic
3. Split analysis across multiple digests (e.g., `src/`, `docs/`, `nix/`)
