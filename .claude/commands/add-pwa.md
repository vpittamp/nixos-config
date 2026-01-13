---
description: Add a new Firefox PWA to the NixOS configuration
---

You are helping the user add a new Firefox Progressive Web App (PWA) to their NixOS configuration.

# PWA Addition Workflow

This command automates the complete workflow for adding a new Firefox PWA, including icon discovery, configuration, and installation.

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

## Step 2: Gather Optional Information

**Determine customization level:**

- If user said "use defaults" or "use values above": **Skip to Step 3** with all defaults
- Otherwise: Ask explicitly if user wants to customize optional fields

### Optional Fields (with smart defaults):

3. **Description**
   - Default: `"{name} web application"` or infer from context
   - Example: `"Home Assistant - Open source home automation"`
   - Ask: "Use default description '{name} web application' or provide custom?"

4. **Categories** (XDG desktop categories)
   - Default: `"Network;"` for general web apps
   - Smart defaults by type:
     - Localhost/self-hosted: `"Network;Utility;"`
     - AI/Chat apps: `"Network;Development;"`
     - Media apps: `"AudioVideo;Video;"`
     - Office apps: `"Office;Utility;"`
   - Ask: "Use default categories '{default}' or customize?"

5. **Keywords** (semicolon-separated for launcher search)
   - Default: Lowercase name + inferred terms
   - Example: `"homeassistant;home;automation;iot;smart;"`
   - Smart inference from name and description
   - Ask: "Use auto-generated keywords or provide custom?"

6. **App Scope**
   - Default: `"global"` (always visible)
   - Alternative: `"scoped"` (project-specific, hidden when switching projects)
   - Ask only if user is familiar with i3pm: "App scope: global or scoped?"

7. **Preferred Workspace**
   - Default: Next available in range 50-70 (query pwa-sites.nix)
   - PWAs use 50-70 to avoid conflicts with standard apps (1-9)
   - Ask: "Use workspace {next_available} or specify different?"

8. **Preferred Monitor Role** (optional)
   - Default: Omit (auto-inferred from workspace: 1-2→primary, 3-5→secondary, 6+→tertiary)
   - Options: `"primary"`, `"secondary"`, `"tertiary"`
   - Ask only if user has multi-monitor setup: "Specify monitor role or use auto?"

## Step 3: Icon Discovery and Validation

This step finds or validates the icon for the PWA. Icons must be **COLORED** (not monochrome) and **ICON-ONLY** (no text/wordmarks).

### 3.1: Check for Existing Icons First

Before searching externally, check if a suitable icon already exists:

```bash
# Search for existing icons matching the PWA name
echo "Checking for existing icons..."
LOWERCASE_NAME=$(echo "{name}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
ls /etc/nixos/assets/icons/ 2>/dev/null | grep -i "$LOWERCASE_NAME" || echo "No matching icons found"
```

**If matching icon(s) found:**
```
Found existing icon(s):
{list each matching icon with full path}

Examples:
- /etc/nixos/assets/icons/notion.svg
- /etc/nixos/assets/icons/notion-alt.png

Options:
1. Use existing icon: {most_relevant_match}
2. Find a new icon (search online)
3. Provide custom path

Which would you like to use?
```

**If user selects existing icon:** Validate it (Step 3.2) then continue to Step 4

### 3.2: Validate Icon (if path provided or selected)

Verify the icon file exists AND meets requirements:

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

**If monochrome or not found:** Proceed to Step 3.3

### 3.3: Find Icon Online (if no suitable icon available)

Search multiple sources to find a high-quality, colored, icon-only image.

#### Priority Order for Icon Sources:

1. **Website manifest.json** (via chrome-devtools MCP)
2. **Apple touch icon** (via chrome-devtools MCP)
3. **Devicon** (for developer tools - use `-original.svg` for colored)
4. **SVG Repo** (via WebSearch)
5. **Brand resource sites** (official press kits)
6. **Screenshot icon element** (via chrome-devtools MCP)

#### Method A: Extract from Website (Primary)

Use **chrome-devtools MCP** to navigate and extract icons:

```javascript
// Execute via mcp__chrome-devtools to extract all icon URLs
const icons = [];

// 1. Favicon links
document.querySelectorAll('link[rel*="icon"]').forEach(link => {
  icons.push({
    url: new URL(link.href, window.location.href).href,
    sizes: link.getAttribute('sizes') || 'unknown',
    type: link.getAttribute('type') || 'image/x-icon',
    source: 'favicon'
  });
});

// 2. Apple touch icons (usually high quality, colored, icon-only)
document.querySelectorAll('link[rel*="apple-touch-icon"]').forEach(link => {
  icons.push({
    url: new URL(link.href, window.location.href).href,
    sizes: link.getAttribute('sizes') || '180x180',
    type: 'image/png',
    source: 'apple-touch-icon'
  });
});

// 3. Manifest icons (best source - often has multiple sizes and SVG)
const manifestLink = document.querySelector('link[rel="manifest"]');
if (manifestLink) {
  icons.push({
    manifestUrl: new URL(manifestLink.href, window.location.href).href,
    source: 'manifest-link'
  });
}

JSON.stringify(icons, null, 2);
```

If manifest found, fetch it:
```bash
curl -s "{manifest_url}" | jq -r '.icons[]? | "\(.src) \(.sizes) \(.type)"'
```

**Priority by quality:**
1. **SVG from manifest** - Vector, scalable, perfect quality
2. **Large PNG from manifest (512x512+)** - High quality
3. **Apple touch icon** - Usually 180x180+, colored
4. **Large favicon (256x256+)** - If SVG or large PNG

#### Method B: Devicon (for developer tools)

```bash
# Use -original.svg for COLORED version (NOT -plain.svg)
NORMALIZED_NAME=$(echo "{name}" | tr '[:upper:]' '[:lower:]')
curl -s "https://raw.githubusercontent.com/devicons/devicon/master/icons/${NORMALIZED_NAME}/${NORMALIZED_NAME}-original.svg" \
  -o "/tmp/{filename}"

# Verify it downloaded correctly
grep -q "<svg" "/tmp/{filename}" && echo "✓ Valid SVG" || echo "✗ Not found in Devicon"
```

#### Method C: SVG Repo (via WebSearch)

```bash
# Search for colored icon
WebSearch: "{site_name} icon colored svg svgrepo"
```

#### Method D: Screenshot Icon Element (last resort)

Use chrome-devtools to screenshot a visible icon:
- Look for selectors: `img[class*="logo"]`, `svg[class*="icon"]`, `.navbar img`
- Screenshot that element and save as PNG

### 3.4: Download and Save Icon

```bash
# Download with curl (follows redirects)
curl -L -o "/tmp/{filename}" "{icon_url}"

# Verify download succeeded
ls -lh "/tmp/{filename}"

# Create icons directory if needed
mkdir -p /etc/nixos/assets/icons

# Move to assets
mv "/tmp/{filename}" "/etc/nixos/assets/icons/{filename}"

# Verify final location
ls -lh "/etc/nixos/assets/icons/{filename}"
```

**Icon path for configuration:**
```nix
icon = "/etc/nixos/assets/icons/{filename}";
```

## Step 4: Generate ULID

Generate a new ULID identifier for the PWA:

```bash
/etc/nixos/scripts/generate-ulid.sh
```

**Validation:**
- Must be exactly 26 characters
- First character must be 0-7
- Remaining characters from alphabet [0-9A-HJKMNP-TV-Z]
- No I, L, O, or U characters allowed

## Step 5: Extract Domain from URL

```bash
echo "{url}" | sed -E 's|https?://([^/:]+).*|\1|'
```

Examples:
- `"https://www.notion.so"` → `"notion.so"`
- `"http://localhost:8123"` → `"localhost"`

## Step 6: Construct Scope

The scope is the URL with a trailing slash (PWA boundary):

```bash
echo "{url}/" | sed 's|//$|/|'
```

## Step 7: Find Next Available Workspace

```bash
grep "preferred_workspace" /etc/nixos/shared/pwa-sites.nix | grep -oE '[0-9]+' | sort -n | tail -1
```

Add 1 to the highest number found (or use 50 if no PWAs exist).

## Step 8: Check Service Availability (Optional for localhost)

**If URL is localhost**, check if the service is running:

```bash
timeout 2 curl -s {url} >/dev/null 2>&1 && echo "✓ Service is running" || echo "⚠️  Service may not be running at {url}"
```

## Step 9: Add Entry to pwa-sites.nix

Read `/etc/nixos/shared/pwa-sites.nix` and add the new entry before the closing `];`:

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

## Step 10: Detect Current Host and Validate Configuration

**Detect the current host for rebuild:**

```bash
# Get hostname and map to flake target
HOSTNAME=$(hostname)
echo "Detected host: $HOSTNAME"

# Check if it's a known NixOS target
case "$HOSTNAME" in
  ryzen|thinkpad|hetzner|kubevirt-sway)
    FLAKE_TARGET="$HOSTNAME"
    IMPURE_FLAG=""
    ;;
  m1|m1-mac|darwin*)
    FLAKE_TARGET="m1"
    IMPURE_FLAG="--impure"
    ;;
  *)
    echo "⚠️  Unknown host '$HOSTNAME'. Please specify flake target."
    FLAKE_TARGET="$HOSTNAME"
    IMPURE_FLAG=""
    ;;
esac

echo "Will rebuild with: sudo nixos-rebuild switch --flake .#$FLAKE_TARGET $IMPURE_FLAG"
```

**Dry-build to validate syntax:**

```bash
sudo nixos-rebuild dry-build --flake .#$FLAKE_TARGET $IMPURE_FLAG
```

Check for errors:
- Duplicate ULIDs
- Invalid ULID format
- Nix syntax errors
- Missing required fields

**If errors occur:** Fix syntax and retry

## Step 11: Rebuild System

Apply the configuration changes using the detected host:

```bash
# Use detected host from Step 10
sudo nixos-rebuild switch --flake .#$FLAKE_TARGET $IMPURE_FLAG
```

This will:
1. Generate PWA manifest JSON in /nix/store
2. Update application registry at `~/.config/i3/application-registry.json`
3. Update PWA registry at `~/.config/i3/pwa-registry.json`
4. Create desktop entry at `~/.local/share/applications/FFPWA-{ULID}.desktop`
5. Update firefoxpwa config
6. Register PWA with i3pm daemon

## Step 12: Wait for Home-Manager Activation

```bash
echo "⏳ Waiting for home-manager activation to complete..."
sleep 10
```

## Step 13: Verify firefoxpwa Profile Installation (CRITICAL)

```bash
firefoxpwa profile list 2>&1 | grep -q "{ULID}" && echo "✓ PWA profile installed" || echo "✗ PWA profile NOT found"
```

**If profile NOT found:**
```
❌ CRITICAL: firefoxpwa profile was NOT created!

Troubleshooting:
1. Check firefoxpwa is installed: which firefoxpwa
2. Check existing profiles: firefoxpwa profile list
3. Manually verify ULID is in pwa-sites.nix
4. Try rebuilding again

DO NOT proceed until profile is installed!
```

## Step 14: Verify Desktop Entry and Registries

```bash
# 1. Check desktop entry exists
if [ -f ~/.local/share/applications/FFPWA-{ULID}.desktop ]; then
  echo "✓ Desktop entry exists"
else
  echo "✗ Desktop entry NOT found"
fi

# 2. Check PWA registry
cat ~/.config/i3/pwa-registry.json | jq -r '.pwas[] | select(.ulid == "{ULID}") | "✓ PWA registry: \(.name)"' || echo "✗ Not in PWA registry"

# 3. Check app registry
cat ~/.config/i3/application-registry.json | jq -r '.applications[] | select(.display_name == "{PWA Name}") | "✓ App registry: \(.display_name)"' || echo "✗ Not in app registry"
```

## Step 15: Reload Services and Test Launch

```bash
# Reload Sway
swaymsg reload

# Restart Walker/Elephant
systemctl --user restart elephant

# Wait for services
sleep 2

# Test launch
launch-pwa-by-name "{PWA Name}" 2>&1 &
sleep 3

# Verify window appeared
swaymsg -t get_tree | grep -q "FFPWA-{ULID}" && echo "✓ PWA launched successfully!" || echo "✗ PWA did not launch"
```

## Success Criteria

Confirm all of these before marking as complete:

- ✅ Icon found/validated (colored, icon-only)
- ✅ PWA entry added to pwa-sites.nix
- ✅ Desktop entry exists at `~/.local/share/applications/FFPWA-{ULID}.desktop`
- ✅ PWA appears in registries
- ✅ PWA searchable in Walker (Meta+D)
- ✅ PWA launches successfully
- ✅ PWA opens on correct workspace
- ✅ Icon displays correctly

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| "Invalid ULID format" | ULID contains I, L, O, U or wrong length | Regenerate ULID |
| "Duplicate ULID detected" | ULID already used | Generate new ULID |
| "Icon file not found" | Icon path doesn't exist | Re-run icon discovery |
| "Icon is monochrome" | Single-color icon | Find colored version |
| "PWA not appearing in Walker" | Desktop entry not cached | `systemctl --user restart elephant` |
| "Service not running" | localhost service down | Start service |
| "Syntax error" | Invalid Nix syntax | Check brackets, semicolons, quotes |
| "Unknown host" | Hostname not in flake | Specify correct flake target |

## Files Modified/Created

### Modified:
- `/etc/nixos/shared/pwa-sites.nix` - Added new PWA entry
- `/etc/nixos/assets/icons/{filename}` - New icon (if downloaded)

### Auto-generated (during rebuild):
- `~/.local/share/applications/FFPWA-{ULID}.desktop`
- `~/.config/i3/application-registry.json`
- `~/.config/i3/pwa-registry.json`
- `~/.local/share/firefoxpwa/config.json`

## Summary

After completing all steps, provide the user with:

1. **Summary of what was added:**
   - PWA name, URL, workspace
   - ULID generated
   - Icon path used
   - Host rebuilt: {hostname}

2. **How to launch:**
   - Via Walker: `Meta+D` → type name → Enter
   - Via CLI: `launch-pwa-by-name "{Name}"`

3. **Next steps:**
   - Test the PWA by launching it
   - Consider committing changes to Git

## References

- PWA System Docs: `/etc/nixos/docs/PWA_SYSTEM.md`
- Feature 056 Quickstart: `/etc/nixos/specs/056-declarative-pwa-installation/quickstart.md`
- PWA Sites Config: `/etc/nixos/shared/pwa-sites.nix`
- App Registry Data: `/etc/nixos/home-modules/desktop/app-registry-data.nix`
