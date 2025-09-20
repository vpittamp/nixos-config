# KDE Activity Management: Native vs Scripted Approaches

## Current Implementation (Scripted Approach)

### How It Works
- **Window Detection**: Uses `xdotool` and `xprop` to manually check window properties
- **Activity Assignment**: Scripts check `_KDE_NET_WM_ACTIVITIES` property per window
- **Instance Management**: Custom logic to detect if app is running in current activity
- **Launch Behavior**: Wrapper scripts intercept launches and manage windows

### Pros
- Full control over behavior
- Can implement complex logic
- Works reliably with explicit window manipulation

### Cons
- Requires external tools (xdotool, xprop)
- More code to maintain
- Potential race conditions with window detection
- Not integrated with KDE's native features

## Native KDE Approach (Recommended)

### Key Native Features

#### 1. **KWin Window Rules**
- Built into KDE's window manager
- Automatically assigns windows to activities based on properties
- No external scripts needed
- Configurable through System Settings or `kwinrulesrc`

Example rule structure:
```ini
[1]
Description=VS Code - NixOS Activity
wmclass=code
wmclassmatch=1  # Substring match
title=/etc/nixos
titlematch=1     # Substring match
activity=6ed332bc-fa61-5381-511d-4d5ba44a293b
activityrule=2   # Force assignment
```

#### 2. **Desktop Actions (Jumplist)**
- Native KDE/freedesktop.org standard
- Right-click menu on application icons
- Supported by launchers and task managers
- Clean integration with Plasma

Example desktop entry:
```ini
[Desktop Entry]
Actions=open-nixos;open-stacks;open-backstage;new-window;

[Desktop Action open-nixos]
Name=Open in NixOS
Exec=code /etc/nixos
Icon=folder-blue
```

#### 3. **D-Bus Activity Manager API**
- Official KDE API for activity management
- Real-time activity change notifications
- Programmatic control over activities
- Used by KDE applications internally

Key interfaces:
- `org.kde.ActivityManager` - Main service
- `/ActivityManager/Activities` - Activity operations
- `CurrentActivity` method - Get current activity
- `CurrentActivityChanged` signal - Monitor changes

#### 4. **Plasma Shortcuts Integration**
- Native support for activity switching
- Can bind shortcuts to specific activities
- Integrated with KRunner
- Works with global shortcuts system

### Implementation Comparison

| Feature | Scripted | Native KDE |
|---------|----------|------------|
| **Setup Complexity** | Medium - requires wrapper scripts | Low - uses existing KDE features |
| **Maintenance** | High - custom code | Low - standard KDE config |
| **Performance** | Slower - external process calls | Faster - integrated with KWin |
| **Reliability** | Good with race conditions | Excellent - native integration |
| **User Experience** | Custom behavior | Standard KDE behavior |
| **Right-click Actions** | Not available | Native jumplist support |
| **Window Rules** | Manual via scripts | Automatic via KWin |
| **Activity Detection** | Polling/checking | Event-driven |

## Recommended Hybrid Approach

Combine the best of both:

### 1. **Use KWin Window Rules**
- Let KWin automatically assign windows to activities
- Configure rules for VS Code, Konsole, Dolphin based on:
  - Window title (workspace path)
  - Working directory
  - Launch parameters

### 2. **Desktop Actions for Quick Access**
- Provide jumplist entries for each activity
- Users can right-click VS Code icon → "Open in Stacks"
- Clean, native integration

### 3. **Simple Launch Scripts**
- Minimal wrapper just to set working directory
- Let KWin rules handle activity assignment
- No complex window detection logic

### 4. **D-Bus Monitoring Service**
- Optional service to sync environment on activity changes
- Updates shell environment variables
- Provides activity context to applications

## Migration Path

1. **Keep existing scripts** for immediate functionality
2. **Add native desktop entries** with Actions
3. **Configure KWin rules** for automatic window assignment
4. **Test and validate** native approach
5. **Gradually remove** complex scripting logic

## Configuration Examples

### KWin Rules via NixOS
```nix
home.file.".config/kwinrulesrc".text = ''
  [General]
  count=3
  rules=1,2,3

  [1]
  Description=VS Code NixOS
  wmclass=code
  title=/etc/nixos
  activity=6ed332bc-fa61-5381-511d-4d5ba44a293b
  activityrule=2
'';
```

### Desktop Entry with Actions
```nix
xdg.desktopEntries.code-activities = {
  name = "VS Code";
  exec = "code";
  actions = {
    open-nixos = {
      name = "Open NixOS Config";
      exec = "code /etc/nixos";
    };
    open-stacks = {
      name = "Open Stacks";
      exec = "code ~/development/stacks";
    };
  };
};
```

### D-Bus Activity Monitoring
```bash
dbus-monitor --session "interface='org.kde.ActivityManager'" |
while read -r line; do
  if [[ "$line" == *"CurrentActivityChanged"* ]]; then
    # React to activity change
    update_environment
  fi
done
```

## Conclusion

While the scripted approach provides fine-grained control, KDE's native features offer:
- Better integration with Plasma desktop
- Lower maintenance burden
- Standard user experience
- Better performance

The native approach using KWin window rules, desktop actions, and D-Bus integration is more efficient and maintainable than manual window manipulation scripts.