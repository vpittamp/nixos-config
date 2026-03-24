"""Async subprocess utility to avoid blocking the event loop.

Wraps asyncio.create_subprocess_exec() with timeout and cleanup,
returning subprocess.CompletedProcess for drop-in compatibility.
"""

import asyncio
import subprocess
from typing import Optional


async def run_command(
    *args: str,
    cwd: Optional[str] = None,
    timeout: float = 30.0,
    check: bool = False,
) -> subprocess.CompletedProcess:
    """Run a command asynchronously without blocking the event loop.

    Args:
        *args: Command and arguments.
        cwd: Working directory.
        timeout: Timeout in seconds.
        check: If True, raise CalledProcessError on non-zero exit.

    Returns:
        subprocess.CompletedProcess with stdout/stderr as strings.

    Raises:
        subprocess.TimeoutExpired: If the command exceeds the timeout.
        subprocess.CalledProcessError: If check=True and returncode != 0.
    """
    proc = await asyncio.create_subprocess_exec(
        *args,
        cwd=cwd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout_bytes, stderr_bytes = await asyncio.wait_for(
            proc.communicate(),
            timeout=timeout,
        )
    except asyncio.TimeoutError:
        proc.kill()
        await proc.communicate()
        raise subprocess.TimeoutExpired(
            cmd=list(args),
            timeout=timeout,
        )

    stdout = stdout_bytes.decode("utf-8", errors="replace") if stdout_bytes else ""
    stderr = stderr_bytes.decode("utf-8", errors="replace") if stderr_bytes else ""

    result = subprocess.CompletedProcess(
        args=list(args),
        returncode=proc.returncode or 0,
        stdout=stdout,
        stderr=stderr,
    )

    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(
            returncode=result.returncode,
            cmd=list(args),
            output=stdout,
            stderr=stderr,
        )

    return result
