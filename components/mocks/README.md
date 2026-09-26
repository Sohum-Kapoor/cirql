Fake walker responses matching `contracts/walkers.md`, one `.cl.jac` module per
walker (e.g. `goalrank.cl.jac` exporting `mock_goalrank() -> list[dict]`). B builds
every screen against these, then swaps to `root spawn Walker(...)` when A's walker
lands. Delete a mock when its walker is live.
