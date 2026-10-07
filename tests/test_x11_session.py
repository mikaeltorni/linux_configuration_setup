"""Exercise persistent X11 selection through the isolated public installer."""

import configparser
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FRAMEWORK = next(path for path in (Path(os.environ.get('ISC_FUNCTIONS_DIR', '/nonexistent')),
                                   ROOT.parent / 'linux_installation_scripts_functions',
                                   Path.home() / 'projects/linux_installation_scripts_functions')
                 if (path / 'component_loader.sh').is_file())
OBSERVED = '''# GDM configuration storage
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=mk
#WaylandEnable=false
[security]
DisallowTCP=true
'''


class X11SessionTests(unittest.TestCase):
    """Keep each installer invocation away from the real desktop and GDM files."""

    def setUp(self):
        """Create fresh configuration, home, session and command fixtures.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.conf = self.base / 'gdm3' / 'custom.conf'
        self.conf.parent.mkdir()
        self.conf.write_text(OBSERVED)
        self.conf.chmod(0o640)
        self.backup = Path(str(self.conf) + '.before-x11-session')
        self.sessions = self.base / 'xsessions'
        self.sessions.mkdir()
        (self.sessions / 'ubuntu-xorg.desktop').write_text('[Desktop Entry]\nName=Ubuntu on Xorg\n')
        self.home = self.base / 'home'
        self.home.mkdir()
        self.runtime = self.base / 'runtime'
        self.runtime.mkdir()
        self.bus = socket.socket(socket.AF_UNIX)
        self.bus.bind(str(self.runtime / 'bus'))
        self.addCleanup(self.bus.close)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        uid = os.getuid()
        (self.bin / 'id').write_text(
            '#!/bin/bash\nif [[ "$*" == "-u" ]]; then echo "${TEST_EUID:-0}"; '
            f'elif [[ "$1" == "-u" ]]; then echo {uid}; else exec /usr/bin/id "$@"; fi\n')
        blocked = '#!/bin/bash\necho "Unexpected desktop command: $0 $*" >&2\nexit 99\n'
        for name in ('sudo', 'gsettings', 'gnome-extensions', 'xdotool', 'reboot', 'shutdown', 'loginctl'):
            (self.bin / name).write_text(blocked)
        self.command_log = self.base / 'systemctl-calls'
        (self.bin / 'systemctl').write_text(
            '#!/bin/bash\ncase "$*" in\n'
            '"is-active --quiet gdm.service"|"kill --kill-who=main --signal=HUP gdm.service")\n'
            ' printf "%s\\n" "$*" >> "$TEST_SYSTEMCTL_LOG"; exit 0 ;;\n'
            '*) echo "Unexpected systemctl command: $*" >&2; exit 99 ;;\nesac\n')
        for item in self.bin.iterdir():
            item.chmod(0o755)
        # Install.sh derives RUNTIME_DIR from TARGET_UID. Override only that
        # session-bus fixture with a BASH_ENV DEBUG trap before main executes.
        self.bootstrap = self.base / 'bash-env'
        self.bootstrap.write_text('trap \'RUNTIME_DIR="$TEST_RUNTIME_DIR"\' DEBUG\n')
        self.env = os.environ.copy()
        self.env.update(HOME=str(self.home), TARGET_HOME_OVERRIDE=str(self.home),
                        XDG_STATE_HOME=str(self.home / 'state'), XDG_CACHE_HOME=str(self.home / 'cache'),
                        ISC_FUNCTIONS_DIR=str(FRAMEWORK), INSTALLER_NO_REBOOT='1',
                        GDM_CUSTOM_CONF=str(self.conf), GDM_XSESSIONS_DIR=str(self.sessions),
                        PATH=f'{self.bin}:{os.environ["PATH"]}', BASH_ENV=str(self.bootstrap),
                        TEST_RUNTIME_DIR=str(self.runtime), TEST_SYSTEMCTL_LOG=str(self.command_log),
                        SUDO_USER='', TEST_EUID='0')
        print(None)

    def installer(self, *arguments):
        """Run the real installer against this case's fixture environment.

        Parameters: self - the test instance; arguments - installer argument tokens.
        Returns: completed subprocess result.
        """
        print(f'self={object.__repr__(self)}, arguments={arguments}')
        result = subprocess.run(['bash', str(ROOT / 'install.sh'), *arguments], env=self.env,
                                text=True, capture_output=True, timeout=30)
        print(result)
        return result

    def policy(self):
        """Read the fixture using an independent standard INI parser.

        Parameters: self - the test instance.
        Returns: parsed configuration.
        """
        print(f'self={object.__repr__(self)}')
        result = configparser.ConfigParser(strict=False)
        result.read(self.conf)
        print(result)
        return result

    def assert_absent(self):
        """Observe absent policy through the installer's public detection command.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        result = self.installer('--detect')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('x11_session\tabsent', result.stdout)
        print(None)

    def test_observed_configuration(self):
        """Repair the exact observed configuration and preserve idempotence.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        self.assert_absent()
        result = self.installer('--select', 'x11_session')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        parsed = self.policy()
        self.assertFalse(parsed.getboolean('daemon', 'WaylandEnable'))
        self.assertTrue(parsed.getboolean('daemon', 'XorgEnable'))
        self.assertEqual(parsed['daemon']['PreferredDisplayServer'], 'xorg')
        self.assertEqual(parsed['daemon']['AutomaticLogin'], 'mk')
        self.assertTrue(parsed.getboolean('daemon', 'AutomaticLoginEnable'))
        self.assertTrue(parsed.getboolean('security', 'DisallowTCP'))
        self.assertEqual(self.backup.read_text(), OBSERVED)
        self.assertEqual(self.conf.stat().st_mode & 0o777, 0o640)
        content, mtime = self.conf.read_bytes(), self.conf.stat().st_mtime_ns
        result = self.installer('--reconfigure', 'x11_session')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.conf.read_bytes(), content)
        self.assertEqual(self.conf.stat().st_mtime_ns, mtime)
        self.assertEqual(self.backup.read_text(), OBSERVED)
        self.assertIn('x11_session\tinstalled', self.installer('--detect').stdout)
        self.assertEqual(self.command_log.read_text().splitlines(),
                         ['is-active --quiet gdm.service',
                          'kill --kill-who=main --signal=HUP gdm.service'] * 2)
        print(None)

    def test_config_shapes(self):
        """Handle absent daemon sections and duplicate conflicting policy keys.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        for content in ('# comment\n[security]\nWaylandEnable=true\n',
                        '[daemon]\n WaylandEnable = true\nWaylandEnable=true\nXorgEnable=false\nPreferredDisplayServer=wayland\n[security]\nWaylandEnable=true\n'):
            with self.subTest(content=content):
                self.conf.write_text(content)
                self.backup.unlink(missing_ok=True)
                result = self.installer('--select', 'x11_session')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(self.policy().getboolean('daemon', 'WaylandEnable'))
                self.assertTrue(self.policy().getboolean('daemon', 'XorgEnable'))
                self.assertEqual(self.policy()['daemon']['PreferredDisplayServer'], 'xorg')
                self.assertEqual(self.policy()['security']['WaylandEnable'], 'true')
                self.assertEqual(self.conf.read_text().count('WaylandEnable=false'), 1)
                self.assertEqual(self.backup.read_text(), content)
        print(None)

    def test_missing_config(self):
        """Reject an unavailable GDM configuration without creating system files.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        self.conf.unlink()
        self.assertNotEqual(self.installer('--select', 'x11_session').returncode, 0)
        self.assertFalse(self.conf.exists())
        self.assertFalse(self.backup.exists())
        self.assert_absent()
        print(None)

    def test_missing_xsession(self):
        """Reject a machine without an installed X11 session before modifying GDM.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        (self.sessions / 'ubuntu-xorg.desktop').unlink()
        self.assertNotEqual(self.installer('--select', 'x11_session').returncode, 0)
        self.assertEqual(self.conf.read_text(), OBSERVED)
        self.assertFalse(self.backup.exists())
        self.assert_absent()
        print(None)

    def test_malformed_config(self):
        """Preserve malformed existing configuration instead of replacing it.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        self.conf.write_text('not an INI config\n')
        self.assertNotEqual(self.installer('--select', 'x11_session').returncode, 0)
        self.assertEqual(self.conf.read_text(), 'not an INI config\n')
        self.assertFalse(self.backup.exists())
        self.assert_absent()
        print(None)

    def test_user_install_defers(self):
        """Defer root-only configuration without prompting or false detection.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        self.env['TEST_EUID'] = '1000'
        result = self.installer('--select', 'x11_session')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f'sudo bash {ROOT}/install.sh --select x11_session', result.stdout)
        self.assertEqual(self.conf.read_text(), OBSERVED)
        self.assertFalse(self.backup.exists())
        self.assert_absent()
        print(None)

    def test_listing(self):
        """List the default-on component without changing any fixture state.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        result = self.installer('--list-components')
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [line.split('\t') for line in result.stdout.splitlines()]
        row = next(row for row in rows if row[0] == 'x11_session')
        self.assertEqual(row[2], 'on')
        self.assertEqual(self.conf.read_text(), OBSERVED)
        self.assertFalse(self.backup.exists())
        self.assertEqual(list(self.home.iterdir()), [])
        print(None)

    def test_default_selection(self):
        """Confirm the normal default selection includes persistent X11.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        result = subprocess.run(['bash', '-c', 'source "$1"; _isc_default_ids', 'test',
                                 str(ROOT / 'install.sh')], env=self.env, text=True,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('x11_session', result.stdout.replace(',', ' ').split())
        saved = json.loads((ROOT / 'installation_configs/default.json').read_text())
        self.assertEqual(saved['components']['x11_session']['on'], 1)
        print(None)

    def test_invalid_selection(self):
        """Keep shared invalid selection inputs from mutating configured state.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        for arguments in (('--unknown-option',), ('--select',)):
            self.assertNotEqual(self.installer(*arguments).returncode, 0)
            self.assertEqual(self.conf.read_text(), OBSERVED)
            self.assert_absent()
        print(None)

    def test_helper_arguments(self):
        """Reject malformed helper arguments through its saved public CLI.

        Parameters: self - the test instance.
        Returns: None.
        """
        print(f'self={object.__repr__(self)}')
        for arguments in ([], ['apply'], ['apply', str(self.conf)], ['check'],
                          ['apply', str(self.conf), str(self.sessions), 'extra'],
                          ['check', str(self.conf), 'extra'], ['unknown', str(self.conf)]):
            result = subprocess.run(['python3', str(ROOT / 'scripts/gdm_x11.py'), *arguments],
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(self.conf.read_text(), OBSERVED)
            self.assert_absent()
        print(None)


if __name__ == '__main__':
    unittest.main()
