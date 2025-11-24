"""
Application Registry Nix File Editor Service

Feature 094: Enhanced Projects & Applications CRUD Interface
Text-based manipulation of app-registry-data.nix per research.md findings
"""

import re
import shutil
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional

from ..models.app_config import ApplicationConfig, PWAConfig, TerminalAppConfig


class AppRegistryEditor:
    """Service for editing app-registry-data.nix using text-based manipulation"""

    def __init__(self, nix_file: Optional[Path] = None):
        """
        Initialize app registry editor

        Args:
            nix_file: Path to app-registry-data.nix (default: home-modules/desktop/app-registry-data.nix)
        """
        self.nix_file = nix_file or Path("/etc/nixos/home-modules/desktop/app-registry-data.nix")

    def add_application(self, config: ApplicationConfig) -> Dict[str, Any]:
        """
        Add new application to Nix registry

        Args:
            config: Validated ApplicationConfig/PWAConfig model

        Returns:
            Result dict with status and rebuild requirement

        Raises:
            ValueError: If app already exists or Nix syntax invalid
        """
        with open(self.nix_file, 'r') as f:
            content = f.read()

        # Check if app already exists
        if self._app_exists(content, config.name):
            raise ValueError(f"Application '{config.name}' already exists in registry")

        # Generate ULID for PWAs
        ulid = None
        if isinstance(config, PWAConfig):
            ulid = self._generate_ulid()
            # Update config with generated ULID if not provided
            if not config.ulid:
                config.ulid = ulid

        # Generate mkApp entry
        new_entry = self._generate_mkapp_entry(config)

        # Find insertion point: before "] # Auto-generate PWA entries" or similar
        insertion_pattern = r'(\s+\])\s*(#.*PWA|$)'

        modified = re.sub(
            insertion_pattern,
            f'\n{new_entry}\n\\1\\2',
            content,
            count=1,
            flags=re.MULTILINE
        )

        # Write with backup and validation
        self._write_with_backup(modified)

        return {
            "status": "success",
            "ulid": ulid,
            "rebuild_required": True,
            "app_name": config.name
        }

    def edit_application(self, name: str, updates: Dict[str, Any]) -> Dict[str, Any]:
        """
        Edit existing application entry

        Args:
            name: Application name
            updates: Dict of fields to update

        Returns:
            Result dict with status and rebuild requirement

        Raises:
            ValueError: If app not found or Nix syntax invalid
        """
        with open(self.nix_file, 'r') as f:
            content = f.read()

        # Find the mkApp block for this application
        pattern = rf'\(mkApp \{{\s+name = "{re.escape(name)}";[^}}]+\}}[^)]*\)'

        match = re.search(pattern, content, re.MULTILINE | re.DOTALL)
        if not match:
            raise ValueError(f"Application '{name}' not found in registry")

        # Parse existing fields
        old_block = match.group(0)
        fields = self._parse_mkapp_fields(old_block)

        # Apply updates
        fields.update(updates)

        # Regenerate block
        # Need to create a config object for validation
        if fields.get("ulid"):
            # PWA
            config = PWAConfig(**fields)
        elif fields.get("terminal"):
            # Terminal app
            config = TerminalAppConfig(**fields)
        else:
            # Regular app
            config = ApplicationConfig(**fields)

        new_block = self._generate_mkapp_entry(config)

        # Replace in content
        modified = content.replace(old_block, new_block)

        # Write with backup and validation
        self._write_with_backup(modified)

        return {
            "status": "success",
            "rebuild_required": True,
            "app_name": name
        }

    def delete_application(self, name: str) -> Dict[str, Any]:
        """
        Delete application entry from Nix registry

        Args:
            name: Application name

        Returns:
            Result dict with status, PWA warning, and rebuild requirement

        Raises:
            ValueError: If app not found or Nix syntax invalid
        """
        with open(self.nix_file, 'r') as f:
            content = f.read()

        # Find and check if PWA
        pattern = rf'\s*\(mkApp \{{\s+name = "{re.escape(name)}";[^}}]+\}}[^)]*\)\s*'

        match = re.search(pattern, content, re.MULTILINE | re.DOTALL)
        if not match:
            raise ValueError(f"Application '{name}' not found in registry")

        # Check if PWA (contains ulid field)
        is_pwa = 'ulid =' in match.group(0)
        pwa_warning = None

        if is_pwa:
            # Extract ULID for warning message
            ulid_match = re.search(r'ulid = "([^"]+)"', match.group(0))
            ulid = ulid_match.group(1) if ulid_match else "UNKNOWN"
            pwa_warning = f"PWA must also be uninstalled via: pwa-uninstall {ulid}"

        # Remove the mkApp block
        modified = re.sub(pattern, '', content, count=1, flags=re.MULTILINE | re.DOTALL)

        # Write with backup and validation
        self._write_with_backup(modified)

        return {
            "status": "success",
            "pwa_warning": pwa_warning,
            "rebuild_required": True,
            "app_name": name
        }

    def _app_exists(self, content: str, name: str) -> bool:
        """Check if app already exists in Nix file"""
        pattern = rf'name = "{re.escape(name)}";'
        return bool(re.search(pattern, content))

    def _generate_mkapp_entry(self, config: ApplicationConfig) -> str:
        """Generate formatted (mkApp {...}) entry with proper indentation"""
        indent = "    "

        # Convert parameters list to Nix format
        if config.parameters:
            params_str = " ".join(f'"{p}"' for p in config.parameters)
        else:
            params_str = ""

        # Base fields
        template = f'''    (mkApp {{
{indent}  name = "{config.name}";
{indent}  display_name = "{config.display_name}";
{indent}  command = "{config.command}";
{indent}  parameters = "{params_str}";
{indent}  scope = "{config.scope}";
{indent}  expected_class = "{config.expected_class}";
{indent}  preferred_workspace = {config.preferred_workspace};'''

        # Optional fields
        if config.preferred_monitor_role:
            template += f'\n{indent}  preferred_monitor_role = "{config.preferred_monitor_role}";'

        template += f'\n{indent}  icon = "{config.icon}";'
        template += f'\n{indent}  nix_package = "{config.nix_package}";'
        template += f'\n{indent}  multi_instance = {str(config.multi_instance).lower()};'
        template += f'\n{indent}  floating = {str(config.floating).lower()};'

        if config.floating_size:
            template += f'\n{indent}  floating_size = "{config.floating_size}";'

        template += f'\n{indent}  fallback_behavior = "{config.fallback_behavior}";'
        template += f'\n{indent}  description = "{config.description}";'
        template += f'\n{indent}  terminal = {str(config.terminal).lower()};'

        # PWA-specific fields
        if isinstance(config, PWAConfig):
            template += f'\n{indent}  ulid = "{config.ulid}";'
            template += f'\n{indent}  start_url = "{config.start_url}";'
            template += f'\n{indent}  scope_url = "{config.scope_url}";'
            template += f'\n{indent}  app_scope = "{config.app_scope}";'
            template += f'\n{indent}  categories = "{config.categories}";'
            template += f'\n{indent}  keywords = "{config.keywords}";'

        template += f'\n{indent}}})'

        return template

    def _parse_mkapp_fields(self, block: str) -> Dict[str, Any]:
        """Parse fields from mkApp block using regex"""
        fields = {}

        # Extract each field: name = "value"; or name = 123; or name = true;
        field_pattern = r'(\w+)\s*=\s*([^;]+);'

        for match in re.finditer(field_pattern, block):
            key = match.group(1)
            value_raw = match.group(2).strip()

            # Type inference
            if value_raw.startswith('"') and value_raw.endswith('"'):
                fields[key] = value_raw[1:-1]  # String
            elif value_raw in ['true', 'false']:
                fields[key] = value_raw == 'true'  # Boolean
            elif value_raw.isdigit():
                fields[key] = int(value_raw)  # Number
            else:
                fields[key] = value_raw  # Other (null, expressions)

        # Handle parameters field specially (space-separated string to list)
        if 'parameters' in fields and fields['parameters']:
            # Split on spaces, remove quotes
            params = fields['parameters'].split()
            fields['parameters'] = [p.strip('"') for p in params]
        else:
            fields['parameters'] = []

        return fields

    def _generate_ulid(self) -> str:
        """
        Generate ULID using /etc/nixos/scripts/generate-ulid.sh

        Per spec.md Q5: Auto-generate ULID programmatically

        Returns:
            26-character ULID

        Raises:
            RuntimeError: If ULID generation fails
        """
        result = subprocess.run(
            ['/etc/nixos/scripts/generate-ulid.sh'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode != 0:
            raise RuntimeError(f"ULID generation failed: {result.stderr}")

        ulid = result.stdout.strip()

        # Validate format: 26 chars, Crockford Base32 (excludes I, L, O, U)
        if not re.match(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$', ulid):
            raise ValueError(f"Generated invalid ULID format: {ulid}")

        return ulid

    def _write_with_backup(self, content: str) -> None:
        """
        Write file with backup and Nix syntax validation

        Args:
            content: New file content

        Raises:
            ValueError: If Nix syntax is invalid (restores backup)
        """
        # Create backup
        backup_file = self.nix_file.with_suffix('.nix.bak')
        if self.nix_file.exists():
            shutil.copy2(self.nix_file, backup_file)

        # Write new content
        with open(self.nix_file, 'w') as f:
            f.write(content)

        # Validate Nix syntax
        result = subprocess.run(
            ['nix-instantiate', '--parse', str(self.nix_file)],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            # Syntax error - restore backup
            if backup_file.exists():
                shutil.copy2(backup_file, self.nix_file)
            raise ValueError(f"Generated invalid Nix syntax: {result.stderr}")
