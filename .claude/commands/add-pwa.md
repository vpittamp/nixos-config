---
description: Add a new Google Chrome PWA to the NixOS configuration
---

You are helping the user add a new Google Chrome Progressive Web App (PWA) to their NixOS configuration.

# PWA Addition Workflow

This command automates the complete workflow for adding a new Google Chrome PWA, including icon discovery, configuration, and installation. It supports both **single PWAs** and **multi-environment PWAs** (dev/staging/prod/ryzen variants of the same service).

## Detect Mode: Single vs Multi-Environment

Before starting, determine which workflow to follow:

**Multi-environment indicators** (use Multi-Environment Workflow below):
- User mentions "dev", "staging", "prod", "ryzen" environments
- User provides Tailscale ingress URLs with environment suffixes (e.g., `*-staging.tail286401.ts.net`)
- User asks for multiple variants of the same service
- User mentions "cluster", "Talos", or "Kubernetes" services

**Single PWA indicators** (use Standard Workflow below):
- User wants one PWA for a single URL
- No environment variants needed

---

# Multi-Environment PWA Workflow

For services deployed across multiple environments (dev/staging/prod/ryzen clusters).

## ME-Step 0: Identify Services and Environments

Parse the user's request to determine:
1. **Services**: Which services need PWAs (e.g., grafana, keycloak, langfuse)
2. **Environments**: Which environments (dev, staging, prod, ryzen)
3. **URL pattern**: Usually `https://{service}-{env}.tail286401.ts.net`

### Current Environment Conventions

| Environment | URL Suffix | Badge Color | Letter | Workspace Range |
|-------------|-----------|-------------|--------|-----------------|
| Dev | `-dev` | Green `#10b981` | D | 121-131 |
| Staging | `-staging` | Amber `#f59e0b` | S | 132-142 |
| Prod | `-prod` | Blue `#3b82f6` | P | 143-153 |
| Ryzen | `-ryzen` | Purple `#a855f7` | R | (existing, varies) |

### Current Service-to-Icon Mapping

| Service | Source Icon | Notes |
|---------|------------|-------|
| dapr | `dapr.svg` | Dapr Dashboard |
| grafana | `grafana.svg` | Observability |
| keycloak | `keycloak.svg` | Identity/Auth |
| langfuse | `langfuse.svg` | LLM Observability |
| loki | `loki.svg` | Log aggregation (no Ryzen entry) |
| mcp-inspector-client | `mcp-inspector.svg` | MCP debugging client |
| mcp-inspector-proxy | `mcp-inspector.svg` | MCP debugging proxy |
| mimir | `mimir.svg` | Metrics backend (no Ryzen entry) |
| phoenix | `phoenix-azire.svg` | AI Tracing |
| redisinsight | `redis-insights.svg` | Redis GUI |
| workflow-builder | `ai-workflow-builder.svg` | AI Workflow Builder |

## ME-Step 1: Check for Existing Base Icons

For each service, verify the source icon exists:

```bash
for icon in dapr.svg grafana.svg keycloak.svg langfuse.svg loki.svg mcp-inspector.svg mimir.svg phoenix-azire.svg redis-insights.svg ai-workflow-builder.svg; do
  [ -f "assets/icons/$icon" ] && echo "✓ $icon" || echo "✗ MISSING: $icon"
done
```

**If any base icon is missing:** Find/download it using the Icon Discovery process (Step 3 in Standard Workflow below) before proceeding.

## ME-Step 2: Generate Environment-Badged Icons

Use the existing badge generation scripts to create environment-specific icon variants:

### Single Service Icon

```bash
scripts/generate-env-icon.sh <source-icon> <env> <output-path>
# Example:
scripts/generate-env-icon.sh assets/icons/grafana.svg dev assets/icons/grafana-dev.png
```

### Batch Generation (All Services)

```bash
scripts/generate-all-env-icons.sh
```

This generates all icon variants for all configured services. Output naming: `{service}-{env}.png`

### How Icon Badges Work

The badge system overlays a colored circle with an environment letter onto the bottom-right corner of the base icon:
- **Input**: Source SVG icon (any service)
- **Output**: 512x512 PNG with environment badge
- **Badge**: 40% diameter circle, white 6px border, colored inner circle, white letter
- **Pipeline**: `rsvg-convert` (SVG→PNG) → `magick` composite (badge overlay)

### Adding a New Service to the Badge System

If adding a service not in the current `generate-all-env-icons.sh` mapping, edit the script:

```bash
# Add to the ICON_MAP associative array in scripts/generate-all-env-icons.sh
[new-service]="new-service-icon.svg"

# Add to ALL_ENV_SERVICES or NO_RYZEN_SERVICES array depending on whether it has a Ryzen deployment
```

## ME-Step 3: Generate ULIDs

Generate one ULID per new PWA entry:

```bash
# Generate N ULIDs (one per service × environment combination)
for i in $(seq 1 N); do scripts/generate-ulid.sh; done
```

## ME-Step 4: Add Entries to pwa-sites.nix

Add entries organized by environment block. Use this template for each entry:

```nix
    # {Service Display Name} ({Environment})
    {
      name = "{Service} {Env}";  # e.g., "Grafana Dev"
      url = "https://{service}-{env}.tail286401.ts.net";
      domain = "{service}-{env}.tail286401.ts.net";
      icon = iconPath "{service}-{env}.png";
      description = "{Service description} - {Env} environment";
      categories = "Network;Development;";
      keywords = "{service};{relevant-keywords};{env};";
      scope = "https://{service}-{env}.tail286401.ts.net/";
      ulid = "{GENERATED_ULID}";
      app_scope = "global";
      preferred_workspace = {workspace_number};  # See workspace table above
      preferred_monitor_role = "secondary";
      routing_domains = [ "{service}-{env}.tail286401.ts.net" ];
    }
```

**Naming convention**: `"Service Dev"`, `"Service Staging"`, `"Service Prod"`, `"Service Ryzen"`

**Workspace allocation** (alphabetical within each environment block):

| Service | Dev | Staging | Prod |
|---------|-----|---------|------|
| dapr | 121 | 132 | 143 |
| grafana | 122 | 133 | 144 |
| keycloak | 123 | 134 | 145 |
| langfuse | 124 | 135 | 146 |
| loki | 125 | 136 | 147 |
| mcp-inspector-client | 126 | 137 | 148 |
| mcp-inspector-proxy | 127 | 138 | 149 |
| mimir | 128 | 139 | 150 |
| phoenix | 129 | 140 | 151 |
| redisinsight | 130 | 141 | 152 |
| workflow-builder | 131 | 142 | 153 |

For new services not in this table, find the next available workspace in each range.

## ME-Step 5: Rename Existing Entries (if applicable)

When adding environment variants for services that already have Ryzen PWAs, rename the existing entries for consistency:

| Old Name Pattern | New Name Pattern | New Icon |
|-----------------|------------------|----------|
| "Grafana Local" | "Grafana Ryzen" | `grafana-ryzen.png` |
| "Dapr Dashboard" | "Dapr Ryzen" | `dapr-ryzen.png` |
| "Phoenix Azire" | "Phoenix Ryzen" | `phoenix-ryzen.png` |
| "{Service}" | "{Service} Ryzen" | `{service}-ryzen.png` |

Keep the existing ULID, URL, and workspace. Only change `name`, `icon`, and add `ryzen;` to `keywords`.

Then continue to **Step 10** (Validate) below.

---

# Standard Single-PWA Workflow

## Step 0: Pre-flight Checks (Critical)

Before gathering information, perform these validation checks:

### Check 1: Verify Name Uniqueness

If the user has mentioned a PWA name in the conversation:

```bash
# Check if name already exists in pwa-sites.nix
grep -i "name = \"$PROPOSED_NAME\"" shared/pwa-sites.nix
```

**If name exists:**
```
PWA name "$PROPOSED_NAME" already exists in configuration!

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
   - Default: Next available workspace (query pwa-sites.nix for highest used)
   - PWAs use workspaces 50+ to avoid conflicts with standard apps (1-49)
   - Single PWAs: 50-120 range
   - Multi-environment PWAs: Dev 121-131, Staging 132-142, Prod 143-153
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
ls assets/icons/ 2>/dev/null | grep -i "$LOWERCASE_NAME" || echo "No matching icons found"
```

**If matching icon(s) found:**
```
Found existing icon(s):
{list each matching icon with full path}

Examples:
- assets/icons/notion.svg
- assets/icons/notion-alt.png

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
mkdir -p assets/icons

# Move to assets
mv "/tmp/{filename}" "assets/icons/{filename}"

# Verify final location
ls -lh "assets/icons/{filename}"
```

**Icon path for configuration:**
```nix
icon = iconPath "{filename}";
```

## Step 4: Generate ULID

Generate a new ULID identifier for the PWA:

```bash
scripts/generate-ulid.sh
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
grep "preferred_workspace" shared/pwa-sites.nix | grep -oE '[0-9]+' | sort -n | tail -1
```

Add 1 to the highest number found (or use 50 if no PWAs exist).

## Step 8: Check Service Availability (Optional for localhost)

**If URL is localhost**, check if the service is running:

```bash
timeout 2 curl -s {url} >/dev/null 2>&1 && echo "✓ Service is running" || echo "⚠️  Service may not be running at {url}"
```

## Step 9: Add Entry to pwa-sites.nix

Read `shared/pwa-sites.nix` and add the new entry before the closing list:

```nix
    # {Name}
    {
      name = "{Name}";
      url = "{URL}";
      domain = "{domain}";
      icon = iconPath "{filename}";
      description = "{description}";
      categories = "{categories}";
      keywords = "{keywords}";
      scope = "{scope}";
      ulid = "{ULID}";  # Generated {current_date}
      # App registry metadata
      app_scope = "{app_scope}";
      preferred_workspace = {workspace_number};
      {only_if_specified: preferred_monitor_role = "{role}";}
      routing_domains = [ "{domain}" ];
    }
```

Important:
- edit the source file only: `shared/pwa-sites.nix`
- do not edit generated files such as `~/.config/i3/application-registry.json` or `~/.config/i3/pwa-registry.json`
- the runtime app name will be derived from the display name as lowercase-with-dashes plus `-pwa`

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
1. Rebuild the declarative PWA source into the app registry
2. Update `~/.config/i3/application-registry.json`
3. Update `~/.config/i3/pwa-registry.json`
4. Create a desktop entry under `~/.local/share/i3pm-applications/applications/`
5. Make the PWA available to Walker, `i3pm launch open`, and `launch-pwa-by-name`

## Step 12: Wait for Home Manager activation

```bash
echo "⏳ Waiting for home-manager activation to complete..."
sleep 10
```

## Step 13: Verify generated outputs

Derive the runtime app slug:

```bash
APP_SLUG=$(printf '%s' "{PWA Name}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
APP_NAME="${APP_SLUG}-pwa"
```

```bash
# 1. Check desktop entry exists
if [ -f "$HOME/.local/share/i3pm-applications/applications/${APP_NAME}.desktop" ]; then
  echo "✓ Desktop entry exists"
else
  echo "✗ Desktop entry NOT found"
fi

# 2. Check PWA registry
cat ~/.config/i3/pwa-registry.json | jq -r '.pwas[] | select(.ulid == "{ULID}") | "✓ PWA registry: \(.name)"' || echo "✗ Not in PWA registry"

# 3. Check app registry by runtime app name
cat ~/.config/i3/application-registry.json | jq -r --arg app "$APP_NAME" '.applications[] | select(.name == $app) | "✓ App registry: \(.name) [\(.display_name)]"' || echo "✗ Not in app registry"
```

## Step 14: Test launch

Do not restart old launcher services or reload Sway unless there is a separate issue. The rebuild-generated desktop entry and registry are the intended integration path.

```bash
# Test via display-name helper
launch-pwa-by-name "{PWA Name}" 2>&1 &
sleep 3

# Verify window appeared
swaymsg -t get_tree | grep -q "WebApp-{ULID}" && echo "✓ PWA launched successfully!" || echo "✗ PWA did not launch"

# Optional: verify daemon-backed launch path too
i3pm launch preview "$APP_NAME" --json
```

## Success Criteria

Confirm all of these before marking as complete:

- ✅ Icon found/validated (colored, icon-only)
- ✅ PWA entry added to pwa-sites.nix
- ✅ Desktop entry exists at `~/.local/share/i3pm-applications/applications/{slug}-pwa.desktop`
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
| "PWA not appearing in Walker" | Desktop entry missing or rebuild not activated | Check `~/.local/share/i3pm-applications/applications/*.desktop` and rerun rebuild |
| "Service not running" | localhost service down | Start service |
| "Syntax error" | Invalid Nix syntax | Check brackets, semicolons, quotes |
| "Unknown host" | Hostname not in flake | Specify correct flake target |
| "Badge icon generation failed" | Missing rsvg-convert or magick | Install librsvg and imagemagick |
| "Source SVG not found" | Base icon missing for badge generation | Download base icon first, then run badge script |
| "Workspace conflict" | Workspace already assigned | Check allocation table; use next available in range |

## Files Modified/Created

### Modified:
- `shared/pwa-sites.nix` - Added new PWA entry/entries
- `assets/icons/{filename}` - New icon (if downloaded)

### Multi-environment additions:
- `assets/icons/{service}-{env}.png` - Badge icons (generated by `generate-env-icon.sh`)
- `scripts/generate-env-icon.sh` - Single icon badge generator
- `scripts/generate-all-env-icons.sh` - Batch icon generator (update ICON_MAP for new services)

### Auto-generated (during rebuild):
- `~/.local/share/i3pm-applications/applications/{slug}-pwa.desktop`
- `~/.config/i3/application-registry.json`
- `~/.config/i3/pwa-registry.json`

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
   - Via daemon-backed launch: `i3pm launch open {slug}-pwa`

3. **Next steps:**
   - Test the PWA by launching it
   - Consider committing changes to Git

## References

- PWA System Docs: `docs/PWA_SYSTEM.md`
- PWA Sites Config: `shared/pwa-sites.nix`
- App Registry Data: `home-modules/desktop/app-registry-data.nix`
- PWA Launcher: `home-modules/tools/pwa-launcher.nix`
- Icon Badge Generator: `scripts/generate-env-icon.sh`
- Batch Icon Generator: `scripts/generate-all-env-icons.sh`
- Icon Assets: `assets/icons/`
