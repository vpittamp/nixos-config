{ ... }:
{
  programs.plasma = {
    # Keep GUI editable by default while still allowing declarative overlays
    immutableByDefault = false;
  };
}
