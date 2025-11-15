---
description: Add a new Firefox PWA to the NixOS configuration
---

You are helping the user add a new Firefox Progressive Web App (PWA) to their NixOS configuration.

# PWA Addition Workflow

This command automates the complete workflow for adding a new Firefox PWA, from gathering information to testing the installation.

## Step 0: Pre-flight Checks (Critical)

Before gathering information, perform these validation checks:

### Check 1: Verify Name Uniqueness

If the user has mentioned a PWA name in the conversation:

```bash
# Check if name already exists in pwa-sites.nix
grep -i "name = \"$PROPOSED_NAME\"" /etc/nixos/shared/pwa-sites.nix
```

**If name exists:**
```
⚠️  PWA name "$PROPOSED_NAME" already exists in configuration!

Existing PWA:
- Name: $EXISTING_NAME
- URL: $EXISTING_URL
- Workspace: $WORKSPACE

Please provide a UNIQUE name (e.g., "$PROPOSED_NAME Web", "$PROPOSED_NAME Cloud", etc.)
```

**If unique:** Proceed to Step 1

## Step 1: Gather Required Information

**Handle command arguments intelligently:**

If user invokes with arguments (e.g., `/add-pwa use values above`):
- Parse context from previous conversation
- Extract PWA name, URL, icon path from prior messages
- **CRITICAL**: Validate name uniqueness first (Step 0)
- Skip redundant questions

If user invokes without context or arguments are unclear:
- Ask explicitly for required information below

### Required Information:

1. **PWA Name** (required)
   - Example: "Notion", "Uber Eats", "Discord", "Home Assistant Web"
   - Format: Human-readable, proper case
   - **MUST BE UNIQUE** - will be validated against existing PWAs
   - This will be the display name in Walker/launchers
   - **If mentioned in previous conversation**, extract and use it (but still validate uniqueness)

2. **URL** (required)
   - Example: "https://www.notion.so", "http://localhost:8123"
   - Format: Full URL (HTTPS for web services, HTTP for localhost)
   - This is where the PWA will open
   - **For self-hosted services**, check user's NixOS config first:
     ```bash
     # Search for localhost services
     grep -r "localhost:[0-9]" /etc/nixos/modules/services/*.nix 2>/dev/null | head -5
     grep -r "external_url\|internal_url" /etc/nixos/modules/services/*.nix 2>/dev/null | head -5
     ```
   - **If found in config**, ask user which URL to use (localhost vs external)

3. **Icon Path** (optional - will auto-check existing icons)
   - Example: "/etc/nixos/assets/icons/notion.svg"
   - **If not provided**, will automatically:
     1. Check `/etc/nixos/assets/icons/` for existing matching icons
     2. Offer to reuse existing icons if found
     3. Run `/find-pwa-icon` to find new icon if needed
   - **If icon was found in previous /find-pwa-icon command**, use that path
   - If provided, will validate it exists and is colored
   - Supported formats: .svg, .png, .jpeg

## Step 2: Gather Optional Information

**Determine customization level:**

- If user said "use defaults" or "use values above": **Skip to Step 3** with all defaults
- Otherwise: Ask explicitly if user wants to customize optional fields

### Optional Fields (with smart defaults):

4. **Description**
   - Default: `"{name} web application"` or infer from context
   - Example: `"Home Assistant - Open source home automation"`
   - Ask: "Use default description '{name} web application' or provide custom?"

5. **Categories** (XDG desktop categories)
   - Default: `"Network;"` for general web apps
   - Smart defaults by type:
     - Localhost/self-hosted: `"Network;Utility;"`
     - AI/Chat apps: `"Network;Development;"`
     - Media apps: `"AudioVideo;Video;"`
     - Office apps: `"Office;Utility;"`
   - Ask: "Use default categories '{default}' or customize?"

6. **Keywords** (semicolon-separated for launcher search)
   - Default: Lowercase name + inferred terms
   - Example: `"homeassistant;home;automation;iot;smart;"`
   - Smart inference from name and description
   - Ask: "Use auto-generated keywords or provide custom?"

7. **App Scope**
   - Default: `"global"` (always visible)
   - Alternative: `"scoped"` (project-specific, hidden when switching projects)
   - Ask only if user is familiar with i3pm: "App scope: global or scoped?"

8. **Preferred Workspace**
   - Default: Next available in range 50-70 (query pwa-sites.nix)
   - PWAs use 50-70 to avoid conflicts with standard apps (1-9)
   - Ask: "Use workspace {next_available} or specify different?"

9. **Preferred Monitor Role** (optional)
   - Default: Omit (auto-inferred from workspace: 1-2→primary, 3-5→secondary, 6+→tertiary)
   - Options: `"primary"`, `"secondary"`, `"tertiary"`
   - Ask only if user has multi-monitor setup: "Specify monitor role or use auto?"

## Step 3: Handle Icon (Check Existing, Validate, or Find)

### 3.1: Check for Existing Icons First

Before validating a provided path or finding a new icon, search for existing icons that might match:

```bash
# Search for existing icons matching the PWA name
echo "Checking for existing icons..."
ls /etc/nixos/assets/icons/ 2>/dev/null | grep -i "{lowercase-name}" || echo "No matching icons found"
```

**If matching icon(s) found:**
```
Found existing icon(s):
{list each matching icon with full path}

Examples:
- /etc/nixos/assets/icons/vscode.svg
- /etc/nixos/assets/icons/vscode-dev.svg

Options:
1. Use existing icon: {most_relevant_match}
2. Find a new icon (run /find-pwa-icon)
3. Provide custom path
4. Skip (if icon already provided by user)

Which would you like to use?
```

**If user selects existing icon:** Validate it (Step 3.2) then continue to Step 4

**If user wants new icon or no matches found:** Continue to Step 3.2

### 3.2: Validate Provided Icon (if applicable)

**If Icon Path Was Provided by User:**

Verify the icon file exists AND is colored:

```bash
# Check file exists
ls -lh {icon_path}

# Validate icon is COLORED (not monochrome)
if [[ "{icon_path}" == *.svg ]]; then
  # Count unique fill colors in SVG
  COLORS=$(grep -oE 'fill="#[^"]+"|fill:[^;]+;' "{icon_path}" | sort | uniq | wc -l)
  if [ "$COLORS" -lt 2 ]; then
    echo "⚠️  WARNING: Icon appears to be monochrome (only $COLORS color found)"
    echo "PWA icons should be FULL COLOR for better visibility"
  else
    echo "✓ Icon has multiple colors ($COLORS unique colors)"
  fi
fi
```

**If exists AND colored:** Continue to Step 4

**If monochrome or not found:**
```
⚠️  Issue with icon at {icon_path}

Problem: Icon is monochrome/single-color OR file not found
Required: PWA icons must be FULL COLOR and icon-only (no text)

Options:
1. Find a colored icon automatically (run /find-pwa-icon)
2. Provide different path to a colored icon
3. Check existing icons again (back to Step 3.1)
4. Abort
```

### 3.3: Find New Icon (if no suitable icon available)

**If Icon Path Was NOT Provided AND No Existing Icon Selected:**

**Invoke /find-pwa-icon command directly:**

```
No suitable icon available. Running /find-pwa-icon to search for {PWA Name} icon...
```

Then invoke `/find-pwa-icon` with the PWA name and URL:
- This will search chrome-devtools MCP, Devicon, SVG Repo, etc.
- Returns icon path or prompts user for manual download
- Use the returned path for subsequent steps

**Do NOT duplicate icon-finding logic here** - always use /find-pwa-icon command.

## Step 4: Generate ULID

Generate a new ULID identifier for the PWA using the validated script.

**Primary method (using generate-ulid.sh):**
```bash
/etc/nixos/scripts/generate-ulid.sh
```

This script generates a valid ULID according to the [canonical spec](https://github.com/ulid/spec):
- 26 characters from Crockford Base32 alphabet: 0123456789ABCDEFGHJKMNPQRSTVWXYZ (excludes I, L, O, U)
- First character restricted to 0-7 (48-bit timestamp constraint)
- Maximum valid ULID: 7ZZZZZZZZZZZZZZZZZZZZZZZZZ

**Example output:**
```
2T24XFCECYHF4SHEK0PZA83KF5
```

**Validation:**
- Must be exactly 26 characters
- First character must be 0-7
- Remaining characters from alphabet [0-9A-HJKMNP-TV-Z]
- No I, L, O, or U characters allowed

## Step 5: Extract Domain from URL

Extract the domain from the URL for the `domain` field:

```bash
echo "{url}" | sed -E 's|https?://([^/:]+).*|\1|'
```

Examples:
- `"https://www.notion.so"` → `"notion.so"`
- `"http://localhost:8123"` → `"localhost"`
- `"http://192.168.1.100:8080"` → `"192.168.1.100"`

## Step 6: Construct Scope

The scope is the URL with a trailing slash (PWA boundary):

```bash
# Add trailing slash if not present
echo "{url}/" | sed 's|//$|/|'
```

Examples:
- `"https://www.notion.so"` → `"https://www.notion.so/"`
- `"http://localhost:8123"` → `"http://localhost:8123/"`

## Step 7: Find Next Available Workspace

Check existing PWAs to find the next available workspace in range 50-70:

```bash
grep "preferred_workspace" /etc/nixos/shared/pwa-sites.nix | grep -oE '[0-9]+' | sort -n | tail -1
```

Add 1 to the highest number found (or use 50 if no PWAs exist, or 64 if highest is 63+).

## Step 8: Check Service Availability (Optional for localhost)

**If URL is localhost**, check if the service is actually running:

```bash
timeout 2 curl -s {url} >/dev/null 2>&1 && echo "✓ Service is running" || echo "⚠️  Service may not be running at {url}"
```

**Note to user:**
```
{if service not running}
⚠️  Note: The service doesn't appear to be running at {url}
The PWA will be configured but won't load until the service starts.
Proceed anyway? (y/n)
```

## Step 9: Add Entry to pwa-sites.nix

Read the current file and add the new entry:

1. Read `/etc/nixos/shared/pwa-sites.nix`
2. Find the closing `];` of the `pwaSites` list
3. Add new entry **before** the closing `];`

Template for new entry:

```nix
    # {Name}
    {
      name = "{Name}";
      url = "{URL}";
      domain = "{domain}";
      icon = "{icon_path}";
      description = "{description}";
      categories = "{categories}";
      keywords = "{keywords}";
      scope = "{scope}";
      ulid = "{ULID}";  # Generated {current_date}
      # App registry metadata
      app_scope = "{app_scope}";
      preferred_workspace = {workspace_number};
      {only_if_specified: preferred_monitor_role = "{role}";}
    }
```

**Example:**
```nix
    # Home Assistant
    {
      name = "Home Assistant";
      url = "http://localhost:8123";
      domain = "localhost";
      icon = "/etc/nixos/assets/icons/home-assistant.svg";
      description = "Home Assistant - Open source home automation";
      categories = "Network;Utility;";
      keywords = "homeassistant;home;automation;iot;smart-home;";
      scope = "http://localhost:8123/";
      ulid = "AA92RQ3MW6JN8Z3X01GZ7W2NSJ";  # Generated 2025-11-15
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 64;
    }
```

## Step 10: Validate Configuration Syntax

Test the configuration with a dry-build:

```bash
sudo nixos-rebuild dry-build --flake .#m1 --impure
```

Check for errors:
- Duplicate ULIDs
- Invalid ULID format
- Nix syntax errors (missing brackets, commas, quotes)
- Missing required fields

**If errors occur:**
- Show error message
- Fix syntax
- Retry dry-build

## Step 11: Rebuild System

Apply the configuration changes:

```bash
sudo nixos-rebuild switch --flake .#m1 --impure
```

This will:
1. Generate PWA manifest JSON in /nix/store
2. Update application registry at `~/.config/i3/application-registry.json`
3. Update PWA registry at `~/.config/i3/pwa-registry.json`
4. **Create desktop entry** at `~/.local/share/applications/FFPWA-{ULID}.desktop` (via home-manager activation)
5. Update firefoxpwa config at `~/.local/share/firefoxpwa/config.json`
6. Register PWA with i3pm daemon

**Note:** Desktop entries are created automatically during this step by home-manager activation hooks. No separate installation step is needed.

## Step 12: Wait for Home-Manager Activation (CRITICAL)

After the rebuild, home-manager activation scripts run to install PWAs. This can take 5-10 seconds.

```bash
echo "⏳ Waiting for home-manager activation to complete..."
sleep 10
```

## Step 13: Verify firefoxpwa Profile Installation (CRITICAL)

**This is the most important verification step** - the PWA won't work without a firefoxpwa profile.

```bash
# Check if firefoxpwa profile was created
firefoxpwa profile list 2>&1 | grep -q "{ULID}" && echo "✓ PWA profile installed" || echo "✗ PWA profile NOT found"
```

**If profile NOT found:**
```
❌ CRITICAL: firefoxpwa profile was NOT created!

This means the PWA won't launch. Common causes:
1. Home-manager activation didn't run
2. firefoxpwa-declarative module not enabled
3. ULID format invalid

Troubleshooting:
1. Check firefoxpwa is installed: which firefoxpwa
2. Check existing profiles: firefoxpwa profile list
3. Manually verify ULID is in pwa-sites.nix: grep {ULID} /etc/nixos/shared/pwa-sites.nix
4. Try running: sudo nixos-rebuild switch --flake .#m1 --impure again

DO NOT proceed to next steps until profile is installed!
```

**If profile found:** Continue to Step 14

## Step 14: Verify Desktop Entry and Registries

Check all integration points:

```bash
# 1. Check desktop entry exists
if [ -f ~/.local/share/applications/FFPWA-{ULID}.desktop ]; then
  echo "✓ Desktop entry exists"
  cat ~/.local/share/applications/FFPWA-{ULID}.desktop | grep "^Name="
else
  echo "✗ Desktop entry NOT found"
fi

# 2. Check PWA registry
cat ~/.config/i3/pwa-registry.json | jq -r '.pwas[] | select(.ulid == "{ULID}") | "✓ PWA registry: \(.name) - WS \(.preferred_workspace)"' || echo "✗ Not in PWA registry"

# 3. Check app registry
cat ~/.config/i3/application-registry.json | jq -r '.applications[] | select(.name | endswith("-pwa")) | select(.display_name == "{PWA Name}") | "✓ App registry: \(.display_name) - WS \(.preferred_workspace)"' || echo "✗ Not in app registry"
```

**Expected output:**
```
✓ Desktop entry exists
Name={PWA Name}
✓ PWA registry: {lowercase-name} - WS {workspace}
✓ App registry: {PWA Name} - WS {workspace}
```

**If any checks fail:** See Step 16 (Troubleshooting)

## Step 15: Reload Services and Test Launch

Reload services to pick up the new PWA:

```bash
# Reload Sway (refreshes i3pm daemon with new PWA config)
swaymsg reload

# Restart Walker/Elephant (picks up new desktop entry)
systemctl --user restart elephant

# Wait for services to restart
sleep 2
```

**Now test launch:**

```bash
# Test via command line
launch-pwa-by-name "{PWA Name}" 2>&1 &

# Wait a moment
sleep 3

# Check if window appeared
swaymsg -t get_tree | grep -q "FFPWA-{ULID}" && echo "✓ PWA launched successfully!" || echo "✗ PWA did not launch"
```

**Expected:** Browser window opens with the PWA

**If launch fails:** See Step 16 (Troubleshooting)

## Success Criteria

Confirm all of these before marking as complete:

- ✅ PWA entry added to pwa-sites.nix
- ✅ Desktop entry exists at `~/.local/share/applications/FFPWA-{ULID}.desktop`
- ✅ PWA appears in registries (pwa-registry.json, application-registry.json)
- ✅ PWA searchable in Walker (Meta+D)
- ✅ PWA launches successfully
- ✅ PWA opens on correct workspace
- ✅ Icon displays correctly in launcher
- ✅ Window class matches `FFPWA-{ULID}` pattern

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| "Invalid ULID format" | ULID contains I, L, O, U or wrong length | Regenerate ULID with Python method |
| "Duplicate ULID detected" | ULID already used in pwa-sites.nix | Generate new ULID |
| "Icon file not found" | Icon path doesn't exist | Run /find-pwa-icon or provide correct path |
| "PWA not appearing in Walker" | Desktop entry not cached | `systemctl --user restart elephant` |
| "Service not running" | localhost service down | Start service or note to user |
| "Syntax error" in rebuild | Invalid Nix syntax | Check brackets, semicolons, quotes |
| "Desktop entry not created" | Rebuild didn't activate home-manager | Check rebuild output for activation errors |

## Files Modified/Created

### Modified:
- `/etc/nixos/shared/pwa-sites.nix` - Added new PWA entry

### Auto-generated (during rebuild):
- `~/.local/share/applications/FFPWA-{ULID}.desktop` - Desktop entry (symlink to /nix/store)
- `~/.config/i3/application-registry.json` - App registry with PWA
- `~/.config/i3/pwa-registry.json` - PWA metadata
- `~/.local/share/firefoxpwa/config.json` - firefoxpwa database

## Summary

After completing all steps, provide the user with:

1. **Summary of what was added:**
   - PWA name, URL, workspace
   - ULID generated
   - Icon path used
   - Files modified

2. **How to launch:**
   - Via Walker: `Meta+D` → type name → Enter
   - Via CLI: `launch-pwa-by-name "{Name}"`

3. **Next steps:**
   - Test the PWA by launching it
   - Verify it loads correctly (especially for localhost services)
   - Consider committing changes to Git
   - Deploy to other machines if needed

4. **For localhost services:**
   - Remind user to ensure service is running
   - Provide command to start service if applicable

## Additional Notes

- **Cross-machine portability:** The static ULID ensures the PWA works identically on all NixOS systems
- **Declarative management:** All PWA metadata is version-controlled in `pwa-sites.nix`
- **Automatic integration:** PWAs automatically integrate with i3pm, Walker, and workspace management
- **No manual installation:** Desktop entries are created automatically during nixos-rebuild via home-manager activation
- **Service dependencies:** For localhost PWAs, ensure the underlying service is configured and running

## References

- PWA System Docs: `/etc/nixos/docs/PWA_SYSTEM.md`
- Feature 056 Quickstart: `/etc/nixos/specs/056-declarative-pwa-installation/quickstart.md`
- PWA Sites Config: `/etc/nixos/shared/pwa-sites.nix`
- App Registry Data: `/etc/nixos/home-modules/desktop/app-registry-data.nix`
- Icon Finder: Use `/find-pwa-icon` command for automatic icon discovery
