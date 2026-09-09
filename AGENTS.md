# Clean Installation Compatibility

The `linux-configuration` skill owns the clean-install and root-optional
installer rules; they are not restated here. Repository-specific installer
facts:

Window-count badges are owned by `linux_taskbar_window_count`; keep GNOME
desktop settings work in this repository focused on configuration outside that
extension.

## Shared workflow

This file intentionally contains project-specific ownership, data-safety,
component, integration, and deployment facts. The reusable workflow rules
live in the selected skills and must not be copied into every project file.

Before editing, read this project file, then load:

- `general-programming-guidelines` for the engineering workflow;
- `commits` for capability boundaries and commit verification;
- `worktree` for isolation, branch, merge, and consumer reapplication; and
- `linux-configuration` when the task touches GNOME, desktop settings,
  systemd user services, or any `install.sh`.

Those skills are the cross-project source of truth for workflow, delivery,
desktop deployment, clean-install compatibility, and root-optional installer
rules. Project-specific sections here may narrow ownership or add required
verification, but must not restate or contradict those shared policies.
