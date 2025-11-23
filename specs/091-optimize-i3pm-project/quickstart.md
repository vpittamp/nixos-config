# Quickstart - Feature 091: Optimize i3pm Project Switching Performance

**Status**: Implementation Pending
**Target**: < 200ms average project switch time (96% improvement from 5.3s baseline)

## Validation Commands

### 1. Benchmark Project Switching Performance

```bash
# Run automated benchmark (10 iterations between two projects)
cd /home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project
./tests/091-optimize-i3pm-project/benchmarks/benchmark_project_switch.sh

# Expected output (after optimization):
# Iteration 1: 182ms
# Iteration 2: 195ms
# ...
# Average: 189ms (target: <200ms)
```

### 2. Check Daemon Performance Logs

```bash
# View real-time performance metrics
journalctl --user -u i3-project-event-listener -f | grep "Performance:"

# Example output:
# Performance: filter_windows_for_project took 142.35ms
# Performance: hide_windows_parallel took 38.12ms
# Performance: restore_windows_parallel took 95.84ms
```

### 3. Validate Zero Regression in Window Filtering

```bash
# Run regression test suite
cd /home/vpittamp/nixos-090-notification-callback-091-optimize-i3pm-project
pytest tests/091-optimize-i3pm-project/integration/test_window_filter.py -v

# All tests should pass (scoped/global window semantics preserved)
```

### 4. Test Feature 090 Integration

```bash
# Test notification callback with reduced sleep time
# After Feature 091 implementation, callback sleep reduced from 6s to 1s

# Trigger Claude Code notification
/etc/nixos/scripts/claude-hooks/stop-notification.sh

# Click "Return to Window" button - should complete in <1.5s total
# (1s sleep + <500ms for project switch)
```

## Performance Targets

| Scenario | Baseline (Before) | Target (After) | Improvement |
|----------|-------------------|----------------|-------------|
| 5 windows | 5.2s | <150ms | 97% |
| 10 windows | 5.3s | <180ms | 97% |
| 20 windows | 5.4s | <200ms | 96% |
| 40 windows | 5.6s | <300ms | 95% |

## Troubleshooting

### Performance Still Slow

**Check daemon logs for bottlenecks**:
```bash
journalctl --user -u i3-project-event-listener --since "5 minutes ago" | grep "Performance:"
```

**Look for**:
- Cache miss rate > 50% (indicates tree caching not working)
- Sequential command execution (indicates parallelization not active)
- High tree query count (should be 1-2 per switch, not 5-10)

### Window Filtering Regression

**Symptom**: Windows not showing/hiding correctly after optimization

**Debug**:
```bash
# Check window marks (scoped vs global)
swaymsg -t get_tree | jq '..|select(.type=="con")|select(.marks!=[])|{id:.id, class:.window_properties.class, marks:.marks}'

# Verify active project
echo $I3PM_PROJECT_NAME

# Check daemon state
i3pm daemon status
```

**Fix**: Revert to sequential implementation if parallel version has race conditions

## Key Metrics to Watch

1. **Average switch time**: Should be <200ms for 10-20 window projects
2. **P95 latency**: Should be <250ms (95th percentile)
3. **Standard deviation**: Should be <50ms (consistent performance)
4. **Tree cache hit rate**: Should be >80% (indicates effective caching)
5. **Parallel batch count**: Should be >1 (indicates parallelization active)

## Implementation Status

**Current State**: Planning phase complete
**Next Steps**:
1. Run `/speckit.tasks` to generate implementation tasks
2. Implement parallel command execution in `window_filter.py`
3. Add `CommandBatchService` and `TreeCacheService`
4. Run benchmarks to validate <200ms target
5. Reduce Feature 090 callback sleep from 6s to 1s

## Documentation

- **Spec**: [spec.md](./spec.md)
- **Plan**: [plan.md](./plan.md)
- **Research**: [research.md](./research.md)
- **Data Models**: [data-model.md](./data-model.md)
- **Internal APIs**: [contracts/](./contracts/)
