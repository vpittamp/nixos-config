---
description: Find and download high-quality icon for a PWA site
---

You are helping the user find and download a high-quality icon (preferably SVG) for a Progressive Web App.

# Icon Finding Workflow

This command searches multiple sources to find the best icon for a PWA, prioritizing SVG format and high quality.

## Step 1: Parse Arguments and Gather Information

**Handle command arguments intelligently:**

If user invokes with arguments (e.g., `/find-pwa-icon find icon for GitHub at https://github.com`):
- Parse context from the invocation text
- Extract site name and URL using pattern matching:
  - Look for "icon for X" or "find X icon" → X is site name
  - Look for URLs starting with http/https → that's the site URL
  - Look for mentions of site names (GitHub, Notion, Discord, etc.)
- Skip redundant questions if both name and URL are found

If user invokes without clear arguments or information is missing:
- Ask explicitly for required fields below

### Icon Requirements (CRITICAL)

**Color**: Icon MUST be in full color (not monochrome, not black & white)
- PWA icons should be colorful and brand-recognizable
- Avoid single-color or grayscale logos
- Look for the official brand colors

**Icon-only**: Icon should NOT include text/wordmarks
- Look for "icon" or "mark" versions, not "logo" or "wordmark" versions
- Example: Discord icon (game controller shape) NOT "Discord" text logo
- Example: GitHub octocat icon only, NOT "GitHub" text with icon
- Some brands call this: "logomark", "icon", "symbol", "mark", "glyph"

### Required Information:

1. **Site Name** (required)
   - Example: "Notion", "Discord", "GitHub", "Home Assistant"
   - Used for searching logo databases
   - **If mentioned in invocation**, extract and use it

2. **Site URL** (required)
   - Example: "https://www.notion.so", "http://localhost:8123"
   - Used for extracting icons from the website itself
   - **If mentioned in invocation or previous conversation**, extract and use it

3. **Output Filename** (optional)
   - Default: lowercase site name with hyphens (e.g., "notion.svg")
   - Example: "home-assistant.svg"

## Step 2: Extract Icons from Website (Primary Method - Chrome DevTools MCP)

Use **chrome-devtools MCP** to navigate to the website and extract high-quality icons directly from the page.

**Why chrome-devtools MCP?**
- Renders JavaScript (gets dynamically loaded icons)
- Can take screenshots of rendered icons
- Extracts from manifest.json, meta tags, and DOM
- Finds icons that static HTML parsing misses

**Steps:**

### 2.1: Navigate and Extract Icon URLs

Use the `mcp__chrome-devtools` tool to navigate to the URL and execute JavaScript to find all icon references:

**Tool**: `mcp__chrome-devtools`
**Action**: Navigate to URL and extract icons

**JavaScript to execute** (extracts all icon URLs):
```javascript
// Extract all icon URLs from the page
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

// 3. Open Graph image
const ogImage = document.querySelector('meta[property="og:image"]');
if (ogImage) {
  icons.push({
    url: new URL(ogImage.content, window.location.href).href,
    sizes: 'unknown',
    type: 'image/png',
    source: 'og-image'
  });
}

// 4. Manifest icons (best source - often has multiple sizes and SVG)
const manifestLink = document.querySelector('link[rel="manifest"]');
if (manifestLink) {
  const manifestUrl = new URL(manifestLink.href, window.location.href).href;
  icons.push({
    manifestUrl: manifestUrl,
    source: 'manifest-link'
  });
}

// Return results
JSON.stringify(icons, null, 2);
```

### 2.2: Fetch Manifest Icons (if manifest found)

If a manifest URL was found in Step 2.1, fetch it and extract icon URLs:

```bash
# Download manifest.json
curl -s "{manifest_url}" -o /tmp/manifest.json

# Extract icon URLs from manifest
cat /tmp/manifest.json | jq -r '.icons[]? | "\(.src) \(.sizes) \(.type)"'
```

Manifest icons often include:
- Multiple sizes (192x192, 512x512, etc.)
- SVG versions (scalable, perfect quality)
- Purpose-specific icons (maskable, any)

### 2.3: Prioritize and Select Best Icon

**Priority by quality:**
1. **SVG from manifest** - Vector, scalable, perfect quality
2. **Large PNG from manifest (512x512+)** - High quality, often colored
3. **Apple touch icon** - Usually 180x180+, colored, icon-only
4. **Large favicon (256x256+)** - If SVG or large PNG
5. **Open Graph image** - Social preview, check if icon-only
6. **Standard favicon** - Last resort (often 16x16 or 32x32)

**Selection criteria:**
- Must be colored (avoid monochrome)
- Prefer icon-only (no text/wordmarks)
- Larger is better (512x512+ ideal)
- SVG > PNG > JPEG

### 2.4: Download Selected Icon

Once you've identified the best icon URL:

```bash
# Download with curl (follows redirects)
curl -L -o "/tmp/{filename}" "{icon_url}"

# Verify download succeeded
ls -lh "/tmp/{filename}"
```

### 2.5: Alternative - Screenshot Icon Element

If no suitable icon URL found, use chrome-devtools to screenshot a visible icon element:

**Tool**: `mcp__chrome-devtools`
**Action**: Take screenshot of icon element

Look for selectors like:
- `img[class*="logo"]`
- `svg[class*="icon"]`
- `.navbar img`, `.header img`
- `[aria-label*="logo"]`

Then screenshot that element and save as PNG.

### 2.6: Fallback to Logo Databases

**If chrome-devtools fails or finds no suitable icons**, proceed to Step 3 (logo databases)

## Step 3: Search Logo Databases (Fallback Method)

If chrome-devtools extraction fails or finds only low-quality icons, search specialized logo databases.

**IMPORTANT**: Look for COLORED, icon-only versions (no text/wordmarks).

### A. SVG Repo (Best for variety and colored icons)
```bash
# Search SVG Repo
# Manual search required - use WebSearch or WebFetch
```

**Site:** https://www.svgrepo.com/
**Search URL:** `https://www.svgrepo.com/vectors/{search-term}/`
**License:** Various (check individual icons)
**Quality:** High variety, many commercial-friendly

Use WebSearch or WebFetch:
```bash
# Search for icon
WebSearch: "{site_name} logo svg svgrepo"
# Then visit top result and download SVG
```

### B. Devicon (Best for developer tools - COLORED versions available)
```bash
# Search Devicon for tech logos (use -original for colored version)
curl -s "https://raw.githubusercontent.com/devicons/devicon/master/icons/{normalized-name}/{normalized-name}-original.svg" \
  -o "/tmp/{filename}"

# Normalized name examples:
# "GitHub" → "github"
# "Docker" → "docker"
# "Python" → "python"

# IMPORTANT: Use "-original" suffix for colored icons
# Avoid "-plain" (monochrome) or "-line" (outline only)
```

**Site:** https://devicon.dev/
**License:** MIT
**Quality:** Excellent for developer tools
**Icon Variants:**
- `-original.svg` - COLORED, full-color brand icon (PREFERRED)
- `-plain.svg` - Monochrome (AVOID for PWAs)
- `-line.svg` - Outline only (AVOID for PWAs)

### C. Brand Resource Sites (For specific brands)

Many companies provide official brand assets:
- Google Fonts Material Symbols (colored variants available)
- Company press kits / brand assets pages
- Use WebSearch: "{company name} brand assets" or "{company name} press kit"

**Look for**: "Icon", "Mark", "Symbol", "Logomark" (NOT "Logo" or "Wordmark")
**Prefer**: SVG format, colored/full-color versions

## Step 4: Validate Downloaded Icon

Check if the downloaded file is valid:

```bash
# Check file exists and has content
ls -lh "/tmp/{filename}"

# Check if it's a valid SVG (should contain <svg tag)
if [[ "{filename}" == *.svg ]]; then
  grep -q "<svg" "/tmp/{filename}" || echo "WARNING: Not a valid SVG"
fi

# Check if it's a valid PNG/JPEG
if [[ "{filename}" == *.png ]] || [[ "{filename}" == *.jpg ]] || [[ "{filename}" == *.jpeg ]]; then
  file "/tmp/{filename}" | grep -qE "(PNG|JPEG)" || echo "WARNING: Not a valid image"
fi

# Optional: Convert PNG/JPEG to SVG using ImageMagick (if installed)
# convert "/tmp/{filename}.png" "/tmp/{filename}.svg"
```

## Step 5: Move Icon to Assets Directory

```bash
# Create icons directory if it doesn't exist
mkdir -p /etc/nixos/assets/icons

# Move downloaded icon
mv "/tmp/{filename}" "/etc/nixos/assets/icons/{filename}"

# Verify final location
ls -lh "/etc/nixos/assets/icons/{filename}"
```

## Step 6: Return Icon Path

Provide the user with:

1. **Icon path for pwa-sites.nix:**
   ```nix
   icon = "/etc/nixos/assets/icons/{filename}";
   ```

2. **Source information:**
   - Where icon was found (website, Simple Icons, SVG Repo, etc.)
   - Format (SVG, PNG, JPEG)
   - Size/dimensions (if available)

3. **Quality assessment:**
   - ✅ SVG (vector, perfect)
   - ✅ PNG/JPEG 512x512+ (good)
   - ⚠️ PNG/JPEG <512x512 (acceptable but may look blurry)

## Priority Order for Icon Sources

Try in this order, stop when high-quality COLORED, icon-only image is found:

1. **Website manifest.json** (via chrome-devtools MCP - PRIMARY)
   - Usually highest quality, site-specific
   - Often includes SVG or large PNG (512x512+)
   - Look for icon-only versions (not wordmarks)
   - Often includes full-color brand icons
   - Chrome-devtools can extract from JavaScript-rendered manifests

2. **Apple touch icon** (via chrome-devtools MCP)
   - High quality, typically 180x180 or larger
   - Designed for mobile, usually colored
   - Generally icon-only (no text)
   - Extracted directly from DOM via JavaScript

3. **Screenshot icon element** (via chrome-devtools MCP)
   - Take screenshot of visible logo/icon on page
   - Useful when icon URLs not directly available
   - Can capture rendered SVG or canvas elements
   - Ensure you're capturing icon-only (not wordmark)

4. **Devicon** (if developer tool/language/technology - FALLBACK)
   - High quality COLORED SVG for tech logos
   - Use `-original.svg` variant for full-color
   - MIT licensed, official brand colors
   - Icon-only versions available

5. **Open Graph image** (via chrome-devtools MCP)
   - Social media preview image
   - Usually high resolution
   - May include wordmarks (check carefully)

6. **SVG Repo** (manual search via WebSearch - FALLBACK)
   - Large variety, many colored options
   - Search for: "{brand name} icon colored svg"
   - Filter for icon-only, avoid wordmarks
   - Check individual icon license

7. **Brand Resource Sites** (official press kits - FALLBACK)
   - Official brand assets from company
   - Look for "icon", "mark", "symbol" downloads
   - Usually highest quality and legally safe
   - Full brand colors guaranteed

8. **Website favicon** (via chrome-devtools MCP, last resort)
   - Often low quality (16x16, 32x32)
   - May be monochrome or low-res
   - Consider upscaling or finding alternative

## Example Execution

### Example 1: Developer Tool Icon (GitHub)

```bash
# User input:
# Name: "GitHub"
# URL: "https://github.com"
# Filename: "github.svg"

# Try Devicon first (GitHub is a developer tool)
# Use -original.svg for COLORED version
curl -s "https://raw.githubusercontent.com/devicons/devicon/master/icons/github/github-original.svg" \
  -o "/tmp/github.svg"

# Success! Validate
grep -q "<svg" "/tmp/github.svg"  # ✓ Valid SVG
# Check if colored (should contain multiple colors/fills)
grep -q 'fill="#' "/tmp/github.svg" || echo "WARNING: May be monochrome"

# Move to assets
mv "/tmp/github.svg" "/etc/nixos/assets/icons/github.svg"

# Result:
# icon = "/etc/nixos/assets/icons/github.svg";
# Source: Devicon (MIT) - colored original variant
# Format: SVG (vector)
# Quality: ✅ Excellent - Full color, icon-only
```

### Example 2: Custom Web App Icon (via chrome-devtools MCP)

```bash
# User input:
# Name: "Notion"
# URL: "https://www.notion.so"
# Filename: "notion.png"

# Step 1: Use chrome-devtools MCP to navigate and extract icons
# Tool: mcp__chrome-devtools
# Action: Navigate to https://www.notion.so and execute JavaScript to find icons
#
# JavaScript execution finds:
# - Apple touch icon: https://www.notion.so/images/logo-ios.png (180x180)
# - Manifest: https://www.notion.so/manifest.json
#
# Step 2: Fetch manifest for additional sizes
curl -s "https://www.notion.so/manifest.json" | jq '.icons'
# Found: 192x192 and 512x512 PNG icons in manifest

# Step 3: Download best icon (512x512 from manifest)
curl -L -o "/tmp/notion.png" "https://www.notion.so/images/logo-512.png"

# Validate
file "/tmp/notion.png"  # ✓ PNG image data, 512 x 512
ls -lh "/tmp/notion.png"  # Check file size (should be >50KB for quality)

# Move to assets
mv "/tmp/notion.png" "/etc/nixos/assets/icons/notion.png"

# Result:
# icon = "/etc/nixos/assets/icons/notion.png";
# Source: Notion website (manifest icon via chrome-devtools MCP)
# Format: PNG
# Size: 512x512
# Quality: ✅ Excellent - High resolution, colored, icon-only
```

### Example 3: Screenshot Method (when icon URLs not available)

```bash
# User input:
# Name: "Custom App"
# URL: "https://example.com"
# Filename: "custom-app.png"

# Step 1: Use chrome-devtools MCP to navigate
# Tool: mcp__chrome-devtools
# Action: Navigate to https://example.com

# Step 2: Find icon element selector
# Use chrome-devtools to inspect page and find:
# Selector: ".header-logo img" or "svg.brand-icon"

# Step 3: Screenshot the icon element
# Tool: mcp__chrome-devtools
# Action: Take screenshot of selector ".header-logo img"
# Save to: /tmp/custom-app.png

# Validate
file "/tmp/custom-app.png"  # ✓ PNG image data
# Check if it's colored and icon-only (not wordmark)

# Move to assets
mv "/tmp/custom-app.png" "/etc/nixos/assets/icons/custom-app.png"

# Result:
# icon = "/etc/nixos/assets/icons/custom-app.png";
# Source: Screenshot from website via chrome-devtools MCP
# Format: PNG
# Quality: ✅ Depends on screenshot resolution
```

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| "Icon URL not found" | Website has no icons | Try logo databases manually |
| "Download failed" | Network error or invalid URL | Check URL, try again |
| "Not a valid image" | Downloaded HTML instead of image | Check URL, may need authentication |
| "File too small" | Low-quality icon (<16KB) | Try different source or upscale |
| "SVG has no content" | Empty or invalid SVG | Try PNG/JPEG or different source |

## Tips for Finding Icons

1. **Search for icon-only, not wordmarks:**
   - Use search terms: "{brand} icon", "{brand} mark", "{brand} symbol"
   - Avoid: "{brand} logo" (often includes text)
   - Look for "logomark" or "brandmark" in brand assets
   - Example: Discord's game controller icon (icon-only) vs "Discord" text logo

2. **Ensure icons are colored:**
   - Check SVG file for multiple `fill=` attributes with different colors
   - Avoid monochrome/single-color icons (common in icon packs)
   - Look for "colored", "full-color", or "original" variants
   - For Devicon: use `-original.svg` NOT `-plain.svg`

3. **Check multiple sizes from website:**
   - Manifest icons often have multiple sizes
   - Apple touch icons are usually high quality (180x180+)
   - Prefer larger sizes for better quality (512x512+ ideal)
   - Icon-only versions often labeled as "app icon" or "touch icon"

4. **Verify licensing:**
   - Devicon: MIT (attribution recommended but not required)
   - SVG Repo: Check individual icon license (varies)
   - Website icons: Generally fair use for personal PWA
   - Brand assets: Check brand guidelines (usually allow for PWA use)

5. **Prefer SVG over PNG/JPEG:**
   - Scalable to any size without quality loss
   - Smaller file size
   - Better for icons at different display scales
   - Ensure SVG is colored (not just outline)

## Integration with /add-pwa

This command can be called from `/add-pwa` when:
- User doesn't provide icon path
- Provided icon path doesn't exist
- User wants to update/replace existing icon

The workflow seamlessly integrates icon finding into the PWA creation process.

## Summary Output

After completion, provide:

```
✅ Icon found and saved!

Path: /etc/nixos/assets/icons/{filename}
Source: {source_name}
Format: {SVG/PNG/JPEG}
Size: {dimensions}
Quality: {assessment}

Use in pwa-sites.nix:
icon = "/etc/nixos/assets/icons/{filename}";

Next steps:
- Add to pwa-sites.nix configuration
- Or use /add-pwa to create complete PWA entry
```

## References

- **chrome-devtools MCP**: Primary tool for extracting icons from websites (navigates, executes JavaScript, takes screenshots)
- **SVG Repo**: https://www.svgrepo.com/ (Variety of colored icons, various licenses)
- **Devicon**: https://devicon.dev/ (Developer tool icons, MIT license, use `-original.svg` for colored)
- **Brand Guidelines**: Search "{company name} brand assets" or "{company name} press kit" for official icons

## MCP Tool Usage

The `mcp__chrome-devtools` tool is available and configured in your environment. Use it to:
- Navigate to URLs and render JavaScript
- Execute JavaScript on pages to extract icon URLs
- Take screenshots of specific elements
- Access manifest.json and other resources

This is more powerful than static HTML parsing because it can:
- Handle JavaScript-rendered content
- Extract from dynamically loaded resources
- Screenshot SVG/canvas elements that aren't downloadable URLs
- Navigate authentication flows if needed

## Important Reminders

**Color Requirement**: PWA icons MUST be in full color (not monochrome)
- Colored icons are more recognizable and match brand identity
- Avoid icon packs that only offer single-color/outline versions
- Check SVG files for multiple color fills

**Icon-Only Requirement**: NO text/wordmarks
- Look for "icon", "mark", "symbol", "logomark" versions
- Avoid full logos that include company name text
- Icon-only versions are cleaner and work better at small sizes
