"""Mock daemon for testing daemon client integration."""

import asyncio
import json
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class MockProject:
    """Mock project for testing."""
    name: str
    directory: str = "/tmp/test-project"
    display_name: str = "Test Project"
    icon: str = ""
    scoped_classes: List[str] = field(default_factory=list)
    workspace_preferences: Dict[int, str] = field(default_factory=dict)


@dataclass
class MockDaemonState:
    """Mock daemon state."""
    active_project: Optional[MockProject] = None
    window_rules: List[Dict[str, Any]] = field(default_factory=list)
    workspace_config: List[Dict[str, Any]] = field(default_factory=list)
    app_classification: Dict[str, Any] = field(default_factory=dict)


class MockDaemon:
    """Mock daemon for testing IPC calls."""
    
    def __init__(self):
        self.state = MockDaemonState()
        self.call_history: List[Dict[str, Any]] = []
        self.running = False
        
    async def handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Handle JSON-RPC request."""
        self.call_history.append(request)
        
        method = request.get("method")
        params = request.get("params", {})
        request_id = request.get("id")
        
        # Dispatch to method handlers
        if method == "get_window_rules":
            result = await self._get_window_rules(params)
        elif method == "classify_window":
            result = await self._classify_window(params)
        elif method == "get_workspace_config":
            result = await self._get_workspace_config(params)
        elif method == "get_monitor_config":
            result = await self._get_monitor_config(params)
        elif method == "reload_window_rules":
            result = await self._reload_window_rules(params)
        elif method == "get_active_project":
            result = await self._get_active_project(params)
        else:
            return {
                "jsonrpc": "2.0",
                "error": {"code": -32601, "message": f"Method not found: {method}"},
                "id": request_id
            }
        
        return {
            "jsonrpc": "2.0",
            "result": result,
            "id": request_id
        }
    
    async def _get_window_rules(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get window rules with optional scope filter."""
        filter_scope = params.get("filter_scope", "all")
        rules = self.state.window_rules
        
        if filter_scope != "all":
            rules = [r for r in rules if r.get("pattern_rule", {}).get("scope") == filter_scope]
        
        return {
            "rules": rules,
            "count": len(rules)
        }
    
    async def _classify_window(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Classify a window using current rules."""
        window_class = params.get("window_class", "")
        window_title = params.get("window_title", "")
        project_name = params.get("project_name")
        
        # Simple mock classification logic
        # Priority 1: Project scoped_classes
        if self.state.active_project and window_class in self.state.active_project.scoped_classes:
            return {
                "scope": "scoped",
                "workspace": None,
                "source": "project",
                "matched_pattern": f"{window_class} (from {self.state.active_project.name}.scoped_classes)"
            }
        
        # Priority 2: Window rules
        for rule in self.state.window_rules:
            pattern_rule = rule.get("pattern_rule", {})
            pattern = pattern_rule.get("pattern", "")
            
            # Simple literal match for mock
            if window_class == pattern or pattern in window_class:
                return {
                    "scope": pattern_rule.get("scope", "global"),
                    "workspace": rule.get("workspace"),
                    "source": "window_rule",
                    "matched_pattern": pattern
                }
        
        # Default: global
        return {
            "scope": "global",
            "workspace": None,
            "source": "default",
            "matched_pattern": None
        }
    
    async def _get_workspace_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get workspace configuration."""
        workspace_number = params.get("workspace_number")
        
        workspaces = self.state.workspace_config
        if workspace_number:
            workspaces = [w for w in workspaces if w.get("number") == workspace_number]
        
        return {
            "workspaces": workspaces,
            "count": len(workspaces)
        }
    
    async def _get_monitor_config(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get monitor configuration."""
        # Return mock single monitor config
        return {
            "monitors": [
                {
                    "name": "DP-1",
                    "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
                    "active": True,
                    "primary": True,
                    "role": "primary"
                }
            ],
            "count": 1
        }
    
    async def _reload_window_rules(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Reload window rules from disk."""
        return {
            "success": True,
            "window_rules_count": len(self.state.window_rules),
            "workspace_config_count": len(self.state.workspace_config)
        }
    
    async def _get_active_project(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Get active project."""
        if self.state.active_project:
            return {
                "name": self.state.active_project.name,
                "directory": self.state.active_project.directory,
                "display_name": self.state.active_project.display_name
            }
        return None
    
    def set_window_rules(self, rules: List[Dict[str, Any]]):
        """Set window rules for testing."""
        self.state.window_rules = rules
    
    def set_workspace_config(self, config: List[Dict[str, Any]]):
        """Set workspace config for testing."""
        self.state.workspace_config = config
    
    def set_active_project(self, project: MockProject):
        """Set active project for testing."""
        self.state.active_project = project


def create_mock_daemon(**kwargs) -> MockDaemon:
    """Factory function to create mock daemon with custom state."""
    daemon = MockDaemon()
    
    if "window_rules" in kwargs:
        daemon.set_window_rules(kwargs["window_rules"])
    if "workspace_config" in kwargs:
        daemon.set_workspace_config(kwargs["workspace_config"])
    if "active_project" in kwargs:
        daemon.set_active_project(kwargs["active_project"])
    
    return daemon
