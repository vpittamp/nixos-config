"""Entry point for sway-config-manager daemon when run as a module."""

from .daemon import main
import asyncio

if __name__ == "__main__":
    asyncio.run(main())
