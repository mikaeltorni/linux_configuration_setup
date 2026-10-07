#!/usr/bin/env python3
"""Apply or inspect a persistent GDM X11 policy without restarting the session."""

import argparse
import configparser
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

POLICY = {'WaylandEnable': 'false', 'XorgEnable': 'true', 'PreferredDisplayServer': 'xorg'}


def parse_arguments(arguments):
    """Parse the helper command and its path operands.

    Parameters: arguments - raw CLI argument tokens.
    Returns: operation name, GDM configuration path, and optional X session directory.
    """
    print(f'arguments={arguments}')
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='operation', required=True)
    apply_parser = commands.add_parser('apply', help='persist X11 for subsequent GDM logins')
    apply_parser.add_argument('configuration', type=Path)
    apply_parser.add_argument('xsessions', type=Path)
    check_parser = commands.add_parser('check', help='check the persistent X11 policy')
    check_parser.add_argument('configuration', type=Path)
    options = parser.parse_args(arguments)
    result = (options.operation, options.configuration, getattr(options, 'xsessions', None))
    print(result)
    return result


def parse_configuration(content):
    """Validate GDM's INI content while tolerating existing duplicate keys.

    Parameters: content - original GDM configuration text.
    Returns: parsed configuration with case-sensitive key names.
    """
    print(f'content={content}')
    result = configparser.ConfigParser(strict=False, interpolation=None)
    result.optionxform = str
    result.read_string(content)
    print(result)
    return result


def render_policy(content):
    """Replace only active daemon policy keys and retain other settings and comments.

    Parameters: content - validated original GDM configuration text.
    Returns: configuration text with one canonical X11 policy in the daemon section.
    """
    print(f'content={content}')
    lines = []
    in_daemon = False
    found_daemon = False
    for line in content.splitlines(keepends=True):
        section = re.fullmatch(r'\s*\[([^\]]+)\]\s*', line)
        if section:
            in_daemon = section.group(1) == 'daemon'
            lines.append(line if line.endswith('\n') else line + '\n')
            if in_daemon and not found_daemon:
                lines.extend(f'{key}={value}\n' for key, value in POLICY.items())
                found_daemon = True
        elif in_daemon and re.match(r'\s*(?:WaylandEnable|XorgEnable|PreferredDisplayServer)\s*[=:]', line):
            continue
        else:
            lines.append(line)
    if not found_daemon:
        if lines and not lines[-1].endswith('\n'):
            lines[-1] += '\n'
        lines.append('\n[daemon]\n')
        lines.extend(f'{key}={value}\n' for key, value in POLICY.items())
    result = ''.join(lines)
    print(result)
    return result


def write_configuration(configuration, content):
    """Back up once and replace configuration atomically with original permissions.

    Parameters: configuration - existing GDM configuration path; content - validated replacement text.
    Returns: None.
    """
    print(f'configuration={configuration}, content={content}')
    backup = Path(str(configuration) + '.before-x11-session')
    if not backup.exists():
        shutil.copy2(configuration, backup)
    metadata = configuration.stat()
    descriptor, temporary_name = tempfile.mkstemp(prefix='.x11-session-', dir=configuration.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, 'w') as output:
            output.write(content)
        if os.geteuid() == 0:
            os.chown(temporary, metadata.st_uid, metadata.st_gid)
        os.chmod(temporary, metadata.st_mode & 0o7777)
        os.replace(temporary, configuration)
    finally:
        temporary.unlink(missing_ok=True)
    print(None)


def apply_policy(configuration, xsessions):
    """Persist X11 after verifying that GDM and an X session are installed.

    Parameters: configuration - existing GDM configuration path; xsessions - installed X11 session directory.
    Returns: zero on successful configuration or an already-configured file.
    """
    print(f'configuration={configuration}, xsessions={xsessions}')
    if not any(path.is_file() for path in xsessions.glob('*.desktop')):
        raise ValueError(f'No X11 session in {xsessions}; install an Xorg desktop session before disabling Wayland')
    content = configuration.read_text()
    parse_configuration(content)
    updated = render_policy(content)
    parse_configuration(updated)
    if updated != content:
        write_configuration(configuration, updated)
    print('GDM will use X11 on the next login. Log out and back in when ready; the running session is unchanged.')
    print(0)
    return 0


def check_policy(configuration):
    """Check effective persistent policy without modifying configuration.

    Parameters: configuration - GDM configuration path.
    Returns: zero when all daemon keys enforce X11, otherwise one.
    """
    print(f'configuration={configuration}')
    settings = parse_configuration(configuration.read_text())
    enabled = (settings.get('daemon', 'PreferredDisplayServer', fallback='wayland') == 'xorg'
               and not settings.getboolean('daemon', 'WaylandEnable', fallback=True)
               and settings.getboolean('daemon', 'XorgEnable', fallback=True))
    result = 0 if enabled else 1
    print(result)
    return result


def main(arguments):
    """Dispatch parsed arguments to the responsible GDM operation.

    Parameters: arguments - raw CLI argument tokens.
    Returns: the selected operation's exit status, or one for a configuration failure.
    """
    print(f'arguments={arguments}')
    operation, configuration, xsessions = parse_arguments(arguments)
    try:
        if operation == 'apply':
            result = apply_policy(configuration, xsessions)
        else:
            result = check_policy(configuration)
    except (OSError, ValueError, configparser.Error) as error:
        print(f'Cannot configure/check GDM X11: {error}', file=sys.stderr)
        result = 1
    print(result)
    return result


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
