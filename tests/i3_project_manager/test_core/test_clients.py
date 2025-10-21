"""Unit tests for daemon and i3 IPC clients."""

import asyncio
import json
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from i3_project_manager.core.daemon_client import (
    DaemonClient,
    DaemonConnectionPool,
    DaemonError,
    get_daemon_client,
)
from i3_project_manager.core.i3_client import I3Client, I3Error


class TestDaemonClient:
    """Tests for DaemonClient."""

    @pytest.mark.asyncio
    async def test_connect_success(self, tmp_path):
        """Test successful connection to daemon."""
        socket_path = tmp_path / "daemon.sock"

        with patch("asyncio.open_unix_connection") as mock_connect:
            mock_reader = AsyncMock()
            mock_writer = AsyncMock()
            mock_connect.return_value = (mock_reader, mock_writer)

            client = DaemonClient(socket_path=socket_path)
            await client.connect()

            assert client._reader is not None
            assert client._writer is not None
            mock_connect.assert_called_once()

    @pytest.mark.asyncio
    async def test_connect_timeout(self, tmp_path):
        """Test connection timeout."""
        socket_path = tmp_path / "daemon.sock"

        with patch("asyncio.open_unix_connection") as mock_connect:
            mock_connect.side_effect = asyncio.TimeoutError()

            client = DaemonClient(socket_path=socket_path, timeout=0.1)

            with pytest.raises(DaemonError, match="Connection timeout"):
                await client.connect()

    @pytest.mark.asyncio
    async def test_connect_socket_not_found(self, tmp_path):
        """Test connection when socket doesn't exist."""
        socket_path = tmp_path / "nonexistent.sock"

        client = DaemonClient(socket_path=socket_path)

        with pytest.raises(DaemonError, match="socket not found"):
            await client.connect()

    @pytest.mark.asyncio
    async def test_call_success(self, tmp_path):
        """Test successful RPC call."""
        socket_path = tmp_path / "daemon.sock"

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        # Mock response
        response = {
            "jsonrpc": "2.0",
            "result": {"daemon_connected": True, "active_project": "nixos"},
            "id": 1,
        }
        mock_reader.readline.return_value = (json.dumps(response) + "\n").encode()

        with patch("asyncio.open_unix_connection") as mock_connect:
            mock_connect.return_value = (mock_reader, mock_writer)

            client = DaemonClient(socket_path=socket_path)
            await client.connect()

            result = await client.call("get_status")

            assert result["daemon_connected"] is True
            assert result["active_project"] == "nixos"
            mock_writer.write.assert_called_once()

    @pytest.mark.asyncio
    async def test_call_daemon_error(self, tmp_path):
        """Test RPC call with daemon error response."""
        socket_path = tmp_path / "daemon.sock"

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        # Mock error response
        response = {
            "jsonrpc": "2.0",
            "error": {"code": -32600, "message": "Invalid request"},
            "id": 1,
        }
        mock_reader.readline.return_value = (json.dumps(response) + "\n").encode()

        with patch("asyncio.open_unix_connection") as mock_connect:
            mock_connect.return_value = (mock_reader, mock_writer)

            client = DaemonClient(socket_path=socket_path)
            await client.connect()

            with pytest.raises(DaemonError, match="Invalid request"):
                await client.call("invalid_method")

    @pytest.mark.asyncio
    async def test_call_timeout(self, tmp_path):
        """Test RPC call timeout."""
        socket_path = tmp_path / "daemon.sock"

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()
        mock_reader.readline.side_effect = asyncio.TimeoutError()

        with patch("asyncio.open_unix_connection") as mock_connect:
            mock_connect.return_value = (mock_reader, mock_writer)

            client = DaemonClient(socket_path=socket_path, timeout=0.1)
            await client.connect()

            with pytest.raises(DaemonError, match="Request timeout"):
                await client.call("get_status")

    @pytest.mark.asyncio
    async def test_get_status(self, mock_daemon_client):
        """Test get_status method."""
        status = await mock_daemon_client.get_status()

        assert status["daemon_connected"] is True
        assert "uptime_seconds" in status
        assert "active_project" in status

    @pytest.mark.asyncio
    async def test_get_active_project(self, mock_daemon_client):
        """Test get_active_project method."""
        project = await mock_daemon_client.get_active_project()
        assert project == "test-project"

    @pytest.mark.asyncio
    async def test_get_events(self, mock_daemon_client):
        """Test get_events method."""
        events = await mock_daemon_client.get_events(limit=10)

        assert "events" in events
        assert isinstance(events["events"], list)

    @pytest.mark.asyncio
    async def test_get_windows(self, mock_daemon_client):
        """Test get_windows method."""
        windows = await mock_daemon_client.get_windows()

        assert "windows" in windows
        assert isinstance(windows["windows"], list)

    @pytest.mark.asyncio
    async def test_ping_success(self, mock_daemon_client):
        """Test ping when daemon is alive."""
        result = await mock_daemon_client.ping()
        assert result is True

    @pytest.mark.asyncio
    async def test_ping_failure(self, tmp_path):
        """Test ping when daemon is dead."""
        socket_path = tmp_path / "nonexistent.sock"
        client = DaemonClient(socket_path=socket_path)

        result = await client.ping()
        assert result is False

    @pytest.mark.asyncio
    async def test_context_manager(self, tmp_path):
        """Test async context manager."""
        socket_path = tmp_path / "daemon.sock"

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        with patch("asyncio.open_unix_connection") as mock_connect:
            mock_connect.return_value = (mock_reader, mock_writer)

            async with DaemonClient(socket_path=socket_path) as client:
                assert client._reader is not None
                assert client._writer is not None

            # Verify close was called
            mock_writer.close.assert_called_once()


class TestDaemonConnectionPool:
    """Tests for DaemonConnectionPool."""

    @pytest.mark.asyncio
    async def test_get_client_creates_new(self, tmp_path):
        """Test getting client creates new connection."""
        socket_path = tmp_path / "daemon.sock"

        mock_reader = AsyncMock()
        mock_writer = AsyncMock()

        with patch("asyncio.open_unix_connection") as mock_connect:
            mock_connect.return_value = (mock_reader, mock_writer)

            pool = DaemonConnectionPool()
            # Monkey-patch socket path for test
            with patch.object(DaemonClient, "__init__", lambda self, **kwargs: (
                setattr(self, "socket_path", socket_path),
                setattr(self, "timeout", 5.0),
                setattr(self, "_reader", None),
                setattr(self, "_writer", None),
                setattr(self, "_request_id", 0),
            )):
                client = await pool.get_client()
                assert client is not None

    @pytest.mark.asyncio
    async def test_get_client_reuses_connection(self, mock_daemon_client):
        """Test getting client reuses existing connection."""
        pool = DaemonConnectionPool()
        pool._client = mock_daemon_client

        client = await pool.get_client()
        assert client is mock_daemon_client


class TestI3Client:
    """Tests for I3Client."""

    @pytest.mark.asyncio
    async def test_connect_success(self):
        """Test successful i3 connection."""
        with patch("i3ipc.aio.Connection") as mock_connection_class:
            mock_conn = AsyncMock()
            mock_connection_class.return_value.connect.return_value = mock_conn

            client = I3Client()
            await client.connect()

            assert client._connection is not None

    @pytest.mark.asyncio
    async def test_connect_failure(self):
        """Test i3 connection failure."""
        with patch("i3ipc.aio.Connection") as mock_connection_class:
            mock_connection_class.return_value.connect.side_effect = Exception(
                "Connection failed"
            )

            client = I3Client()

            with pytest.raises(I3Error, match="Failed to connect"):
                await client.connect()

    @pytest.mark.asyncio
    async def test_get_tree(self, mock_i3_connection):
        """Test get_tree method."""
        client = I3Client()
        client._connection = mock_i3_connection

        tree = await client.get_tree()

        assert tree is not None
        mock_i3_connection.get_tree.assert_called_once()

    @pytest.mark.asyncio
    async def test_get_workspaces(self, mock_i3_connection):
        """Test get_workspaces method."""
        client = I3Client()
        client._connection = mock_i3_connection

        workspaces = await client.get_workspaces()

        assert isinstance(workspaces, list)
        assert len(workspaces) > 0
        assert "num" in workspaces[0]
        assert "output" in workspaces[0]

    @pytest.mark.asyncio
    async def test_get_outputs(self, mock_i3_connection):
        """Test get_outputs method."""
        client = I3Client()
        client._connection = mock_i3_connection

        outputs = await client.get_outputs()

        assert isinstance(outputs, list)
        assert len(outputs) > 0
        assert "name" in outputs[0]
        assert "active" in outputs[0]

    @pytest.mark.asyncio
    async def test_get_marks(self, mock_i3_connection):
        """Test get_marks method."""
        client = I3Client()
        client._connection = mock_i3_connection

        marks = await client.get_marks()

        assert isinstance(marks, list)
        assert "project:test-project" in marks

    @pytest.mark.asyncio
    async def test_command(self, mock_i3_connection):
        """Test command method."""
        client = I3Client()
        client._connection = mock_i3_connection

        results = await client.command("workspace 1")

        assert isinstance(results, list)
        assert len(results) > 0
        assert results[0]["success"] is True

    @pytest.mark.asyncio
    async def test_get_windows_by_mark(self, mock_i3_connection):
        """Test get_windows_by_mark method."""
        client = I3Client()
        client._connection = mock_i3_connection

        windows = await client.get_windows_by_mark("project:test-project")

        assert isinstance(windows, list)
        assert len(windows) > 0
        assert "window_class" in windows[0]
        assert "marks" in windows[0]

    @pytest.mark.asyncio
    async def test_get_workspace_to_output_map(self, mock_i3_connection):
        """Test get_workspace_to_output_map method."""
        client = I3Client()
        client._connection = mock_i3_connection

        ws_map = await client.get_workspace_to_output_map()

        assert isinstance(ws_map, dict)
        assert 1 in ws_map
        assert ws_map[1] == "eDP-1"

    @pytest.mark.asyncio
    async def test_assign_logical_outputs(self, mock_i3_connection):
        """Test assign_logical_outputs method."""
        client = I3Client()
        client._connection = mock_i3_connection

        role_map = await client.assign_logical_outputs()

        assert isinstance(role_map, dict)
        assert "primary" in role_map
        assert role_map["primary"] == "eDP-1"

    @pytest.mark.asyncio
    async def test_focus_workspace(self, mock_i3_connection):
        """Test focus_workspace method."""
        client = I3Client()
        client._connection = mock_i3_connection

        result = await client.focus_workspace(2)

        assert result is True
        mock_i3_connection.command.assert_called()

    @pytest.mark.asyncio
    async def test_send_tick(self, mock_i3_connection):
        """Test send_tick method."""
        client = I3Client()
        client._connection = mock_i3_connection

        result = await client.send_tick("project:nixos")

        assert result is True
        mock_i3_connection.command.assert_called_with("nop project:nixos")

    @pytest.mark.asyncio
    async def test_context_manager(self):
        """Test async context manager."""
        with patch("i3ipc.aio.Connection") as mock_connection_class:
            mock_conn = AsyncMock()
            mock_connection_class.return_value.connect.return_value = mock_conn

            async with I3Client() as client:
                assert client._connection is not None
