# Configuration Contracts

This directory contains contract specifications for all configuration interfaces used in the KDE Plasma performance optimization feature.

## Purpose

Contracts define the **interface** between modules and configuration, documenting:
- Option names and types
- Valid value ranges
- Default values and recommendations
- Validation rules
- Dependencies and relationships

## Contract Files

### `compositor-config.nix`
**Entity**: CompositorConfig
**Module**: `home-modules/desktop/plasma-config.nix`
**Purpose**: KDE KWin compositor rendering settings

**Key Options**:
- `backend`: Rendering backend (OpenGL vs XRender)
- `maxFPS`: Frame rate limit
- `vSync`: Vertical synchronization toggle
- `glCore`: OpenGL core profile usage

### `effects-config.nix`
**Entity**: EffectsConfig
**Module**: `home-modules/desktop/plasma-config.nix`
**Purpose**: KDE visual effects configuration

**Key Options**:
- `blur`: Blur effect behind windows
- `backgroundContrast`: Background contrast effect
- `translucency`: Window translucency
- `wobblyWindows`: Wobbly window animation
- `magicLamp`: Magic lamp minimize animation
- `desktopCube`: Desktop cube effect

### `service-config.nix`
**Entity**: ServiceConfig
**Module**: `modules/services/kde-optimization.nix` (to be created)
**Purpose**: KDE background service management

**Key Options**:
- `baloo.disable`: Disable Baloo file indexer
- `akonadi.disable`: Disable Akonadi PIM services
- `kdeConnect.disable`: Disable KDE Connect

### `kubevirt-vm-spec.yaml`
**Entity**: VMResourceSpec
**Configuration**: KubeVirt VirtualMachine YAML
**Purpose**: VM compute and I/O resource allocation

**Key Fields**:
- `cpu.cores`: vCPU count (recommendation: 8)
- `cpu.dedicatedCpuPlacement`: Exclusive CPU assignment
- `memory.guest`: RAM allocation (recommendation: 16Gi)
- `ioThreadsPolicy`: Disk I/O threading strategy

## Usage in Implementation

These contracts serve as **reference specifications** during implementation:

1. **Phase 1 (Design)**: Contracts define the interface before implementation
2. **Phase 2-5 (Implementation)**: Modules implement these contracts
3. **Phase 6 (Testing)**: Validation tests verify contract compliance

## Contract Validation

Each contract includes validation rules:

```nix
# Example from compositor-config.nix
validate = config:
  assert lib.assertMsg
    (config.compositor.backend == "XRender" -> config.compositor.glCore == false)
    "glCore must be false when using XRender backend";
  config;
```

Validation rules ensure:
- Type safety (correct types for all options)
- Value constraints (ranges, enums respected)
- Cross-field dependencies (related options consistent)
- Performance requirements (settings meet targets)

## Integration with Data Model

Contracts correspond to entities defined in `../data-model.md`:

| Contract | Data Model Entity | Implementation Module |
|----------|-------------------|----------------------|
| compositor-config.nix | CompositorConfig | home-modules/desktop/plasma-config.nix |
| effects-config.nix | EffectsConfig | home-modules/desktop/plasma-config.nix |
| service-config.nix | ServiceConfig | modules/services/kde-optimization.nix |
| kubevirt-vm-spec.yaml | VMResourceSpec | KubeVirt YAML (external) |

## Extending Contracts

To add new configuration options:

1. Update the relevant contract file with new option
2. Add validation rules for the new option
3. Update data-model.md to document the new attribute
4. Implement the option in the corresponding module
5. Add tests to verify the option works correctly

## References

- **Data Model**: `../data-model.md` - Entity definitions and relationships
- **Research**: `../research.md` - Performance findings and rationale
- **Plan**: `../plan.md` - Implementation phases and timeline

---

**Last Updated**: 2025-10-14
**Status**: Phase 1 Complete
