"""i3 tree inspector display mode.

Direct i3 IPC connection to inspect window tree hierarchy and marks.
"""

from typing import Any, List, Optional

import i3ipc.aio
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text
from rich.tree import Tree as RichTree

from .base import BaseDisplay


class TreeDisplay(BaseDisplay):
    """i3 window tree inspector mode."""

    def __init__(
        self,
        marks_filter: Optional[str] = None,
        expand: bool = False,
        console: Optional[Console] = None,
    ):
        """Initialize tree display.

        Args:
            marks_filter: Optional marks filter (e.g., "project:")
            expand: Whether to expand all nodes by default
            console: Optional Rich Console instance
        """
        # TreeDisplay doesn't use DaemonClient, so pass None to parent
        super().__init__(client=None, console=console)  # type: ignore
        self.marks_filter = marks_filter
        self.expand = expand

    async def run(self) -> None:
        """Run tree inspector display.

        This connects directly to i3 IPC and displays the window tree.
        """
        # Connect to i3
        try:
            i3 = await i3ipc.aio.Connection().connect()
        except Exception as e:
            self.print_error(f"Failed to connect to i3: {e}")
            return

        try:
            # Get i3 tree
            tree = await i3.get_tree()

            # Display tree
            self._display_tree(tree)

        except Exception as e:
            self.print_error(f"Error fetching i3 tree: {e}")
        finally:
            # Disconnect
            i3.main_quit()

    def _display_tree(self, tree: Any) -> None:
        """Display i3 window tree.

        Args:
            tree: i3ipc Container tree root
        """
        # Create Rich tree
        rich_tree = RichTree(
            "[bold cyan]i3 Window Tree[/bold cyan]",
            guide_style="dim",
        )

        # Build tree recursively
        self._build_tree(tree, rich_tree)

        # Display tree
        filter_info = f" (filter: {self.marks_filter})" if self.marks_filter else ""
        panel = Panel(
            rich_tree,
            title=f"[bold green]i3 Tree Inspector[/bold green]{filter_info}",
            border_style="green",
            padding=(0, 1),
        )

        self.console.print(panel)

    def _build_tree(
        self, container: Any, parent_node: RichTree, depth: int = 0
    ) -> None:
        """Recursively build tree from i3 container.

        Args:
            container: i3ipc Container node
            parent_node: Parent Rich Tree node
            depth: Current depth in tree
        """
        # Check marks filter
        if self.marks_filter:
            # Only include nodes that have matching marks
            # OR have descendants with matching marks
            if not self._has_matching_marks(container):
                # Skip this branch unless it has matching descendants
                if not self._has_matching_descendants(container):
                    return

        # Format node label
        label = self._format_node_label(container)

        # Add node to tree
        node = parent_node.add(label)

        # Add child nodes
        all_children = container.nodes + container.floating_nodes
        for child in all_children:
            self._build_tree(child, node, depth + 1)

    def _has_matching_marks(self, container: Any) -> bool:
        """Check if container has matching marks.

        Args:
            container: i3ipc Container

        Returns:
            True if container has marks matching filter
        """
        if not self.marks_filter:
            return True

        marks = container.marks or []
        return any(self.marks_filter in mark for mark in marks)

    def _has_matching_descendants(self, container: Any) -> bool:
        """Check if container has descendants with matching marks.

        Args:
            container: i3ipc Container

        Returns:
            True if any descendant has matching marks
        """
        if not self.marks_filter:
            return True

        # Check immediate children
        all_children = container.nodes + container.floating_nodes
        for child in all_children:
            if self._has_matching_marks(child):
                return True
            # Recursive check
            if self._has_matching_descendants(child):
                return True

        return False

    def _format_node_label(self, container: Any) -> str:
        """Format container as a labeled node.

        Args:
            container: i3ipc Container

        Returns:
            Formatted label string with markup
        """
        node_type = container.type
        node_id = container.id
        marks = container.marks or []
        name = container.name or "(unnamed)"

        # Color by type
        if node_type == "root":
            type_label = f"[bold magenta]{node_type.upper()}[/bold magenta]"
        elif node_type == "output":
            type_label = f"[bold cyan]OUTPUT[/bold cyan]"
        elif node_type == "workspace":
            # Highlight scratchpad
            if name == "__i3_scratch":
                type_label = f"[bold yellow]SCRATCHPAD[/bold yellow]"
            else:
                type_label = f"[bold green]WORKSPACE[/bold green]"
        elif node_type == "con":
            type_label = f"[cyan]CONTAINER[/cyan]"
        elif node_type == "floating_con":
            type_label = f"[yellow]FLOATING[/yellow]"
        else:
            type_label = f"[white]{node_type}[/white]"

        # Build label parts
        parts = [type_label]
        parts.append(f"[dim]#{node_id}[/dim]")

        # Add marks
        if marks:
            # Highlight project marks
            formatted_marks = []
            for mark in marks:
                if mark.startswith("project:"):
                    formatted_marks.append(f"[bold magenta]{mark}[/bold magenta]")
                else:
                    formatted_marks.append(f"[yellow]{mark}[/yellow]")
            marks_str = ", ".join(formatted_marks)
            parts.append(f"[{marks_str}]")

        # Add name/title
        if node_type == "con" or node_type == "floating_con":
            # For windows, show class and title
            window_class = container.window_class or "?"
            window_title = self.truncate_string(name, 40)
            parts.append(f"[cyan]{window_class}[/cyan]: {window_title}")
        else:
            parts.append(f"{name}")

        # Add window properties for containers
        if container.window and node_type in ["con", "floating_con"]:
            props = []
            if container.window_role:
                props.append(f"role={container.window_role}")
            if container.floating and container.floating != "auto_off":
                props.append(f"[yellow]floating={container.floating}[/yellow]")
            if container.layout and container.layout != "splith":
                props.append(f"layout={container.layout}")

            if props:
                props_str = " ".join(props)
                parts.append(f"[dim]({props_str})[/dim]")

        return " ".join(parts)
