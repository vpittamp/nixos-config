from setuptools import setup, find_packages

setup(
    name="i3pm-diagnostic",
    version="1.0.0",
    packages=find_packages(),
    install_requires=[
        "click",
        "rich",
        "pydantic",
    ],
    entry_points={
        "console_scripts": [
            "i3pm-diagnose=i3pm_diagnostic.__main__:cli",
        ],
    },
    python_requires=">=3.11",
)
