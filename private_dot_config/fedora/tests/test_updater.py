"""Exercise the interactive Fedora updater without privilege or network access."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

UPDATER = Path(__file__).resolve().parents[1] / 'update-system.sh'

class UpdaterTests(unittest.TestCase):
    def run_updater(self, updates='', answer='', failure=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'os-release').write_text('ID=fedora\n')
            # Run an exact copy with only its os-release input redirected to a fixture.
            script = root/'updater'
            script.write_text(UPDATER.read_text().replace('/etc/os-release', str(root/'os-release')))
            mocks = {
                'dnf5': '#!/bin/sh\ncase " $* " in *" repoquery "*) [ "$FAIL_QUERY" = 0 ] || { echo network-failed >&2; exit 1; }; printf "%s" "$UPDATES";; *) echo "dnf5 $*" >> "$CALLS";; esac\n',
                'sudo': '#!/bin/sh\necho "sudo $*" >> "$CALLS"\n',
                'systemctl': '#!/bin/sh\nexit 1\n',
                'df': '#!/bin/sh\nprintf "Avail\\n107374182400\\n"\n',
            }
            for name, content in mocks.items():
                path=root/name; path.write_text(content); path.chmod(0o755)
            env={**os.environ, 'PATH': str(root)+':/usr/bin', 'UPDATES': updates,
                 'FAIL_QUERY': '1' if failure else '0', 'CALLS': str(root/'calls')}
            result=subprocess.run(['bash',str(script)],input=answer,text=True,capture_output=True,env=env,timeout=5)
            calls=(root/'calls').read_text() if (root/'calls').exists() else ''
            return result, calls
    def test_no_updates_needs_no_privilege(self):
        result,calls=self.run_updater()
        self.assertEqual(result.returncode,0,result.stderr); self.assertEqual(calls,'')
    def test_decline_needs_no_privilege(self):
        result,calls=self.run_updater('kernel.x86_64 1\n','n\n')
        self.assertEqual(result.returncode,0,result.stderr); self.assertEqual(calls,'')
    def test_query_failure_cannot_claim_up_to_date(self):
        result,calls=self.run_updater(failure=True)
        self.assertNotEqual(result.returncode,0); self.assertNotIn('up to date',result.stdout); self.assertEqual(calls,'')
    def test_confirmed_update_is_rpm_only(self):
        result,calls=self.run_updater('kernel.x86_64 1\n','y\n')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(calls.splitlines(),['sudo -v','sudo -n dnf5 --refresh upgrade'])

if __name__ == '__main__':
    unittest.main()
