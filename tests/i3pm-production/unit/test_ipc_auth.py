"""
Unit tests for IPC authentication

Feature 030: Production Readiness
Task T011: Authentication tests

Tests UID-based authentication via SO_PEERCRED.
"""

import pytest
import socket
import struct
import os
import tempfile
from pathlib import Path

from security.auth import (
    authenticate_client,
    AuthenticationError,
    get_peer_credentials,
    validate_socket_permissions,
)


# ============================================================================
# Peer Credentials Tests
# ============================================================================

@pytest.mark.skipif(
    os.name != 'posix',
    reason="SO_PEERCRED only available on POSIX systems"
)
def test_get_peer_credentials_from_socketpair():
    """Test get_peer_credentials with socketpair (simulated connection)"""
    # Create a connected socket pair
    client_sock, server_sock = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)

    try:
        # Get credentials from server side (viewing client)
        pid, uid, gid = get_peer_credentials(server_sock)

        # Should return current process credentials
        assert pid == os.getpid()
        assert uid == os.getuid()
        assert gid == os.getgid()

    finally:
        client_sock.close()
        server_sock.close()


# ============================================================================
# Authentication Tests
# ============================================================================

@pytest.mark.skipif(
    os.name != 'posix',
    reason="SO_PEERCRED only available on POSIX systems"
)
def test_authenticate_client_same_user():
    """Test authentication succeeds for same UID"""
    # Create connected socket pair (simulates client/server)
    client_sock, server_sock = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)

    try:
        # Should succeed because both sockets are in same process (same UID)
        result = authenticate_client(server_sock, allow_same_user_only=True)
        assert result is True

    finally:
        client_sock.close()
        server_sock.close()


@pytest.mark.skipif(
    os.name != 'posix' or os.getuid() == 0,
    reason="Test requires POSIX and non-root user"
)
def test_authenticate_client_different_user_simulation():
    """Test authentication logic (cannot actually simulate different UID)"""
    # Note: We cannot actually create a socket from different UID in tests
    # This test validates the error handling logic

    # Create socket pair
    client_sock, server_sock = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)

    try:
        # Monkeypatch get_peer_credentials to simulate different UID
        def fake_credentials(sock):
            return (12345, 99999, 99999)  # Fake PID, UID, GID

        import security.auth
        original_func = security.auth.get_peer_credentials
        security.auth.get_peer_credentials = fake_credentials

        # Should raise AuthenticationError due to UID mismatch
        with pytest.raises(AuthenticationError) as exc_info:
            authenticate_client(server_sock, allow_same_user_only=True)

        assert "UID mismatch" in str(exc_info.value)

        # Restore original function
        security.auth.get_peer_credentials = original_func

    finally:
        client_sock.close()
        server_sock.close()


# ============================================================================
# Socket Permissions Tests
# ============================================================================

def test_validate_socket_permissions_nonexistent():
    """Test validation fails for nonexistent socket"""
    with pytest.raises(AuthenticationError) as exc_info:
        validate_socket_permissions("/nonexistent/socket.sock")

    assert "not found" in str(exc_info.value)


def test_validate_socket_permissions_correct():
    """Test validation succeeds for correctly secured socket"""
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        socket_path = tmp.name

    try:
        # Set correct permissions (0600)
        os.chmod(socket_path, 0o600)

        # Should succeed
        result = validate_socket_permissions(socket_path)
        assert result is True

    finally:
        os.unlink(socket_path)


def test_validate_socket_permissions_too_permissive():
    """Test validation fails for overly permissive socket"""
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        socket_path = tmp.name

    try:
        # Set overly permissive permissions (0666)
        os.chmod(socket_path, 0o666)

        # Should fail
        with pytest.raises(AuthenticationError) as exc_info:
            validate_socket_permissions(socket_path)

        assert "too permissive" in str(exc_info.value)

    finally:
        os.unlink(socket_path)


def test_validate_socket_permissions_group_readable():
    """Test validation fails if group can read socket"""
    with tempfile.NamedTemporaryFile(delete=False) as tmp:
        socket_path = tmp.name

    try:
        # Set group-readable permissions (0640)
        os.chmod(socket_path, 0o640)

        # Should fail
        with pytest.raises(AuthenticationError) as exc_info:
            validate_socket_permissions(socket_path)

        assert "too permissive" in str(exc_info.value)

    finally:
        os.unlink(socket_path)


# ============================================================================
# Integration Tests
# ============================================================================

@pytest.mark.skipif(
    os.name != 'posix',
    reason="Unix domain sockets only available on POSIX"
)
def test_full_authentication_flow():
    """Test complete authentication flow with Unix socket"""
    with tempfile.TemporaryDirectory() as tmpdir:
        socket_path = os.path.join(tmpdir, "test.sock")

        # Create server socket
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(socket_path)
        server.listen(1)

        # Set correct permissions
        os.chmod(socket_path, 0o600)

        # Validate permissions
        assert validate_socket_permissions(socket_path) is True

        # Clean up
        server.close()
        os.unlink(socket_path)
