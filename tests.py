import unittest, platform

confsys = __import__("configure-syslog")

# "mock" out the LOGGER object
class Amorphous(object):
    def __getattr__(self, name):
        return lambda x: x

confsys.LOGGER = Amorphous()

class TestConfigureSyslog(unittest.TestCase):

    def test_get_syslog_version(self):

        r = confsys.get_syslog_version()
        t = r[0]
        
        self.assertTrue(len(r) > 0)
        self.assertTrue(isinstance(t, tuple) )

        self.assertTrue(t[0] in ['rsyslog', 'syslog-ng'] )

        # versions should only be of xx.yy form; no more, no less
        self.assertEquals(2, len(t[1].split('.')) )

    def skip_test_new_old_equality(self):

        new_get = confsys.new_get_syslog_version()

        distro_name, version, version_id = platform.linux_distribution()
        distro_id = confsys.get_os_id(distro_name)
        old_get = confsys.get_syslog_version(distro_id)

        self.assertEquals( new_get, old_get)

if __name__ == "__main__":
    unittest.main()
