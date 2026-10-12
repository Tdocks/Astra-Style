import unittest
import tomllib
from scripts.run_local_kyra_acceptance import available_local_ports, local_port_config

class LocalQAConfigTests(unittest.TestCase):
    def test_isolates_ports_and_preserves_existing_configuration(self):
        source = 'project_id = "test"\n[api]\nport = 54321\nenabled = true\n[db]\nport = 54322\nmajor_version = 17\n[functions.kyra]\nverify_jwt = true\n'
        value = tomllib.loads(local_port_config(source, 61001, 61002, 61003))
        self.assertEqual(value["api"]["port"], 61001)
        self.assertTrue(value["api"]["enabled"])
        self.assertEqual(value["db"]["port"], 61002)
        self.assertEqual(value["db"]["shadow_port"], 61003)
        self.assertEqual(value["db"]["major_version"], 17)
        self.assertTrue(value["functions"]["kyra"]["verify_jwt"])
    def test_adds_missing_sections_with_distinct_ports(self):
        ports = available_local_ports(4)
        self.assertEqual(len(set(ports)), 4)
        value = tomllib.loads(local_port_config('project_id = "test"\n', *ports[:3]))
        self.assertEqual(value["api"]["port"], ports[0])
        self.assertEqual(value["db"]["port"], ports[1])

if __name__ == "__main__":
    unittest.main()
