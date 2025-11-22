# Feature Specification: Remote Project Environment Support

**Feature Branch**: `087-ssh-projects`
**Created**: 2025-11-22
**Status**: Draft
**Input**: User description: "Add remote environment support to i3pm project management system, allowing terminal-based applications to be launched via SSH on remote hosts while maintaining project-scoped context and workflow integration."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create and Switch to Remote Project (Priority: P1)

A developer wants to work on a project that lives on a remote Hetzner server through their local M1 MacBook. They need to create a remote project definition that maps their local project directory to the remote working directory, then switch to that project context.

**Why this priority**: Core foundational capability - without the ability to create and switch to remote projects, no other remote functionality is possible. This is the MVP that enables all subsequent features.

**Independent Test**: Can be fully tested by creating a remote project with valid SSH credentials, switching to it, and verifying the project context is active (without launching any applications yet). Delivers the value of project context switching for remote environments.

**Acceptance Scenarios**:

1. **Given** user has SSH access to hetzner-sway.tailnet, **When** they run `i3pm project create-remote hetzner-dev --local-dir ~/projects/hetzner-dev --remote-host hetzner-sway.tailnet --remote-user vpittamp --remote-dir /home/vpittamp/dev/my-app`, **Then** a new project JSON file is created at `~/.config/i3/projects/hetzner-dev.json` with remote configuration populated
2. **Given** remote project "hetzner-dev" exists, **When** user runs `i3pm project switch hetzner-dev`, **Then** the project manager daemon sets active project to "hetzner-dev" and user sees confirmation message
3. **Given** user attempts to create remote project with invalid remote configuration (missing host/user/working_dir), **When** they run create command, **Then** system rejects creation with clear error message explaining which required fields are missing
4. **Given** user provides relative path for remote working directory, **When** they attempt to create remote project, **Then** system rejects configuration with error "Remote working_dir must be absolute path"

---

### User Story 2 - Launch Terminal Applications in Remote Context (Priority: P2)

When working in a remote project, a developer wants to launch terminal-based applications (terminal, lazygit, yazi) that automatically execute on the remote host in the correct working directory, without manually typing SSH commands.

**Why this priority**: Primary value delivery - automates the tedious SSH wrapping process and integrates remote terminal workflows into familiar local keyboard shortcuts. This is the first user-facing feature that demonstrates remote capability.

**Independent Test**: Can be tested independently by switching to a remote project and pressing a terminal launch hotkey (e.g., Win+T). Success means a terminal window appears connected to the remote host in the correct directory. Delivers immediate workflow value.

**Acceptance Scenarios**:

1. **Given** user is in remote project "hetzner-dev", **When** they press Win+T (terminal hotkey), **Then** a Ghostty terminal window opens connected via SSH to hetzner-sway.tailnet in /home/vpittamp/dev/my-app directory with active sesh session
2. **Given** user is in remote project "hetzner-dev", **When** they press Win+G (lazygit hotkey), **Then** a Ghostty window opens running lazygit via SSH on the remote host in the project's remote working directory
3. **Given** user is in remote project "hetzner-dev", **When** they press Win+Y (yazi hotkey), **Then** a Ghostty window opens running yazi file manager via SSH on the remote host in the project's remote working directory
4. **Given** terminal application fails to launch due to SSH connection error, **When** launch attempt occurs, **Then** user sees error notification with connection failure details and troubleshooting suggestions

---

### User Story 3 - Convert Existing Local Project to Remote (Priority: P3)

A developer has an existing local i3pm project and wants to convert it to work with a remote environment (e.g., they moved the codebase to a remote server), without recreating the entire project definition from scratch.

**Why this priority**: Convenience feature for migration scenarios. Lower priority because users can work around this by creating a new remote project, but enhances user experience for common workflow transitions.

**Independent Test**: Can be tested by taking an existing local project, running `i3pm project set-remote <name> --host <host> --user <user> --working-dir <remote-path>`, and verifying the project JSON is updated with remote configuration. Delivers value by preserving existing project metadata and scoped window configurations.

**Acceptance Scenarios**:

1. **Given** local project "my-app" exists with scoped window classes configured, **When** user runs `i3pm project set-remote my-app --host hetzner-sway.tailnet --user vpittamp --working-dir /home/vpittamp/dev/my-app`, **Then** project JSON is updated with remote configuration while preserving existing metadata, scoped_classes, and display settings
2. **Given** remote project "hetzner-dev" exists, **When** user runs `i3pm project unset-remote hetzner-dev`, **Then** remote configuration is removed from project JSON and project reverts to local-only mode
3. **Given** user attempts to set remote configuration with missing required fields, **When** they run set-remote command, **Then** system rejects update with clear error message explaining validation failure

---

### User Story 4 - Test Remote SSH Connectivity (Priority: P4)

Before working in a remote project, a developer wants to verify that SSH connectivity to the remote host is working correctly, to catch authentication or network issues early.

**Why this priority**: Quality-of-life feature that improves troubleshooting experience. Lower priority because users can verify connectivity manually with standard SSH commands, but provides integrated workflow validation.

**Independent Test**: Can be tested by running `i3pm project test-remote <name>` on a project with valid SSH configuration. Success means system reports connection status and any authentication/network issues. Delivers value by surfacing configuration problems before launch attempts fail.

**Acceptance Scenarios**:

1. **Given** remote project "hetzner-dev" has valid SSH configuration, **When** user runs `i3pm project test-remote hetzner-dev`, **Then** system attempts SSH connection and reports success with remote host information (hostname, user, working directory existence)
2. **Given** remote project has SSH configuration with unreachable host, **When** user runs test-remote command, **Then** system reports connection failure with network error details
3. **Given** remote project has SSH configuration with authentication issues (missing key, wrong user), **When** user runs test-remote command, **Then** system reports authentication failure with troubleshooting guidance (check SSH keys, verify user permissions)
4. **Given** remote working directory does not exist on remote host, **When** user runs test-remote command, **Then** system reports successful connection but warns that working directory is missing with suggestion to create it

---

### Edge Cases

- What happens when user attempts to launch a GUI application (VS Code, Firefox) from a remote project context? System must reject the launch with clear error message: "Cannot launch GUI application '$APP_NAME' in remote project. Remote projects only support terminal-based applications. GUI apps require X11 forwarding or local execution."
- What happens when SSH connection drops mid-session while working in a remote terminal? The terminal application (sesh/tmux) on the remote host maintains session state, and user can reconnect by re-launching the terminal application locally (new SSH connection resumes sesh session).
- What happens when remote host is temporarily unreachable (network outage, Tailscale down) and user tries to launch a terminal app? System attempts SSH connection, times out after reasonable period (configurable, default 10 seconds), and shows error notification with connection failure details.
- What happens when user switches from a remote project back to a local project? Daemon updates active project context, and subsequent terminal app launches execute locally without SSH wrapping (normal local behavior).
- What happens when user has scoped GUI applications (VS Code) configured in a remote project's scoped_classes? When user switches to that remote project, scoped GUI windows remain hidden (normal scoping behavior), but attempting to launch them shows error. User must manually exclude GUI apps from scoped_classes or use workarounds (VS Code Remote-SSH extension).
- What happens when remote working directory path contains spaces or special characters? System must properly escape the path in SSH command construction to prevent shell injection or command parsing errors.
- What happens when user configures non-standard SSH port for remote host? System respects the port configuration from remote.port field (default 22) and passes it to SSH command via `-p` flag.
- What happens when SSH key passphrase is required but not available (no SSH agent running)? SSH connection attempt prompts for passphrase interactively in the terminal window, allowing user to authenticate (standard SSH behavior).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST extend project data model to include optional remote configuration with fields: enabled (boolean), host (SSH hostname), user (SSH username), working_dir (absolute path on remote), port (integer, default 22)
- **FR-002**: System MUST validate remote working directory is an absolute path (starts with '/') when remote configuration is enabled
- **FR-003**: System MUST provide CLI command `i3pm project create-remote <name>` with required flags `--local-dir`, `--remote-host`, `--remote-user`, `--remote-dir` and optional flag `--port`
- **FR-004**: System MUST provide CLI command `i3pm project set-remote <name>` to add or update remote configuration on existing projects
- **FR-005**: System MUST provide CLI command `i3pm project unset-remote <name>` to remove remote configuration from projects
- **FR-006**: System MUST provide CLI command `i3pm project test-remote <name>` to verify SSH connectivity and remote working directory existence
- **FR-007**: System MUST detect when active project has remote configuration enabled during app launch
- **FR-008**: System MUST identify terminal-based applications via "terminal" flag in app registry
- **FR-009**: System MUST wrap terminal application launch commands with SSH for remote projects by extracting command after `-e` flag, substituting remote working directory, and rebuilding command as `ghostty -e bash -c "ssh -t user@host 'cd /remote/path && <original-command>>'"`
- **FR-010**: System MUST reject GUI application launches in remote project contexts with clear error message explaining limitation
- **FR-011**: System MUST substitute `$PROJECT_DIR` placeholder with remote working_dir in terminal commands for remote projects
- **FR-012**: System MUST inject I3PM_* environment variables locally (before SSH execution) to maintain project context metadata
- **FR-013**: System MUST support Tailscale hostnames (e.g., hetzner-sway.tailnet) in remote host configuration
- **FR-014**: System MUST support custom SSH ports via `-p` flag when remote.port is not 22
- **FR-015**: System MUST properly escape remote working directory paths containing spaces or special shell characters in SSH command construction
- **FR-016**: System MUST persist remote project configuration to `~/.config/i3/projects/<name>.json` with remote field as optional object
- **FR-017**: System MUST validate required remote configuration fields (host, user, working_dir) are non-empty when remote.enabled is true
- **FR-018**: System MUST maintain backward compatibility with existing local-only project JSON files (remote field is optional)

### Key Entities

- **Remote Project Configuration**: Represents SSH connection parameters for remote project environments. Key attributes: enabled (boolean flag), host (SSH hostname or Tailscale domain), user (SSH username), working_dir (absolute path to project on remote filesystem), port (SSH port number). Relationships: Optional extension of Project entity.
- **Project**: Existing entity extended with optional remote configuration. Key attributes: name, directory (local path), display_name, icon, scoped_classes, remote (optional RemoteConfig object). Relationships: Has zero or one RemoteConfig.
- **Application Registry Entry**: Defines launchable applications with metadata. Key attributes: name, command, parameters (may include $PROJECT_DIR substitution), terminal (boolean flag indicating terminal-based app). Relationships: Referenced during app launch to determine SSH wrapping behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can create a remote project and launch a terminal application on the remote host in under 30 seconds (measured from running create-remote command to seeing active remote terminal)
- **SC-002**: Terminal applications launch in remote project contexts with SSH wrapping applied automatically, without requiring manual SSH command entry (100% of terminal app launches in remote projects)
- **SC-003**: System correctly handles SSH connection failures with informative error messages, achieving 95% user understanding of resolution steps (validated via error message clarity testing)
- **SC-004**: Remote project configuration validation prevents 100% of invalid configurations (missing required fields, relative paths) from being persisted to project files
- **SC-005**: Switching between local and remote projects maintains correct application launch behavior (local vs. SSH-wrapped) with 100% accuracy
- **SC-006**: System supports all existing terminal-based applications (terminal, lazygit, yazi, btop, htop, k9s, sesh) in remote contexts without application-specific code changes (100% compatibility)
- **SC-007**: Remote project workflows integrate with existing project management features (project switching, scoped window management) without breaking local project functionality (0 regressions in local project tests)

## Constraints & Dependencies

### Technical Dependencies

- Requires SSH client available on local system (standard on NixOS)
- Requires SSH key-based authentication configured between local and remote hosts (manual setup by user via ~/.ssh/config or ssh-keygen)
- Requires Tailscale networking if using Tailscale hostnames for remote hosts (already installed on both M1 and Hetzner systems)
- Requires identical terminal applications (ghostty, lazygit, yazi, etc.) installed on remote host for commands to execute successfully
- Requires sesh (session manager) installed on remote host for terminal session persistence

### Limitations

- **GUI Applications Not Supported**: Remote projects cannot launch GUI applications (VS Code, Firefox, PWAs) without complex X11 forwarding setup. Users must use alternative workflows (VS Code Remote-SSH extension, local GUI with remote terminal apps, or VNC to remote desktop).
- **Window Matching Ambiguity**: Remote terminal applications appear to window manager as local Ghostty windows (com.mitchellh.ghostty class), making them indistinguishable from each other for window-based project scoping. Impact: All remote terminal windows look identical to daemon.
- **Environment Variable Scope**: I3PM_* environment variables are injected locally before SSH execution, so remote processes do not have direct access to them. Impact: Minimal, as these variables are primarily used for local window matching.
- **Session Continuity**: SSH connection drops do not automatically reconnect. Users must manually re-launch terminal applications to reconnect (sesh/tmux sessions preserve remote state).
- **Performance**: Remote terminal launches incur SSH connection establishment overhead (typically 1-3 seconds depending on network latency and Tailscale routing).

### User Responsibilities

- User must configure SSH key-based authentication between local and remote systems before creating remote projects
- User must ensure remote working directories exist on remote hosts (system can detect this via test-remote command, but does not automatically create them)
- User must install required terminal applications on remote hosts for commands to execute
- User must configure Tailscale on both systems if using Tailscale hostnames for remote connectivity
- User must exclude GUI applications from scoped_classes for remote projects or accept that they cannot be launched in remote project contexts

## Assumptions

- SSH key-based authentication is preferred over password authentication (more secure, better for automation)
- Default SSH port is 22 unless explicitly configured otherwise
- Remote hosts are running compatible shell environments (bash/zsh) for command execution
- Users have appropriate file system permissions on remote hosts to access configured working directories
- Tailscale networking provides reliable connectivity between local and remote systems (existing infrastructure)
- Terminal applications (ghostty, lazygit, yazi, sesh) use consistent command-line interfaces across local and remote systems
- Users understand SSH fundamentals and can troubleshoot basic connectivity issues (key permissions, network reachability)

## Out of Scope

- Automatic SSH key generation and distribution to remote hosts (user must configure manually)
- X11 forwarding or Wayland forwarding for GUI application support
- Automatic installation of required applications on remote hosts
- Automatic creation of remote working directories
- File synchronization between local and remote project directories (users must manage this via git, rsync, or other tools)
- Remote desktop protocols (VNC/RDP) for full GUI access (already exists separately via WayVNC)
- Multi-hop SSH connections (bastion hosts, SSH proxying)
- SendEnv configuration to pass I3PM_* environment variables to remote processes
- Monitoring or logging of remote process execution (beyond standard SSH output)
- Automatic SSH connection keep-alive or reconnection on network interruption
- Support for SSH password authentication (key-based only)
- Integration with VS Code Remote-SSH extension (user must configure separately)
