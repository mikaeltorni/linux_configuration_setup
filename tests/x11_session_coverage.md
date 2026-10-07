# X11 session coverage

Runner: `python3 -m unittest discover -s tests -p 'test_x11_session.py' -v`.
Each case creates a fresh temporary HOME, state directory, GDM configuration,
X session directory and mock command directory. The actual `install.sh` runs in
subprocesses. An `id` stub simulates root only for `id -u`; a Unix socket fixture
satisfies the installer preflight. Desktop commands and sudo fail if invoked. systemctl accepts only the active-GDM probe and the main-process SIGHUP settings reload; arguments are captured.

| Interface/rule | Saved case and independent expectation |
| --- | --- |
| `--select x11_session` with the observed commented-out policy and autologin | `test_observed_configuration`: daemon WaylandEnable=false, XorgEnable=true, PreferredDisplayServer=xorg; automatic login and security setting preserved; original backup exact; file permissions preserved |
| `--reconfigure x11_session` | `test_observed_configuration`: second run byte-identical config and backup, unchanged mtime; detect installed; only the exact settings-only GDM SIGHUP command is issued |
| Clean GDM config without daemon section / conflicting and duplicate keys | `test_config_shapes`: canonical daemon policy, unrelated sections/comments preserved, one active owned key per daemon |
| Missing GDM config | `test_missing_config`: nonzero exit; no file or backup created; detect absent |
| No installed X11 session | `test_missing_xsession`: nonzero exit; original populated config unchanged; no backup; detect absent |
| Malformed INI | `test_malformed_config`: nonzero exit; original populated config unchanged; no backup; detect absent |
| Sudo-free installation | `test_user_install_defers`: success with saved Session/XSession=ubuntu-xorg and SessionType=x11 through mocked AccountsService; exact sudo component command for global policy; config unchanged; global-policy detect absent (receipt cannot override live detection) |
| AccountsService denies the own-account change | `test_account_unavailable_defers`: no interactive authorization; populated account preference unchanged; global config unchanged; exact sudo command still reported |
| `--list-components` | `test_listing`: default-on component present, no configuration/backup/receipt writes |
| Default install selection | `test_default_selection`: framework's default-id output and saved default.json enable x11_session |
| Shared command validation | `test_invalid_selection`: unknown option and missing --select value rejected before mutation; public --detect still absent |
| Config helper operand parsing | `test_helper_arguments`: missing config/operand, extra operand and unknown operation rejected without changing populated config |

AccountsService calls are mocked and captured; no account service writes reach the machine from tests.

Numeric conversion and numeric domain cases are inapplicable: all operands are
paths. No uninstall operation is introduced: the component has a saved backup
but deliberately retains X11 policy on receipt-only uninstall. Current live
session remains unchanged, and no GUI/service restart command is permitted; only settings-only GDM SIGHUP is allowed.
