# Desktop native helper checks

Runner: `cargo test --offline --locked --release --test desktop_config_cli`.

| Contract | Saved assertion |
| --- | --- |
| Filter migration/on/off/idempotence/absent file | `kitty_filter_round_trip_preserves_user_text`: exact independently expected bytes after each call, preserved unrelated/shifted mapping and Unicode path. |
| Defaults removal | `kitty_default_removal_preserves_unrelated_settings`: exact personal setting bytes after two removals. |
| Unit template | `unit_render_handles_spaces_unicode_and_literal_shell_characters`: both literal replacements, unrelated directive retained, normalized newline and repeat equality. |
| Shared shape, invalid mode, missing files | `rejections_preserve_existing_config_and_unit`: exact statuses and immediate unchanged file reads. All operands are text/paths; no numeric rule. |
| Real installer callers, no Python/Cargo runtime detection | `test_desktop_native_shell.sh`: public shell operations with Python trapped, systemctl mocked; read-only GDM resolution with Cargo hidden. Retained lifecycle/detection tests observe complete contents. |

Each mutable case uses fresh temporary state. No real service, setting, GUI or
GDM file is touched. The file-operation API has no new value query; direct
file bytes are the strongest observation for this static filesystem interface.
