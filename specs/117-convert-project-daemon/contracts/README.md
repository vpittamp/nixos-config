# Contracts: Convert i3pm Project Daemon to User-Level Service

**Feature**: 117-convert-project-daemon
**Date**: 2025-12-14

## No API Changes

This feature does not introduce new APIs or modify existing IPC protocols. The daemon's JSON-RPC 2.0 interface over Unix socket remains unchanged.

## Socket Path Contract

The only contract change is the socket file location:

### Socket Path Resolution

Clients MUST implement the following socket resolution order:

1. **User socket** (primary): `$XDG_RUNTIME_DIR/i3-project-daemon/ipc.sock`
2. **System socket** (fallback): `/run/i3-project-daemon/ipc.sock`

### Environment Variables

| Variable | Requirement | Description |
|----------|-------------|-------------|
| `XDG_RUNTIME_DIR` | SHOULD be set | User runtime directory (typically `/run/user/{uid}`) |

### Fallback Behavior

```
IF user_socket exists:
    RETURN user_socket
ELSE IF system_socket exists:
    RETURN system_socket
ELSE:
    RETURN user_socket (for error message clarity)
```

## IPC Protocol (Unchanged)

The JSON-RPC 2.0 protocol over the Unix socket is unchanged:

- **Request format**: `{"jsonrpc":"2.0","method":"<method>","params":{...},"id":<int>}`
- **Response format**: `{"jsonrpc":"2.0","result":{...},"id":<int>}` or `{"jsonrpc":"2.0","error":{...},"id":<int>}`
- **Delimiter**: Newline (`\n`)

See existing daemon documentation for full method listing.
