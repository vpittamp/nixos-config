# Draft: upstream issue for NVIDIA/open-gpu-kernel-modules

Ready to file at <https://github.com/NVIDIA/open-gpu-kernel-modules/issues/new>.
Related public reports to cross-reference when filing: forum thread 346165
(same kmalloc-64 call chain on 580.65.06), forum thread 371770 (610.43.02
present-path leak, bug IDs 5352012/5556719), GitHub issue #1254 (unbounded
SUnreclaim growth on 610.43.03).

File with (the sed strips this preamble; everything below the `---` is the
issue body):

```bash
sed '1,/^---$/d' docs/nvidia-semsurf-leak-upstream-issue.md > /tmp/issue-body.md
gh issue create --repo NVIDIA/open-gpu-kernel-modules \
  --title "nvKmsKapiRegisterSemaphoreSurfaceCallback leaks its callback allocation on the NVOS_STATUS_ERROR_ALREADY_SIGNALLED path (unbounded kmalloc-64 SUnreclaim growth under Wayland explicit sync)" \
  --body-file /tmp/issue-body.md
```

---

## Summary

`nvKmsKapiRegisterSemaphoreSurfaceCallback()`
(`src/nvidia-modeset/kapi/src/nvkms-kapi-sync.c`) leaks its freshly allocated
`struct NvKmsKapiSemaphoreSurfaceCallback` every time the register-waiter RM
control returns `NVOS_STATUS_ERROR_ALREADY_SIGNALLED`. Under a Wayland
compositor using `linux-drm-syncobj-v1` explicit sync this path races
constantly (observed ~50 leaks/second on a desktop workload), growing
**unreclaimable** kmalloc-64 slab by hundreds of MiB per day until the host
livelocks. The leaked objects are unreachable from every teardown path, so
only a reboot recovers the memory.

The buggy code is byte-identical at tags 595.80, 595.84, and 610.43.03.

## Environment

- RTX 5070 (Blackwell), open kernel modules, driver 595.80
- Linux 6.18.35, NixOS, Sway/wlroots 0.20.1 (Wayland, explicit sync active)
- `nvidia-drm.modeset=1`

## Mechanism

1. `nv_drm_semsurf_fence_create_ioctl` → `__nv_drm_semsurf_ctx_reg_callbacks`
   calls `nvKmsKapiRegisterSemaphoreSurfaceCallback()`, which allocates `cb`
   (`nvKmsKapiCalloc`, 32-byte struct + 8-byte alloc header → kmalloc-64) and
   passes `&cb->rmCallback` as the notification handle of
   `NV_SEMAPHORE_SURFACE_CTRL_CMD_REGISTER_WAITER`.
2. In RM, `_semsurfAddWaiter()` (`src/nvidia/src/kernel/gpu/mem_mgr/sem_surf.c`)
   re-reads the semaphore value under its spinlock; if the GPU has already
   passed `wait_value` it returns `NV_ERR_ALREADY_SIGNALLED` **before**
   `registerEventNotification()` — the notification handle is never stored.
3. Back in `nvKmsKapiRegisterSemaphoreSurfaceCallback()`, the
   `NVOS_STATUS_ERROR_ALREADY_SIGNALLED` case returns **without freeing `cb`
   and without writing `*pCallbackHandle`** (595.80 lines 441–455 — contrast
   with the `fail:` label, which does `nvKmsKapiFree(cb)`):

   ```c
   switch (ret) {
   case NVOS_STATUS_SUCCESS:
       if (pCallback) {
           *pCallbackHandle = cb;
       }
       return NVKMS_KAPI_REG_WAITER_SUCCESS;
   case NVOS_STATUS_ERROR_ALREADY_SIGNALLED:
       return NVKMS_KAPI_REG_WAITER_ALREADY_SIGNALLED;   /* cb orphaned */
   default:
       break;
   }

   fail:
       nvKmsKapiFree(cb);
       return NVKMS_KAPI_REG_WAITER_FAILED;
   ```

4. The caller (`kernel-open/nvidia-drm/nvidia-drm-fence.c`,
   `__nv_drm_semsurf_ctx_reg_callbacks`) retries in a
   `do { … } while (ret == NVKMS_KAPI_REG_WAITER_ALREADY_SIGNALLED)` loop,
   allocating a fresh `cb` per iteration — one leaked object per iteration.
   `reg_callbacks` runs on every fence create, every callback fire, and every
   capped timeout, so any explicit-sync compositing workload hits the race
   continuously.

Because RM never stored the handle and the caller never received the pointer,
the object is referenced by nothing: fence signal, DRM fd close
(`__nv_drm_semsurf_fence_ctx_destroy` unregisters only the single *stored*
callback), `semsurfDestruct`, and even module unload cannot free it.

## Evidence

`slub_debug=U,kmalloc-*64` attribution on a 32 GiB workstation pinned 99.7 %
of leaked kmalloc-64 objects to this single call site:

```
__kmalloc_noprof
nvkms_alloc                               [nvidia_modeset]
nvKmsKapiRegisterSemaphoreSurfaceCallback [nvidia_modeset]
nv_drm_semsurf_fence_create_ioctl         [nvidia_drm]
```

One incident reached ~26 GiB SUnreclaim / ~323 M objects after 26 days of
uptime. Setting `__NV_DISABLE_EXPLICIT_SYNC=1` (so no semsurf fences are
created) stops the growth, consistent with other public reports
(fd-leak thread bug 5556719; 610.43.02 present-path leak thread referencing
bug 5352012, where the same variable eliminates growth).

## Fix

Free `cb` on the `ALREADY_SIGNALLED` path, mirroring the `fail:` label. Safe
by construction: on this status RM provably never retained the notification
handle and the caller never receives the pointer, so no double-free or
dangling reference is possible.

```diff
     case NVOS_STATUS_ERROR_ALREADY_SIGNALLED:
+        nvKmsKapiFree(cb);
         return NVKMS_KAPI_REG_WAITER_ALREADY_SIGNALLED;
```

We are running this one-liner locally (patch applied to the 595.80 open
modules); happy to submit it as a PR if that helps.
