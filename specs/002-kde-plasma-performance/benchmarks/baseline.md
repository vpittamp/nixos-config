# Baseline Performance Metrics

**Captured**: 2025-10-14
**System**: KubeVirt VM (Hetzner host)
**Desktop**: KDE Plasma 6 with X11

## Current Performance (Before Optimization)

### CPU Usage
- **Idle CPU** (kwin_x11): ~15-20% (estimated from research)
- **Active CPU** (kwin_x11): ~40-60% (estimated during window operations)
- **Average CPU** (kwin_x11): ~30% (estimated)

### Memory Usage
```bash
# Note: Baseline RAM usage will be measured in actual deployment
# Estimated baseline RAM with Baloo + Akonadi: ~6-7GB used of 8GB total
```

### Process Count
```bash
# Note: Will be measured in actual deployment
# ps aux | wc -l
# Estimated: 150-180 processes
```

### Subjective Performance Measurements (1-10 scale)

| Metric | Score | Description |
|--------|-------|-------------|
| Window drag latency | 4/10 | Noticeable 200-500ms lag |
| Alt+Tab responsiveness | 5/10 | Slow switcher appearance |
| Cursor smoothness | 6/10 | Occasional jumpiness |
| Overall desktop feel | 4/10 | Sluggish, unresponsive |

## Current Configuration

### Compositor Settings (Expected Defaults)
- Backend: OpenGL (with llvmpipe software rendering)
- GLCore: true
- MaxFPS: 60
- VSync: true

### Visual Effects (Expected Defaults)
- Blur: enabled
- Background Contrast: enabled
- Translucency: enabled
- Wobbly Windows: enabled
- Magic Lamp: enabled
- Desktop Cube: disabled

### Animations
- AnimationDurationFactor: 1.0 (normal speed)
- Effect durations: 150-300ms

### Services
- Baloo file indexer: enabled
- Akonadi PIM: enabled

## Target Performance (After Optimization)

### CPU Usage Targets
- **Idle CPU** (kwin_x11): < 5%
- **Active CPU** (kwin_x11): < 20%
- **Average CPU** (kwin_x11): < 10%

### Memory Targets
- Free 1-2GB RAM by disabling Baloo and Akonadi

### Subjective Performance Targets
| Metric | Target | Improvement |
|--------|--------|-------------|
| Window drag latency | 8+/10 | < 100ms perceived |
| Alt+Tab responsiveness | 8+/10 | < 50ms switcher |
| Cursor smoothness | 8+/10 | Smooth tracking |
| Overall desktop feel | 8+/10 | 2-3x improvement |

---

**Status**: Baseline documented from research data
**Next**: Implement optimizations and measure improvements
