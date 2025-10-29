"""
Setup configuration for Sway Configuration Manager.

Feature 047: Dynamic Sway Configuration Management Architecture
"""

from setuptools import setup, find_packages
from pathlib import Path

# Read requirements
requirements_file = Path(__file__).parent / "requirements.txt"
requirements = requirements_file.read_text().strip().split("\n") if requirements_file.exists() else []

# Read long description from README if it exists
readme_file = Path(__file__).parent / "README.md"
long_description = readme_file.read_text() if readme_file.exists() else ""

setup(
    name="sway-config-manager",
    version="1.0.0",
    description="Dynamic configuration management system for Sway window manager",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="NixOS Configuration Team",
    author_email="",
    url="https://github.com/your-repo/nixos-config",  # Update with actual repo
    packages=find_packages(exclude=["tests", "tests.*"]),
    install_requires=requirements,
    python_requires=">=3.11",
    entry_points={
        "console_scripts": [
            "sway-config-daemon=daemon:main",
        ],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Programming Language :: Python :: 3.13",
    ],
    extras_require={
        "test": [
            "pytest>=7.0.0",
            "pytest-asyncio>=0.21.0",
            "pytest-cov>=4.0.0",
        ],
    },
)
