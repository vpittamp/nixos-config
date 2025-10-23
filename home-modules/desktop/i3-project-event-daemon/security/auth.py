"""
IPC Authentication Module

Feature 030: Production Readiness
Task T009: UID-based authentication via SO_PEERCRED

This module implements secure authentication for Unix domain socket IPC
using SO_PEERCRED to verify client UID matches daemon UID.

Reference: research.md Decision 6 (lines 315-350)
"""

import socket
import struct
import os
import logging
from typing import Tuple

logger = logging.getLogger(__name__)


class AuthenticationError(Exception):
    """Raised when IPC client authentication fails"""
    pass


def get_peer_credentials(sock: socket.socket) -> Tuple[int, int, int]:
    """
    Get peer process credentials from Unix domain socket

    Uses SO_PEERCRED socket option to retrieve PID, UID, and GID
    of the connecting process.

    Args:
        sock: Unix domain socket with connected peer

    Returns:
        Tuple of (pid, uid, gid)

    Raises:
        OSError: If SO_PEERCRED is not available (non-Linux platform)
        AuthenticationError: If credentials cannot be retrieved
    """
    try:
        # SO_PEERCRED returns struct ucred { pid_t pid; uid_t uid; gid_t gid; }
        # On Linux, these are typically 32-bit integers (3i format)
        creds_bytes = sock.getsockopt(
            socket.SOL_SOCKET,
            socket.SO_PEERCRED,
            struct.calcsize('3i')
        )
        pid, uid, gid = struct.unpack('3i', creds_bytes)
        return pid, uid, gid
    except OSError as e:
        raise AuthenticationError(f"Failed to retrieve peer credentials: {e}")


def authenticate_client(sock: socket.socket, allow_same_user_only: bool = True) -> bool:
    """
    Authenticate IPC client via UID verification

    This function implements security via UID matching:
    - Retrieves peer credentials using SO_PEERCRED
    - Compares peer UID against daemon UID
    - Optionally allows specific trusted UIDs (future enhancement)

    Security properties:
    - Enforced by kernel (SO_PEERCRED cannot be spoofed)
    - Only processes running as same user can connect
    - Prevents privilege escalation attacks
    - Socket file permissions (0600) provide additional layer

    Args:
        sock: Unix domain socket with connected client
        allow_same_user_only: If True, only accept connections from same UID

    Returns:
        True if authentication succeeds

    Raises:
        AuthenticationError: If authentication fails

    Example:
        >>> sock = accept_connection(server_socket)
        >>> try:
        ...     authenticate_client(sock)
        ...     # Process authenticated request
        ... except AuthenticationError as e:
        ...     logger.warning(f"Auth failed: {e}")
        ...     sock.close()
    """
    daemon_uid = os.getuid()
    daemon_gid = os.getgid()

    try:
        pid, uid, gid = get_peer_credentials(sock)
    except AuthenticationError as e:
        logger.warning(f"Failed to get peer credentials: {e}")
        raise

    # Log connection attempt
    logger.debug(
        f"IPC connection attempt: peer_uid={uid} peer_gid={gid} peer_pid={pid} "
        f"daemon_uid={daemon_uid} daemon_gid={daemon_gid}"
    )

    # Verify UID match
    if allow_same_user_only:
        if uid != daemon_uid:
            error_msg = (
                f"UID mismatch: client UID {uid} != daemon UID {daemon_uid} "
                f"(client PID {pid})"
            )
            logger.warning(f"Authentication failed: {error_msg}")
            raise AuthenticationError(error_msg)

    logger.debug(f"Authentication successful: client PID {pid} UID {uid}")
    return True


def validate_socket_permissions(socket_path: str) -> bool:
    """
    Validate Unix socket file has correct permissions (0600)

    This provides defense-in-depth: even if SO_PEERCRED fails,
    socket file permissions prevent unauthorized access.

    Args:
        socket_path: Path to Unix domain socket file

    Returns:
        True if permissions are correct (owner read/write only)

    Raises:
        AuthenticationError: If permissions are too permissive
    """
    import stat

    try:
        st = os.stat(socket_path)
        mode = stat.S_IMODE(st.st_mode)

        # Expected: 0600 (owner read/write, no group/other access)
        expected_mode = stat.S_IRUSR | stat.S_IWUSR  # 0600

        if mode != expected_mode:
            actual = oct(mode)
            expected = oct(expected_mode)
            raise AuthenticationError(
                f"Socket permissions too permissive: {actual} (expected {expected}). "
                f"Run: chmod 0600 {socket_path}"
            )

        # Also verify owner is current user
        if st.st_uid != os.getuid():
            raise AuthenticationError(
                f"Socket owned by UID {st.st_uid}, expected {os.getuid()}"
            )

        return True

    except FileNotFoundError:
        raise AuthenticationError(f"Socket file not found: {socket_path}")
    except OSError as e:
        raise AuthenticationError(f"Failed to check socket permissions: {e}")


# Future enhancement: Support for trusted UID allowlist
# This would enable system services or sudo commands to interact with daemon
TRUSTED_UIDS = set()  # type: set[int]


def add_trusted_uid(uid: int) -> None:
    """
    Add UID to trusted allowlist (future enhancement)

    This would allow specific system services or administrative
    commands to interact with the daemon even if running as different user.

    Args:
        uid: User ID to trust
    """
    TRUSTED_UIDS.add(uid)
    logger.info(f"Added trusted UID: {uid}")


def is_trusted_uid(uid: int) -> bool:
    """
    Check if UID is in trusted allowlist

    Args:
        uid: User ID to check

    Returns:
        True if UID is trusted
    """
    return uid in TRUSTED_UIDS
