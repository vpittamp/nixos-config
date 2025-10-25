# Environment Variable-Based App Filtering Research

**Feature**: 035-now-that-we | **Date**: 2025-10-25
**Question**: Should app filtering be based on environment variables instead of tag-based filtering?

## User Proposal

**Concept**: Inject project-specific environment variables into the global scope, allowing applications to access project context and enabling dynamic filtering based on environment state.

**Benefits Claimed**:
1. More flexible filtering logic
2. Enhanced functionality within certain apps (apps can read project context)
3. Potentially simpler implementation

## Analysis

### Current Architecture (Tag-Based Filtering)

**How it works currently**:
1. Projects define application tags: `["development", "terminal", "git"]`
2. Walker/Elephant launcher is invoked with isolated XDG environment
3. Desktop files are generated only for apps matching project tags
4. Walker scans `$XDG_DATA_HOME/applications` and shows filtered apps

**XDG Isolation Pattern** (from walker.nix:87-95):
```bash
# elephant-isolated wrapper
unset XDG_DATA_HOME
unset XDG_DATA_DIRS
export XDG_DATA_HOME="${HOME}/.local/share/i3pm-applications"
export XDG_DATA_DIRS="${HOME}/.local/share/i3pm-applications"
exec elephant
```

**Application Launch Pattern** (from app-launcher-wrapper.sh:107-119):
```bash
# Query daemon for project context
PROJECT_JSON=$(i3pm project current --json 2>/dev/null || echo '{}')
PROJECT_NAME=$(echo "$PROJECT_JSON" | jq -r '.name // ""')
PROJECT_DIR=$(echo "$PROJECT_JSON" | jq -r '.directory // ""')

# Substitute variables in parameters
PARAM_RESOLVED="${PARAMETERS//\$PROJECT_DIR/$PROJECT_DIR}"
```

### Environment Variable-Based Filtering

**Proposed Approach**:

**Option A: Global Environment Variables**
```bash
# Set by project switch command
export I3PM_PROJECT_NAME="nixos"
export I3PM_PROJECT_DIR="/etc/nixos"
export I3PM_PROJECT_TAGS="development,editor,terminal,git"
export I3PM_ACTIVE="true"

# Walker/Elephant launcher can read these
# Desktop files can use these in Exec= lines
# Applications can access project context without daemon queries
```

**Option B: XDG Environment + Project Variables**
```bash
# Combined approach: XDG isolation + project environment
export XDG_DATA_HOME="${HOME}/.local/share/i3pm-applications"
export I3PM_PROJECT_NAME="nixos"
export I3PM_PROJECT_DIR="/etc/nixos"

# Generate desktop files dynamically based on I3PM_PROJECT_TAGS
# Filter at generation time instead of isolation
```

## Trade-off Analysis

### Advantages of Environment Variable Approach

1. **Application Access to Project Context** ⭐ **MAJOR BENEFIT**
   - Applications can read `$I3PM_PROJECT_DIR` and `$I3PM_PROJECT_NAME` directly
   - No need for daemon queries or wrapper script substitution
   - Example: neovim could auto-open project directory on launch
   - Example: terminal could auto-cd to project directory without wrapper
   - Example: file manager could bookmark project directories

2. **Simpler Launcher Integration**
   - Walker/Elephant don't need XDG isolation tricks
   - Can use standard `$XDG_DATA_HOME` and `$XDG_DATA_DIRS`
   - Desktop files can use `Exec=code $I3PM_PROJECT_DIR` directly

3. **Shell Integration**
   - Project context available in every terminal session
   - Bash/Zsh prompts can display active project
   - Scripts can check `$I3PM_ACTIVE` to determine project mode

4. **Reduced Daemon Dependency**
   - Launcher doesn't need to query daemon for project context
   - Project state is in environment, not daemon state

5. **Better Debugging**
   - `env | grep I3PM` shows project state immediately
   - No need to query daemon or parse JSON
   - Clear environment inheritance model

### Disadvantages of Environment Variable Approach

1. **Environment Propagation Challenges** ⚠️ **CRITICAL ISSUE**
   - How do existing terminal sessions get updated when project switches?
   - i3 environment is set at startup - changing it mid-session is complex
   - Applications launched before project switch won't have new environment
   - Solution A: Restart i3 on project switch (BAD: breaks workflow)
   - Solution B: Launch new shell with updated env (COMPLEX: process management)
   - Solution C: Use `.bashrc` to source project state file (WORKABLE but adds latency)

2. **Desktop File Generation Complexity**
   - Need to regenerate desktop files on every project switch
   - XDG isolation works NOW because desktop files are static (from Nix build)
   - Dynamic generation requires runtime desktop file creation
   - Walker/Elephant caching may not pick up changes immediately
   - Need mechanism to invalidate launcher cache

3. **Multi-Session Conflicts**
   - What if user has multiple terminals with different projects?
   - Global environment variables conflict across sessions
   - Terminal A: project=nixos, Terminal B: project=stacks
   - Both read `$I3PM_PROJECT_NAME` - which one is "active"?
   - Tag-based filtering is global (one active project), env vars should be too

4. **Security and Isolation**
   - Environment variables are inherited by all child processes
   - Project directory paths visible in process listings (`ps auxe`)
   - Less isolation than XDG directory-based filtering

5. **Nix Integration Complexity**
   - Current approach: desktop files generated at build time from app-registry.nix
   - Env var approach: need runtime desktop file generation
   - How to integrate with home-manager's declarative file generation?
   - Violates Principle VI (Declarative Configuration)?

## Hybrid Approach: Best of Both Worlds

**Recommended Solution**: Combine environment variables for application context with current tag-based filtering mechanism.

### Implementation Strategy

**Phase 1: Add Project Environment Variables (Enhances current system)**

1. **Export environment variables on project switch**:
   ```bash
   # In i3pm project switch command
   export I3PM_PROJECT_NAME="nixos"
   export I3PM_PROJECT_DIR="/etc/nixos"
   export I3PM_PROJECT_DISPLAY_NAME="NixOS Configuration"
   export I3PM_ACTIVE="true"

   # Update i3 environment (via i3-msg)
   i3-msg exec "export I3PM_PROJECT_NAME=nixos"
   ```

2. **Source project environment in shell sessions**:
   ```bash
   # In ~/.bashrc or ~/.zshrc
   if [ -f ~/.config/i3/active-project-env.sh ]; then
       source ~/.config/i3/active-project-env.sh
   fi
   ```

3. **Update active-project-env.sh on project switch**:
   ```bash
   # Written by i3pm project switch
   cat > ~/.config/i3/active-project-env.sh <<EOF
   export I3PM_PROJECT_NAME="nixos"
   export I3PM_PROJECT_DIR="/etc/nixos"
   export I3PM_ACTIVE="true"
   EOF
   ```

4. **Applications can now access project context**:
   ```bash
   # Application code (or startup script)
   if [ -n "$I3PM_PROJECT_DIR" ]; then
       cd "$I3PM_PROJECT_DIR"
   fi
   ```

**Phase 2: Keep Tag-Based Filtering (Don't fix what isn't broken)**

- Desktop files still generated at build time from app-registry.nix
- XDG isolation still used for Walker/Elephant filtering
- NO runtime desktop file generation needed
- Tag-based filtering continues to work as designed

**Benefits of Hybrid Approach**:
- ✅ Applications gain access to project context (user's request)
- ✅ No launcher changes needed (XDG isolation still works)
- ✅ Shell sessions can read project state
- ✅ Backward compatible with current architecture
- ✅ No desktop file regeneration complexity
- ✅ Still declarative (environment file generated by CLI, sourced by shell)

### Alternative: Full Environment Variable Filtering

**If we replace tag-based filtering with env vars**:

**Desktop File Dynamic Generation**:
```nix
# In app-registry.nix
# Generate desktop files with environment variable references
(mkDesktopFile {
  name = "vscode";
  exec = ''sh -c 'if [ -n "$I3PM_PROJECT_DIR" ]; then code "$I3PM_PROJECT_DIR"; else code; fi' '';
})
```

**Filtering Mechanism**:
```bash
# Generate desktop files filtered by I3PM_PROJECT_TAGS on project switch
python3 << 'EOF'
import os
import json

project_tags = os.environ.get("I3PM_PROJECT_TAGS", "").split(",")
registry = json.load(open(os.path.expanduser("~/.config/i3/application-registry.json")))

for app in registry["applications"]:
    if any(tag in app["tags"] for tag in project_tags) or app["scope"] == "global":
        # Generate desktop file in ~/.local/share/i3pm-applications/applications/
        pass
EOF
```

**Problems with This Approach**:
1. Violates Principle VI (Declarative Configuration) - desktop files generated imperatively
2. Complex cache invalidation for Walker/Elephant
3. Performance: regeneration on every project switch
4. Error-prone: What if generation fails mid-switch?
5. State management: Need cleanup of old desktop files

## Recommendation

### Implement Hybrid Approach (Phase 1 Only)

**Add environment variables for application context, keep tag-based filtering**

**Why**:
1. **Solves user's request**: Applications gain access to project context
2. **Minimal changes**: Extends current system, doesn't replace it
3. **No complexity**: No desktop file regeneration needed
4. **Declarative**: Environment file generated by CLI, fits Nix model
5. **Backward compatible**: Existing tag-based filtering still works

**Implementation Tasks** (update Feature 035 plan):
- T088: Generate `~/.config/i3/active-project-env.sh` on project switch
- T089: Source environment file in bashrc/zshrc template
- T090: Export I3PM_* variables: PROJECT_NAME, PROJECT_DIR, PROJECT_DISPLAY_NAME, ACTIVE
- T091: Document environment variables in quickstart.md
- T092: Update applications to use environment variables where beneficial

**Applications That Benefit**:
- **Terminals**: Auto-cd to project directory on launch
- **Neovim**: Auto-open project directory or last session
- **File managers**: Auto-navigate to project root
- **tmux/sesh**: Session naming and initialization
- **Shell prompts**: Display active project in prompt

**What NOT to change**:
- ❌ Don't replace XDG isolation for Walker/Elephant
- ❌ Don't regenerate desktop files dynamically
- ❌ Don't remove tag-based filtering mechanism
- ❌ Keep app-launcher-wrapper.sh variable substitution (still works)

### Future Consideration: Full Env Var Filtering

**If tag-based filtering proves insufficient**, consider full environment variable approach:
- Requires runtime desktop file generation
- Needs Walker/Elephant cache invalidation strategy
- Must maintain declarative principles (scripted generation)
- Significant complexity increase

**Decision**: Revisit ONLY if hybrid approach doesn't meet needs.

## Conclusion

**Decision**: **Implement Hybrid Approach - Add environment variables, keep tag-based filtering**

**Rationale**:
- Solves user's request (apps access project context)
- Minimal complexity (extends, doesn't replace)
- Maintains declarative principles
- Backward compatible
- Clear migration path if more needed later

**Next Steps**:
1. Update plan.md to include environment variable export
2. Update data-model.md to document environment file schema
3. Update tasks.md to include environment variable tasks
4. Update quickstart.md with environment variable examples

**Constitutional Alignment**:
- ✅ Principle VI: Environment file is declaratively generated, sourced by shell (acceptable)
- ✅ Principle XII: Doesn't preserve legacy - extends optimal current solution
- ✅ Principle I: Modular - environment variables are opt-in for applications

