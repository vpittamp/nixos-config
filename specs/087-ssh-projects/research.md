# Technical Research: Remote Project Environment Support

**Feature**: 087-ssh-projects | **Date**: 2025-11-22
**Purpose**: Research SSH command construction, shell escaping, and remote project validation patterns

## Research Questions

1. How do we construct safe SSH commands with proper shell escaping for remote paths containing spaces/special characters?
2. What is the standard pattern for wrapping terminal applications (ghostty -e <command>) with SSH?
3. How do we validate SSH connectivity and remote directory existence efficiently?
4. What error handling patterns should we use for SSH connection failures?

## Findings

### 1. SSH Command Construction & Shell Escaping

**Decision**: Use SSH with `-t` flag for pseudo-terminal allocation and single-quoted remote commands for safety

**Pattern**:
```bash
ssh -t user@host 'cd /remote/path && command args'
```

**Rationale**:
- `-t` flag: Forces pseudo-terminal allocation, required for interactive commands (lazygit, yazi, tmux/sesh)
- Single quotes: Prevents local shell expansion of variables and special characters
- `cd && command`: Ensures working directory is set before command execution
- Graceful handling: SSH returns exit code of remote command for error detection

**Shell Escaping Strategy**:
```bash
# Original terminal command
ghostty -e sesh connect /local/project/path

# Remote-wrapped version
ghostty -e bash -c "ssh -t user@host 'cd /remote/path && sesh connect /remote/path'"
```

**Escaping Rules**:
1. **Local path substitution**: Use `${VARIABLE//search/replace}` Bash pattern for `$PROJECT_DIR → $REMOTE_WORKING_DIR`
2. **Remote path escaping**: Wrap in single quotes to prevent shell expansion on local side
3. **Nested command escaping**: Use `bash -c "..."` wrapper with double quotes for ghostty `-e` parameter

**Edge Cases**:
- Paths with spaces: `'cd /remote/with spaces/path && command'` (single quotes protect)
- Paths with single quotes: Use `'"'"'` pattern to escape single quote within single-quoted string
- Example: `/path/with'quote` becomes `'cd /path/with'"'"'quote && command'`

**Testing Strategy**:
```bash
# Test path with spaces
REMOTE_DIR="/home/user/my projects/app"
ssh -t user@host "cd '$REMOTE_DIR' && pwd"

# Test path with special characters
REMOTE_DIR="/home/user/\$dollar/path"
ssh -t user@host "cd '$REMOTE_DIR' && pwd"
```

**Alternatives Considered**:
- ❌ **Double quotes for remote command**: `ssh user@host "cd $REMOTE_DIR && command"`
  - Rejected: Local shell expands variables before SSH transmission, breaks paths with `$`
- ❌ **Heredoc for command**: `ssh user@host <<EOF\ncd /path\ncommand\nEOF`
  - Rejected: Complex syntax, harder to debug, no benefit for single-line commands
- ❌ **Base64 encoding**: Encode entire command in base64, decode remotely
  - Rejected: Over-engineered for simple path escaping problem

### 2. Terminal Application Wrapping Pattern

**Decision**: Detect terminal apps via registry `terminal: true` flag and reconstruct args with SSH wrapper

**Implementation Pattern**:
```bash
# Existing launcher logic (lines 90-200 in app-launcher-wrapper.sh)
COMMAND=$(echo "$APP_JSON" | jq -r '.command')
PARAMETERS=$(echo "$APP_JSON" | jq -r '.parameters | join(" ")')
IS_TERMINAL=$(echo "$APP_JSON" | jq -r '.terminal // false')

# NEW: Remote project detection (line 110)
REMOTE_ENABLED=$(echo "$PROJECT_JSON" | jq -r '.remote.enabled // false')
REMOTE_HOST=$(echo "$PROJECT_JSON" | jq -r '.remote.host // ""')
REMOTE_USER=$(echo "$PROJECT_JSON" | jq -r '.remote.user // ""')
REMOTE_WORKING_DIR=$(echo "$PROJECT_JSON" | jq -r '.remote.working_dir // ""')
REMOTE_PORT=$(echo "$PROJECT_JSON" | jq -r '.remote.port // 22')

# NEW: SSH wrapping for terminal apps (after line 200)
if [[ "$REMOTE_ENABLED" == "true" ]] && [[ "$IS_TERMINAL" == "true" ]]; then
    # Extract terminal command after -e flag
    TERMINAL_CMD=""
    for ((i=0; i<${#ARGS[@]}; i++)); do
        if [[ "${ARGS[$i]}" == "-e" ]] && [[ $((i+1)) -lt ${#ARGS[@]} ]]; then
            TERMINAL_CMD="${ARGS[@]:$((i+1))}"
            break
        fi
    done

    # Substitute remote paths
    TERMINAL_CMD_REMOTE="${TERMINAL_CMD//$PROJECT_DIR/$REMOTE_WORKING_DIR}"

    # Build SSH command
    SSH_CMD="ssh"
    [[ "$REMOTE_PORT" != "22" ]] && SSH_CMD="$SSH_CMD -p $REMOTE_PORT"
    SSH_CMD="$SSH_CMD -t $REMOTE_USER@$REMOTE_HOST"
    SSH_CMD="$SSH_CMD 'cd $REMOTE_WORKING_DIR && $TERMINAL_CMD_REMOTE'"

    # Rebuild args: ghostty -e bash -c "ssh ..."
    ARGS=("${ARGS[0]}" "-e" "bash" "-c" "$SSH_CMD")
fi
```

**Terminal App Examples**:
| Original Command | Remote-Wrapped Command |
|-----------------|------------------------|
| `ghostty -e sesh connect /local/path` | `ghostty -e bash -c "ssh -t user@host 'cd /remote/path && sesh connect /remote/path'"` |
| `ghostty -e lazygit --work-tree=/local/path` | `ghostty -e bash -c "ssh -t user@host 'cd /remote/path && lazygit --work-tree=/remote/path'"` |
| `ghostty -e yazi /local/path` | `ghostty -e bash -c "ssh -t user@host 'cd /remote/path && yazi /remote/path'"` |

**Non-Terminal Apps**:
- GUI apps (VS Code, Firefox): Error immediately with clear message (FR-010)
- No SSH wrapping attempt - prevent confusing error messages

### 3. SSH Connectivity Validation

**Decision**: Use `ssh -q -o ConnectTimeout=5 -o BatchMode=yes user@host 'test -d /remote/path && echo OK'` for fast validation

**Validation Levels**:
1. **Connection test**: `ssh -q -o BatchMode=yes user@host 'echo OK'`
   - Validates: SSH key auth, host reachability, user permissions
   - Timeout: 5 seconds (configurable)
   - Exit codes: 0 (success), 255 (connection failed), 1 (auth failed)

2. **Directory test**: `ssh user@host 'test -d /remote/path && echo OK || echo MISSING'`
   - Validates: Remote working directory exists
   - Returns: "OK" (exists), "MISSING" (not found)
   - Non-blocking: Warning if missing, not fatal error

3. **Full validation**: Combines both tests
   - Used by `i3pm project test-remote <name>` command
   - Provides detailed error messages with troubleshooting guidance

**SSH Options for Validation**:
- `-q`: Quiet mode (suppress warnings/banners)
- `-o ConnectTimeout=5`: Network timeout (5 seconds)
- `-o BatchMode=yes`: Disable password prompts (key-only auth)
- `-o StrictHostKeyChecking=no`: Skip host key verification (optional, Tailscale trusted)

**Error Message Patterns**:
```bash
# Connection refused / host unreachable
if [[ $exit_code == 255 ]]; then
    echo "Cannot connect to $REMOTE_HOST"
    echo "  - Check Tailscale is running: tailscale status"
    echo "  - Verify host is online: ping $REMOTE_HOST"
    echo "  - Check firewall allows SSH (port $REMOTE_PORT)"
fi

# Authentication failed
if [[ $exit_code == 1 ]]; then
    echo "SSH authentication failed for $REMOTE_USER@$REMOTE_HOST"
    echo "  - Verify SSH key is added to remote ~/.ssh/authorized_keys"
    echo "  - Check SSH key exists: ls ~/.ssh/id_ed25519.pub"
    echo "  - Test manually: ssh $REMOTE_USER@$REMOTE_HOST"
fi

# Directory missing
if [[ $output == "MISSING" ]]; then
    echo "Warning: Remote directory not found: $REMOTE_WORKING_DIR"
    echo "  - Create directory: ssh $REMOTE_USER@$REMOTE_HOST 'mkdir -p $REMOTE_WORKING_DIR'"
    echo "  - Or clone project: ssh $REMOTE_USER@$REMOTE_HOST 'git clone <repo> $REMOTE_WORKING_DIR'"
fi
```

**Performance Considerations**:
- Validation is optional - run on-demand via `i3pm project test-remote`
- Not run automatically during project switch (avoid network latency blocking UX)
- Cached validation results (5 minute TTL) for repeated checks

**Alternatives Considered**:
- ❌ **Pre-validation on every app launch**: Too slow (1-2s network I/O before every terminal launch)
- ❌ **Background validation daemon**: Over-engineered, adds complexity for minimal benefit
- ✅ **On-demand validation**: User-triggered, clear troubleshooting path

### 4. Error Handling Patterns

**Decision**: Fail fast with actionable error messages, log detailed context for debugging

**Error Categories**:

1. **Configuration Errors** (block project creation):
   ```python
   # Python Pydantic validation
   class RemoteConfig(BaseModel):
       host: str = Field(..., min_length=1)
       user: str = Field(..., min_length=1)
       working_dir: str = Field(..., min_length=1)
       port: int = Field(default=22, ge=1, le=65535)

       @field_validator('working_dir')
       def validate_remote_dir(cls, v):
           if not v.startswith('/'):
               raise ValueError("Remote working_dir must be absolute path")
           return v
   ```
   - Missing required fields: Clear error listing required fields
   - Invalid port: Must be 1-65535
   - Relative path: Error with example of correct absolute path

2. **Connection Errors** (runtime failures):
   ```bash
   # Bash error handling
   if ! ssh -q -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" 'echo OK' &>/dev/null; then
       log "ERROR" "SSH connection failed: $REMOTE_USER@$REMOTE_HOST"
       notify-send "Remote Project Error" \
           "Cannot connect to $REMOTE_HOST\nCheck Tailscale and SSH keys"
       exit 1
   fi
   ```
   - Network unreachable: Suggest Tailscale status check
   - Auth failure: Suggest SSH key verification
   - Timeout: Suggest checking remote host is online

3. **Launch Errors** (app-specific):
   ```bash
   # GUI app in remote project
   if [[ "$REMOTE_ENABLED" == "true" ]] && [[ "$IS_TERMINAL" == "false" ]]; then
       error "Cannot launch GUI application '$APP_NAME' in remote project
       Remote projects only support terminal-based applications.
       GUI apps require X11 forwarding or local execution.

       Workarounds:
       - Use VS Code Remote-SSH extension instead
       - Launch $APP_NAME locally (switch to local project)
       - Exclude from scoped_classes if not needed remotely"
   fi
   ```
   - GUI app rejection: Explain limitation, suggest workarounds
   - Missing terminal command: Debug log for investigation

4. **Logging Strategy**:
   ```bash
   # Feature 087 logging pattern
   LOG_FILE="${HOME}/.local/state/app-launcher.log"

   log() {
       local level="$1"
       shift
       echo "[$(date -Iseconds)] [Feature 087] $level $*" >> "$LOG_FILE"
   }

   # Debug logging for SSH commands
   log "DEBUG" "Remote mode: enabled"
   log "DEBUG" "SSH command: $SSH_CMD"
   log "DEBUG" "Resolved args: ${ARGS[*]}"
   ```
   - Feature-tagged logs: Easy grep for debugging (`grep "Feature 087" app-launcher.log`)
   - Structured format: Timestamp, level, message
   - Debug mode: `DEBUG=1 app-launcher-wrapper.sh <app>` shows real-time logs

## Best Practices Summary

**SSH Command Construction**:
- Use `-t` for interactive commands (lazygit, yazi, sesh)
- Single-quote remote commands to prevent local shell expansion
- Escape paths with spaces using single quotes: `'cd /path with spaces && command'`
- Handle non-standard ports with `-p` flag

**Terminal App Wrapping**:
- Detect via `terminal: true` flag in application registry
- Extract command after `-e` flag, substitute paths, rebuild with SSH wrapper
- Reject GUI apps with clear error messages

**Validation**:
- On-demand validation via `i3pm project test-remote <name>`
- 5-second connection timeout to prevent long hangs
- Detailed error messages with troubleshooting steps

**Error Handling**:
- Fail fast on configuration errors (missing required fields, invalid paths)
- Actionable error messages with suggested fixes
- Feature-tagged debug logging for post-mortem analysis

**Testing**:
- Unit tests for Pydantic validation logic
- Integration tests for SSH command construction with edge case paths
- Sway tests for end-to-end terminal launch workflows
