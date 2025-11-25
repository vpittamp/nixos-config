"""
Application Registry Nix File Editor Service

Feature 094: Enhanced Projects & Applications CRUD Interface
Text-based manipulation of app-registry-data.nix per research.md findings
"""

import re
import shutil
import subprocess
import fcntl
import time
from pathlib import Path
from typing import Dict, Any, Optional, List
from dataclasses import dataclass
from contextlib import contextmanager

from ..models.app_config import ApplicationConfig, PWAConfig, TerminalAppConfig


@dataclass
class EditResult:
    """Result of an edit operation"""
    success: bool
    backup_path: Optional[str] = None
    error_message: str = ""


@dataclass
class ValidationResult:
    """Result of Nix syntax validation"""
    valid: bool
    error_message: str = ""


class AppRegistryEditor:
    """Service for editing app-registry-data.nix using text-based manipulation"""

    def __init__(self, nix_file_path: Optional[str] = None, nix_file: Optional[Path] = None):
        """
        Initialize app registry editor

        Args:
            nix_file_path: String path to app-registry-data.nix (for test compatibility)
            nix_file: Path object to app-registry-data.nix
        """
        if nix_file_path:
            self.nix_file = Path(nix_file_path)
        elif nix_file:
            self.nix_file = nix_file
        else:
            self.nix_file = Path("/etc/nixos/home-modules/desktop/app-registry-data.nix")

        self._lock_file = None
        self._lock_fd = None

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

    def edit_application(self, name: str, updates: Dict[str, Any], wait_for_lock: bool = True) -> EditResult:
        """
        Edit existing application entry

        Args:
            name: Application name
            updates: Dict of fields to update
            wait_for_lock: Whether to wait for file lock (default True)

        Returns:
            EditResult with success status, backup path, and error message
        """
        try:
            # Acquire lock
            if wait_for_lock:
                with self.acquire_lock():
                    return self._do_edit(name, updates)
            else:
                # Try to acquire without blocking
                try:
                    with self.acquire_lock():
                        return self._do_edit(name, updates)
                except BlockingIOError:
                    return EditResult(
                        success=False,
                        error_message="File is currently locked by another process"
                    )
        except FileNotFoundError as e:
            return EditResult(success=False, error_message=str(e))
        except PermissionError as e:
            return EditResult(success=False, error_message=f"Permission denied: {e}")
        except ValueError as e:
            return EditResult(success=False, error_message=str(e))
        except Exception as e:
            return EditResult(success=False, error_message=f"Unexpected error: {e}")

    def _do_edit(self, name: str, updates: Dict[str, Any]) -> EditResult:
        """Internal edit implementation"""
        content = self.read_file()

        # Find the mkApp block for this application
        pattern = rf'\(mkApp \{{\s+name = "{re.escape(name)}";[^}}]+\}}[^)]*\)'

        match = re.search(pattern, content, re.MULTILINE | re.DOTALL)
        if not match:
            return EditResult(
                success=False,
                error_message=f"Application '{name}' not found in registry"
            )

        # Parse existing fields
        old_block = match.group(0)
        fields = self._parse_mkapp_fields(old_block)

        # Apply updates
        fields.update(updates)

        # Regenerate block with validation
        try:
            if fields.get("ulid"):
                # PWA
                config = PWAConfig(**fields)
            elif fields.get("terminal"):
                # Terminal app
                config = TerminalAppConfig(**fields)
            else:
                # Regular app
                config = ApplicationConfig(**fields)
        except Exception as e:
            return EditResult(
                success=False,
                error_message=f"Validation error: {e}"
            )

        new_block = self._generate_mkapp_entry(config)

        # Replace in content
        modified = content.replace(old_block, new_block)

        # Create backup
        backup_path = self.create_backup()

        # Write new content
        try:
            with open(self.nix_file, 'w') as f:
                f.write(modified)
        except Exception as e:
            return EditResult(
                success=False,
                backup_path=str(backup_path),
                error_message=f"Failed to write file: {e}"
            )

        # Validate Nix syntax
        validation = self.validate_nix_syntax(str(self.nix_file))
        if not validation.valid:
            # Restore backup on validation failure
            self.restore_from_backup(backup_path)
            return EditResult(
                success=False,
                backup_path=str(backup_path),
                error_message=f"Invalid Nix syntax: {validation.error_message}"
            )

        return EditResult(
            success=True,
            backup_path=str(backup_path)
        )

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

        # Convert parameters list to Nix list format
        if config.parameters:
            params_str = " ".join(f'"{p}"' for p in config.parameters)
            params_field = f'[{params_str}]'
        else:
            params_field = '[]'

        # Base fields
        template = f'''    (mkApp {{
{indent}  name = "{config.name}";
{indent}  display_name = "{config.display_name}";
{indent}  command = "{config.command}";
{indent}  parameters = {params_field};
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

        # Handle parameters field specially (space-separated string to list or Nix list syntax)
        if 'parameters' in fields:
            params_value = fields['parameters']
            if params_value == '[]' or params_value == '':
                # Empty list
                fields['parameters'] = []
            elif params_value.startswith('[') and params_value.endswith(']'):
                # Nix list syntax: ["-e" "bash"]
                # Remove brackets and split, then strip quotes
                inner = params_value[1:-1].strip()
                if inner:
                    # Split on quotes and filter
                    params = [p.strip('"').strip() for p in inner.split('"') if p.strip() and p.strip() not in ['', ' ']]
                    fields['parameters'] = params
                else:
                    fields['parameters'] = []
            else:
                # Space-separated string: "-e" "bash"
                params = params_value.split()
                fields['parameters'] = [p.strip('"') for p in params if p.strip()]
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

    # Additional helper methods for test compatibility (T043)

    def read_file(self) -> str:
        """Read Nix file contents"""
        with open(self.nix_file, 'r') as f:
            return f.read()

    def find_app_block(self, name: str) -> Optional[str]:
        """Find mkApp block by application name"""
        content = self.read_file()
        pattern = rf'\(mkApp \{{\s+name = "{re.escape(name)}";[^}}]+\}}[^)]*\)'
        match = re.search(pattern, content, re.MULTILINE | re.DOTALL)
        return match.group(0) if match else None

    def parse_field(self, block: str, field_name: str) -> Any:
        """Parse a specific field from mkApp block"""
        fields = self._parse_mkapp_fields(block)
        return fields.get(field_name)

    def update_field(self, block: str, field_name: str, value: Any) -> str:
        """Update a specific field in mkApp block"""
        fields = self._parse_mkapp_fields(block)
        fields[field_name] = value

        # Reconstruct block with updated field
        # Simple approach: regex replace for the specific field
        if isinstance(value, str):
            new_value = f'"{value}"'
        elif isinstance(value, bool):
            new_value = str(value).lower()
        elif isinstance(value, int):
            new_value = str(value)
        elif isinstance(value, list):
            new_value = '" "'.join(f'"{v}"' if isinstance(v, str) else str(v) for v in value)
            new_value = f'[{new_value}]' if value else '[]'
        elif value is None:
            # Remove the field
            pattern = rf'\s*{re.escape(field_name)}\s*=\s*[^;]+;\s*'
            return re.sub(pattern, '', block)
        else:
            new_value = str(value)

        # Replace field value
        pattern = rf'({re.escape(field_name)}\s*=\s*)[^;]+;'
        replacement = rf'\1{new_value};'

        updated_block = re.sub(pattern, replacement, block)

        # If field doesn't exist and value is not None, add it
        if updated_block == block and value is not None:
            # Add before closing brace
            insert_pattern = r'(\s*\})\)'
            field_line = f'\n    {field_name} = {new_value};'
            updated_block = re.sub(insert_pattern, f'{field_line}\\1)', block)

        return updated_block

    def create_backup(self) -> Path:
        """Create backup file and return path"""
        backup_path = self.nix_file.with_suffix('.nix.backup')
        if self.nix_file.exists():
            shutil.copy2(self.nix_file, backup_path)
        return backup_path

    def restore_from_backup(self, backup_path: Path) -> None:
        """Restore file from backup"""
        if not backup_path.exists():
            raise FileNotFoundError(f"Backup file not found: {backup_path}")
        shutil.copy2(backup_path, self.nix_file)

    def validate_nix_syntax(self, file_path: str) -> ValidationResult:
        """Validate Nix file syntax using nix-instantiate"""
        result = subprocess.run(
            ['nix-instantiate', '--parse', file_path],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            return ValidationResult(valid=True)
        else:
            return ValidationResult(valid=False, error_message=result.stderr)

    @contextmanager
    def acquire_lock(self):
        """Context manager for file locking"""
        lock_file = self.nix_file.with_suffix('.lock')
        lock_fd = open(lock_file, 'w')

        try:
            fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            self._lock_file = lock_file
            self._lock_fd = lock_fd
            yield
        finally:
            if lock_fd:
                fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
                lock_fd.close()
            if lock_file.exists():
                lock_file.unlink()
            self._lock_file = None
            self._lock_fd = None

    def is_locked(self) -> bool:
        """Check if file is currently locked"""
        return self._lock_fd is not None

    def cleanup_old_backups(self, max_keep: int = 5) -> None:
        """Clean up old backup files, keeping only the most recent max_keep"""
        backup_pattern = f"{self.nix_file.stem}.nix.backup.*"
        backup_dir = self.nix_file.parent

        backups = sorted(
            backup_dir.glob(backup_pattern),
            key=lambda p: p.stat().st_mtime,
            reverse=True
        )

        # Delete backups beyond max_keep
        for backup in backups[max_keep:]:
            backup.unlink()
