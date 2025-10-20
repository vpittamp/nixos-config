"""Make the daemon executable as a Python module.

Run with: python -m i3_project_daemon
"""

from .daemon import main

if __name__ == "__main__":
    main()
