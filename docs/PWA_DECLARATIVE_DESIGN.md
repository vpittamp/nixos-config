# PWA Declarative Configuration Analysis

## Current Approach vs Fully Declarative

### Current Approach (Semi-Declarative)
```
User Action → firefoxpwa install → Generated ID → Map ID to Icon → Runtime Processing
```

**Problems:**
- PWA IDs are generated, not deterministic
- Manual PWA installation required
- Icons processed at runtime
- Two separate systems (firefoxpwa + our icons)

### Fully Declarative Approach
```
Nix Config → Build-time Processing → Desktop Files + Icons → Ready to Use
```

**Benefits:**
- Everything defined in Nix
- Icons processed at build time
- No runtime dependencies
- Reproducible across systems

## Icon Format Comparison

### PNG (Current)
- ❌ Multiple files needed (one per size)
- ❌ Lossy when scaled
- ❌ Larger repo size
- ✅ Universal support

### SVG (Recommended)
- ✅ Single file for all sizes
- ✅ Perfect scaling
- ✅ Smaller repo size
- ✅ Text-based (Git-friendly)
- ✅ Can be styled with CSS
- ❌ Slightly more complex for photos

### Symlinks
- ✅ No duplication
- ✅ Easy to update
- ❌ Still need source files
- ❌ Can break if source moves

## Three Levels of Declarative

### Level 1: Icon Mapping (Current)
```nix
# Maps existing PWAs to icons
"01K5SRD32G3CDN8FC5KM8HMQNP" = {
  name = "Google AI";
  iconFile = "./google-ai.png";
};
```

### Level 2: PWA Definition (Better)
```nix
# Defines PWAs by name, generates IDs
google-ai = {
  name = "Google AI";
  url = "https://google.com/search?udm=50";
  icon = ./google-ai.svg;
};
```

### Level 3: Full Integration (Best)
```nix
# PWAs as first-class Nix packages
programs.firefox-pwas = {
  google-ai = {
    name = "Google AI";
    url = "...";
    icon = ./google-ai.svg;
    shortcuts = true;  # Add to menu/taskbar
    profile = "work";  # Firefox profile
  };
};
```

## Recommendation

**Use Level 2 with SVG icons:**
1. Convert PNGs to SVGs where possible
2. Use the new `pwa-declarative.nix` module
3. Define PWAs by name, not ID
4. Let Nix handle all generation at build time

This gives you:
- True declarative configuration
- Version control for everything
- Reproducible builds
- No manual steps

## Migration Path

1. Keep current system working
2. Add new declarative module alongside
3. Gradually migrate PWAs
4. Remove old system when complete

## File Structure (Recommended)
```
/etc/nixos/
├── assets/
│   └── icons/
│       └── pwas/
│           ├── google-ai.svg     # SVG preferred
│           ├── argocd.svg
│           └── ...
└── modules/
    └── desktop/
        └── pwa-declarative.nix   # New module
```