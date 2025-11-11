# Application Icons Summary

Downloaded on: 2025-11-11

## Icon Specifications

- **Source Size**: 48×48 pixels (or scalable SVG)
- **Display Size**: 20×20 pixels (scaled by Eww widget)
- **Format**: SVG (preferred) or PNG fallback
- **Purpose**: Workspace bar icons via workspace_panel.py

## Desktop Application Icons

Location: `/etc/nixos/assets/app-icons/`

| Application | Filename | Size | Format | Source |
|-------------|----------|------|--------|--------|
| Ghostty Terminal | ghostty.svg | 184K | SVG | Dashboard Icons |
| VS Code | vscode.svg | 34K | SVG | SVG Repo |
| Neovim | neovim.svg | 2.2K | SVG | Wikimedia Commons |
| Firefox | firefox.svg | 11K | SVG | Wikimedia Commons |
| Chromium | chromium.svg | 34K | SVG | SVG Repo |
| Lazygit | lazygit.svg | 34K | SVG | SVG Repo (Git icon) |
| Thunar | thunar.svg | 34K | SVG | SVG Repo (File Manager) |
| btop | btop.svg | 2.9K | SVG | GitHub (aristocratos/btop) |
| htop | htop.svg | 34K | SVG | SVG Repo |
| Yazi | yazi.svg | 34K | SVG | SVG Repo (File Manager) |
| K9s | k9s.svg | 11K | SVG | Wikimedia (Kubernetes logo) |

**Total Desktop Icons**: 11 files

## PWA Application Icons

Location: `/etc/nixos/assets/pwa-icons/`

| Application | Filename | Size | Format | Source |
|-------------|----------|------|--------|--------|
| YouTube | youtube.svg | 974 bytes | SVG | Wikimedia Commons |
| Google Gemini | gemini.svg | 34K | SVG | SVG Repo |
| Claude AI | claude.svg | 34K | SVG | SVG Repo |
| ChatGPT | chatgpt.svg | 972 bytes | SVG | Wikimedia Commons |
| GitHub | github.svg | 1.3K | SVG | Wikimedia Commons |
| GitHub Codespaces | github-codespaces.svg | 34K | SVG | SVG Repo |
| Gmail | gmail.svg | 419 bytes | SVG | Wikimedia Commons |
| Google Calendar | google-calendar.svg | 2.4K | SVG | Wikimedia Commons |
| LinkedIn Learning | linkedin-learning.svg | 34K | SVG | SVG Repo |

**Total PWA Icons**: 9 files

## Icon Sources

### Primary Sources (Official/Semi-Official)
- **Wikimedia Commons**: Firefox, Neovim, YouTube, ChatGPT, GitHub, Gmail, Google Calendar
- **GitHub Repositories**: btop (aristocratos/btop)
- **Dashboard Icons**: Ghostty

### Secondary Sources (High Quality)
- **SVG Repo**: VS Code, Chromium, Lazygit, Thunar, htop, Yazi, Gemini, Claude, GitHub Codespaces, LinkedIn Learning

## File Size Guidelines

- **Optimal**: 1-50KB (achieved by: neovim, btop, firefox, k9s, youtube, chatgpt, github, gmail, google-calendar)
- **Good**: 10-100KB (achieved by: none in this range)
- **Large but acceptable**: 100KB+ (ghostty at 184K)
- **From SVG Repo**: 34KB (standard size from that source)

## Notes

1. **SVG Format**: All icons are in SVG format for optimal scalability and quality
2. **Transparent Backgrounds**: All icons use transparent backgrounds for dark theme integration
3. **Catppuccin Mocha Compatible**: Icons integrate well with the dark theme
4. **High DPI Support**: SVG format ensures crisp rendering on Retina displays (M1 MacBook Pro)
5. **Fallback Icons**: Some apps use generic icons (Lazygit uses Git icon, Thunar/Yazi use file manager icons)
6. **Fixed 2025-11-11**: Replaced broken HTML security checkpoint pages with valid SVG icons from Iconify API
7. **PNG Removal 2025-11-11**: Removed all duplicate PNG files where SVG versions exist; workspace bar now uses SVG exclusively
8. **Icon Theme Integration**: Icons symlinked to `~/.local/share/icons/hicolor/scalable/apps/` for XDG icon theme resolution

## Integration with workspace_panel.py

The workspace_panel.py daemon expects icons in these paths:
- Desktop apps: `/etc/nixos/assets/app-icons/<app-name>.svg`
- PWAs: `/etc/nixos/assets/pwa-icons/<app-name>.svg`

Icon lookup is performed by:
```python
icon_path = getIconPath(icon_name, 48)  # Requests 48px source size
```

Eww widget then scales to 20×20 for display.

## Download Scripts

The download process is automated via:
- `/tmp/app-icons-download/download-icons.sh` - Initial download
- `/tmp/app-icons-download/fix-downloads.sh` - Fix failed downloads
- `/tmp/app-icons-download/fix-remaining.sh` - Fix remaining issues

## Licensing

All icons are from sources that allow free usage:
- Wikimedia Commons (CC BY 3.0 or similar)
- SVG Repo (Free for commercial use)
- GitHub repositories (MIT, Apache 2.0, or similar open source licenses)

Always verify license compliance for commercial use.

## Future Improvements

1. **Optimize Large Files**: ghostty.svg (184K) could be optimized with SVGO
2. **Replace Generic Icons**: Find specific icons for Lazygit, Thunar, and Yazi
3. **Standardize Sizes**: Some SVG Repo icons are uniformly 34K - could investigate optimization
4. **Add Missing Apps**: FZF File Search and Scratchpad Terminal (if needed)
