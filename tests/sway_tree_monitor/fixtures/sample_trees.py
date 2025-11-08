"""Sample Sway tree fixtures for testing

Provides realistic mock Sway tree structures at different scales:
- 50 windows: Typical developer setup (3-5 workspaces)
- 100 windows: Heavy multitasking (8-10 workspaces)
- 200 windows: Stress test scenario (15-20 workspaces)

Based on actual Sway tree structure from research.md.
"""

from typing import Dict, Any, List


def create_container(
    container_id: int,
    name: str,
    container_type: str = "con",
    layout: str = "splith",
    x: int = 0,
    y: int = 0,
    width: int = 1920,
    height: int = 1080,
    focused: bool = False,
    app_id: str = None,
    nodes: List[Dict] = None,
    floating_nodes: List[Dict] = None
) -> Dict[str, Any]:
    """Create a container node matching Sway tree structure"""
    return {
        "id": container_id,
        "name": name,
        "type": container_type,
        "layout": layout,
        "rect": {"x": x, "y": y, "width": width, "height": height},
        "focused": focused,
        "visible": True,
        "urgent": False,
        "marks": [],
        "fullscreen_mode": 0,
        "floating": "auto_off",
        "app_id": app_id,
        "pid": container_id * 100 if app_id else None,
        "window": container_id * 10 if app_id else None,
        "nodes": nodes or [],
        "floating_nodes": floating_nodes or [],
    }


def create_workspace(
    ws_num: int,
    output_name: str,
    window_count: int,
    base_id: int = 1000
) -> Dict[str, Any]:
    """Create a workspace with specified number of windows"""
    ws_id = base_id + ws_num * 100

    # Create windows (evenly split between tiled and floating)
    tiled_count = window_count // 2
    floating_count = window_count - tiled_count

    tiled_windows = []
    for i in range(tiled_count):
        win_id = ws_id + i + 1
        tiled_windows.append(create_container(
            container_id=win_id,
            name=f"window_{win_id}",
            container_type="con",
            app_id=f"app_{i % 5}",  # Cycle through 5 app types
            x=i * 400,
            y=0,
            width=400,
            height=1080,
            focused=(i == 0 and ws_num == 1)  # Focus first window on WS 1
        ))

    floating_windows = []
    for i in range(floating_count):
        win_id = ws_id + tiled_count + i + 1
        floating_windows.append(create_container(
            container_id=win_id,
            name=f"float_{win_id}",
            container_type="floating_con",
            app_id=f"float_app_{i % 3}",
            x=50 + i * 50,
            y=50 + i * 50,
            width=800,
            height=600
        ))

    return create_container(
        container_id=ws_id,
        name=f"{ws_num}",
        container_type="workspace",
        layout="splith",
        nodes=tiled_windows,
        floating_nodes=floating_windows
    )


def create_output(
    output_name: str,
    workspaces: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """Create an output with workspaces"""
    return create_container(
        container_id=hash(output_name) % 10000,
        name=output_name,
        container_type="output",
        layout="output",
        width=1920,
        height=1080,
        nodes=workspaces
    )


def create_tree_50_windows() -> Dict[str, Any]:
    """Create tree with ~50 windows (typical developer setup)

    Distribution:
    - WS 1: 10 windows (5 tiled, 5 floating)
    - WS 2: 15 windows (8 tiled, 7 floating)
    - WS 3: 12 windows (6 tiled, 6 floating)
    - WS 4: 13 windows (7 tiled, 6 floating)
    Total: 50 windows across 4 workspaces
    """
    workspaces = [
        create_workspace(1, "eDP-1", window_count=10, base_id=1000),
        create_workspace(2, "eDP-1", window_count=15, base_id=2000),
        create_workspace(3, "eDP-1", window_count=12, base_id=3000),
        create_workspace(4, "eDP-1", window_count=13, base_id=4000),
    ]

    output = create_output("eDP-1", workspaces)

    return create_container(
        container_id=1,
        name="root",
        container_type="root",
        layout="splith",
        nodes=[output]
    )


def create_tree_100_windows() -> Dict[str, Any]:
    """Create tree with ~100 windows (heavy multitasking)

    Distribution:
    - WS 1-5: 12 windows each = 60
    - WS 6-8: 13 windows each = 39
    - WS 9: 1 empty workspace
    Total: 99 windows across 9 workspaces
    """
    workspaces = []
    for i in range(1, 6):
        workspaces.append(create_workspace(i, "eDP-1", window_count=12, base_id=i * 1000))

    for i in range(6, 9):
        workspaces.append(create_workspace(i, "eDP-1", window_count=13, base_id=i * 1000))

    # Empty workspace
    workspaces.append(create_workspace(9, "eDP-1", window_count=0, base_id=9000))

    output = create_output("eDP-1", workspaces)

    return create_container(
        container_id=1,
        name="root",
        container_type="root",
        layout="splith",
        nodes=[output]
    )


def create_tree_200_windows() -> Dict[str, Any]:
    """Create tree with ~200 windows (stress test)

    Distribution:
    - WS 1-10: 12 windows each = 120
    - WS 11-18: 10 windows each = 80
    Total: 200 windows across 18 workspaces
    """
    workspaces = []
    for i in range(1, 11):
        workspaces.append(create_workspace(i, "eDP-1", window_count=12, base_id=i * 1000))

    for i in range(11, 19):
        workspaces.append(create_workspace(i, "eDP-1", window_count=10, base_id=i * 1000))

    output = create_output("eDP-1", workspaces)

    return create_container(
        container_id=1,
        name="root",
        container_type="root",
        layout="splith",
        nodes=[output]
    )


def modify_tree_add_window(tree: Dict[str, Any], ws_num: int = 1) -> Dict[str, Any]:
    """Clone tree and add a new window to specified workspace

    Simulates: user opens new terminal
    """
    import copy
    new_tree = copy.deepcopy(tree)

    # Find workspace
    output = new_tree["nodes"][0]
    for ws in output["nodes"]:
        if ws["name"] == str(ws_num):
            # Add new window
            new_win_id = 99999
            new_window = create_container(
                container_id=new_win_id,
                name="new_window",
                app_id="alacritty",
                x=0,
                y=0,
                width=800,
                height=600,
                focused=True
            )
            ws["nodes"].append(new_window)
            break

    return new_tree


def modify_tree_move_window(tree: Dict[str, Any]) -> Dict[str, Any]:
    """Clone tree and move a window position

    Simulates: user resizes/moves window
    """
    import copy
    new_tree = copy.deepcopy(tree)

    # Modify first window geometry
    output = new_tree["nodes"][0]
    if output["nodes"] and output["nodes"][0]["nodes"]:
        first_window = output["nodes"][0]["nodes"][0]
        first_window["rect"]["x"] += 100
        first_window["rect"]["width"] -= 100

    return new_tree


def modify_tree_focus_change(tree: Dict[str, Any]) -> Dict[str, Any]:
    """Clone tree and change focused window

    Simulates: user switches window focus (Alt+Tab)
    """
    import copy
    new_tree = copy.deepcopy(tree)

    output = new_tree["nodes"][0]
    if output["nodes"] and output["nodes"][0]["nodes"]:
        # Unfocus first window, focus second
        windows = output["nodes"][0]["nodes"]
        if len(windows) >= 2:
            windows[0]["focused"] = False
            windows[1]["focused"] = True

    return new_tree


# Convenience exports
TREE_50 = create_tree_50_windows()
TREE_100 = create_tree_100_windows()
TREE_200 = create_tree_200_windows()
