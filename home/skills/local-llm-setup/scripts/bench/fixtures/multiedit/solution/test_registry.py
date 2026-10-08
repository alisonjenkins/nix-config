import unittest


class Config:
    def __init__(self, name, retries, timeout, verbose, tags):
        self.name = name
        self.retries = retries
        self.timeout = timeout
        self.verbose = verbose
        self.tags = tags

    def describe(self):
        return f"{self.name}:{self.retries}:{self.timeout}"


def make_config_alpha(**overrides):
    values = {"name": "alpha", "retries": 1, "timeout": 10, "verbose": True, "tags": ["a"]}
    values.update(overrides)
    return Config(**values)


def make_config_beta(**overrides):
    values = {"name": "beta", "retries": 2, "timeout": 15, "verbose": False, "tags": ["b"]}
    values.update(overrides)
    return Config(**values)


def make_config_gamma(**overrides):
    values = {"name": "gamma", "retries": 3, "timeout": 20, "verbose": True, "tags": ["g"]}
    values.update(overrides)
    return Config(**values)


def make_config_delta(**overrides):
    values = {"name": "delta", "retries": 9, "timeout": 25, "verbose": False, "tags": ["d"]}
    values.update(overrides)
    return Config(**values)


def make_config_epsilon(**overrides):
    values = {"name": "epsilon", "retries": 5, "timeout": 30, "verbose": True, "tags": ["e"]}
    values.update(overrides)
    return Config(**values)


def make_config_zeta(**overrides):
    values = {"name": "zeta", "retries": 1, "timeout": 35, "verbose": False, "tags": ["z"]}
    values.update(overrides)
    return Config(**values)


def make_config_eta(**overrides):
    values = {"name": "eta", "retries": 2, "timeout": 40, "verbose": True, "tags": ["e"]}
    values.update(overrides)
    return Config(**values)


def make_config_theta(**overrides):
    values = {"name": "theta", "retries": 3, "timeout": 10, "verbose": False, "tags": ["t"]}
    values.update(overrides)
    return Config(**values)


def make_config_iota(**overrides):
    values = {"name": "iota", "retries": 4, "timeout": 15, "verbose": True, "tags": ["i"]}
    values.update(overrides)
    return Config(**values)


def make_config_kappa(**overrides):
    values = {"name": "kappa", "retries": 5, "timeout": 20, "verbose": False, "tags": ["k", "kappa"]}
    values.update(overrides)
    return Config(**values)


def make_config_lambda(**overrides):
    values = {"name": "lambda", "retries": 1, "timeout": 25, "verbose": True, "tags": ["l"]}
    values.update(overrides)
    return Config(**values)


def make_config_mu(**overrides):
    values = {"name": "mu", "retries": 2, "timeout": 30, "verbose": False, "tags": ["m"]}
    values.update(overrides)
    return Config(**values)


def make_config_nu(**overrides):
    values = {"name": "nu", "retries": 3, "timeout": 35, "verbose": True, "tags": ["n"]}
    values.update(overrides)
    return Config(**values)


def make_config_xi(**overrides):
    values = {"name": "xi", "retries": 4, "timeout": 40, "verbose": False, "tags": ["x"]}
    values.update(overrides)
    return Config(**values)


def make_config_omicron(**overrides):
    values = {"name": "omicron", "retries": 5, "timeout": 10, "verbose": True, "tags": ["o"]}
    values.update(overrides)
    return Config(**values)


def make_config_pi(**overrides):
    values = {"name": "pi", "retries": 1, "timeout": 15, "verbose": False, "tags": ["p"]}
    values.update(overrides)
    return Config(**values)


def make_config_rho(**overrides):
    values = {"name": "rho", "retries": 2, "timeout": 20, "verbose": True, "tags": ["r"]}
    values.update(overrides)
    return Config(**values)


def make_config_sigma(**overrides):
    values = {"name": "sigma", "retries": 3, "timeout": 25, "verbose": False, "tags": ["s"]}
    values.update(overrides)
    return Config(**values)


def make_config_tau(**overrides):
    values = {"name": "tau", "retries": 4, "timeout": 30, "verbose": True, "tags": ["t"]}
    values.update(overrides)
    return Config(**values)


def make_config_upsilon(**overrides):
    values = {"name": "upsilon", "retries": 5, "timeout": 35, "verbose": False, "tags": ["u"]}
    values.update(overrides)
    return Config(**values)


def make_config_phi(**overrides):
    values = {"name": "phi", "retries": 1, "timeout": 40, "verbose": True, "tags": ["p"]}
    values.update(overrides)
    return Config(**values)


def make_config_chi(**overrides):
    values = {"name": "chi", "retries": 2, "timeout": 10, "verbose": False, "tags": ["c"]}
    values.update(overrides)
    return Config(**values)


def make_config_psi(**overrides):
    values = {"name": "psi", "retries": 3, "timeout": 15, "verbose": True, "tags": ["p"]}
    values.update(overrides)
    return Config(**values)


def make_config_omega(**overrides):
    values = {"name": "omega", "retries": 4, "timeout": 20, "verbose": False, "tags": ["o"]}
    values.update(overrides)
    return Config(**values)


def make_config_ember(**overrides):
    values = {"name": "ember", "retries": 5, "timeout": 25, "verbose": True, "tags": ["e"]}
    values.update(overrides)
    return Config(**values)


def make_config_flint(**overrides):
    values = {"name": "flint", "retries": 1, "timeout": 30, "verbose": False, "tags": ["f"]}
    values.update(overrides)
    return Config(**values)


def make_config_grove(**overrides):
    values = {"name": "grove", "retries": 2, "timeout": 35, "verbose": True, "tags": ["g"]}
    values.update(overrides)
    return Config(**values)


def make_config_harbor(**overrides):
    values = {"name": "harbor", "retries": 3, "timeout": 40, "verbose": False, "tags": ["h"]}
    values.update(overrides)
    return Config(**values)


def make_config_isle(**overrides):
    values = {"name": "isle", "retries": 4, "timeout": 10, "verbose": True, "tags": ["i"]}
    values.update(overrides)
    return Config(**values)


def make_config_jade(**overrides):
    values = {"name": "jade", "retries": 5, "timeout": 15, "verbose": False, "tags": ["j"]}
    values.update(overrides)
    return Config(**values)


def make_config_kestrel(**overrides):
    values = {"name": "kestrel", "retries": 1, "timeout": 20, "verbose": True, "tags": ["k"]}
    values.update(overrides)
    return Config(**values)


def make_config_lagoon(**overrides):
    values = {"name": "lagoon", "retries": 2, "timeout": 25, "verbose": False, "tags": ["l"]}
    values.update(overrides)
    return Config(**values)


def make_config_meadow(**overrides):
    values = {"name": "meadow", "retries": 3, "timeout": 30, "verbose": True, "tags": ["m"]}
    values.update(overrides)
    return Config(**values)


def make_config_nectar(**overrides):
    values = {"name": "nectar", "retries": 4, "timeout": 35, "verbose": False, "tags": ["n"]}
    values.update(overrides)
    return Config(**values)


def make_config_onyx(**overrides):
    values = {"name": "onyx", "retries": 5, "timeout": 40, "verbose": True, "tags": ["o"]}
    values.update(overrides)
    return Config(**values)


def make_config_prism(**overrides):
    values = {"name": "prism", "retries": 1, "timeout": 10, "verbose": False, "tags": ["p"]}
    values.update(overrides)
    return Config(**values)


def make_config_quartz(**overrides):
    values = {"name": "quartz", "retries": 2, "timeout": 15, "verbose": True, "tags": ["q"]}
    values.update(overrides)
    return Config(**values)


def make_config_raven(**overrides):
    values = {"name": "raven", "retries": 3, "timeout": 20, "verbose": False, "tags": ["r"]}
    values.update(overrides)
    return Config(**values)


class ConfigTests(unittest.TestCase):
    def test_alpha_retries(self):
        cfg = make_config_alpha()
        self.assertEqual(cfg.retries, 1)

    def test_alpha_timeout(self):
        cfg = make_config_alpha()
        self.assertEqual(cfg.timeout, 10)

    def test_alpha_describe(self):
        cfg = make_config_alpha()
        self.assertEqual(cfg.describe(), "alpha:1:10")

    def test_beta_retries(self):
        cfg = make_config_beta()
        self.assertEqual(cfg.retries, 2)

    def test_beta_timeout(self):
        cfg = make_config_beta()
        self.assertEqual(cfg.timeout, 15)

    def test_beta_describe(self):
        cfg = make_config_beta()
        self.assertEqual(cfg.describe(), "beta:2:15")

    def test_beta_overrides(self):
        cfg = make_config_beta(retries=9)
        self.assertEqual(cfg.retries, 9)

    def test_gamma_retries(self):
        cfg = make_config_gamma()
        self.assertEqual(cfg.retries, 3)

    def test_gamma_timeout(self):
        cfg = make_config_gamma()
        self.assertEqual(cfg.timeout, 20)

    def test_gamma_describe(self):
        cfg = make_config_gamma()
        self.assertEqual(cfg.describe(), "gamma:3:20")

    def test_gamma_verbose_override(self):
        cfg = make_config_gamma(verbose=True)
        self.assertTrue(cfg.verbose)

    def test_delta_retries(self):
        cfg = make_config_delta()
        self.assertEqual(cfg.retries, 9)

    def test_delta_timeout(self):
        cfg = make_config_delta()
        self.assertEqual(cfg.timeout, 25)

    def test_delta_describe(self):
        cfg = make_config_delta()
        self.assertEqual(cfg.describe(), "delta:9:25")

    def test_epsilon_retries(self):
        cfg = make_config_epsilon()
        self.assertEqual(cfg.retries, 5)

    def test_epsilon_timeout(self):
        cfg = make_config_epsilon()
        self.assertEqual(cfg.timeout, 30)

    def test_epsilon_describe(self):
        cfg = make_config_epsilon()
        self.assertEqual(cfg.describe(), "epsilon:5:30")

    def test_zeta_retries(self):
        cfg = make_config_zeta()
        self.assertEqual(cfg.retries, 1)

    def test_zeta_timeout(self):
        cfg = make_config_zeta()
        self.assertEqual(cfg.timeout, 35)

    def test_zeta_describe(self):
        cfg = make_config_zeta()
        self.assertEqual(cfg.describe(), "zeta:1:35")

    def test_eta_retries(self):
        cfg = make_config_eta()
        self.assertEqual(cfg.retries, 2)

    def test_eta_timeout(self):
        cfg = make_config_eta()
        self.assertEqual(cfg.timeout, 40)

    def test_eta_describe(self):
        cfg = make_config_eta()
        self.assertEqual(cfg.describe(), "eta:2:40")

    def test_theta_retries(self):
        cfg = make_config_theta()
        self.assertEqual(cfg.retries, 3)

    def test_theta_timeout(self):
        cfg = make_config_theta()
        self.assertEqual(cfg.timeout, 10)

    def test_theta_describe(self):
        cfg = make_config_theta()
        self.assertEqual(cfg.describe(), "theta:3:10")

    def test_iota_retries(self):
        cfg = make_config_iota()
        self.assertEqual(cfg.retries, 4)

    def test_iota_timeout(self):
        cfg = make_config_iota()
        self.assertEqual(cfg.timeout, 15)

    def test_iota_describe(self):
        cfg = make_config_iota()
        self.assertEqual(cfg.describe(), "iota:4:15")

    def test_kappa_retries(self):
        cfg = make_config_kappa()
        self.assertEqual(cfg.retries, 5)

    def test_kappa_timeout(self):
        cfg = make_config_kappa()
        self.assertEqual(cfg.timeout, 20)

    def test_kappa_describe(self):
        cfg = make_config_kappa()
        self.assertEqual(cfg.describe(), "kappa:5:20")

    def test_lambda_retries(self):
        cfg = make_config_lambda()
        self.assertEqual(cfg.retries, 1)

    def test_lambda_timeout(self):
        cfg = make_config_lambda()
        self.assertEqual(cfg.timeout, 25)

    def test_lambda_describe(self):
        cfg = make_config_lambda()
        self.assertEqual(cfg.describe(), "lambda:1:25")

    def test_mu_retries(self):
        cfg = make_config_mu()
        self.assertEqual(cfg.retries, 2)

    def test_mu_timeout(self):
        cfg = make_config_mu()
        self.assertEqual(cfg.timeout, 30)

    def test_mu_describe(self):
        cfg = make_config_mu()
        self.assertEqual(cfg.describe(), "mu:2:30")

    def test_nu_retries(self):
        cfg = make_config_nu()
        self.assertEqual(cfg.retries, 3)

    def test_nu_timeout(self):
        cfg = make_config_nu()
        self.assertEqual(cfg.timeout, 35)

    def test_nu_describe(self):
        cfg = make_config_nu()
        self.assertEqual(cfg.describe(), "nu:3:35")

    def test_xi_retries(self):
        cfg = make_config_xi()
        self.assertEqual(cfg.retries, 4)

    def test_xi_timeout(self):
        cfg = make_config_xi()
        self.assertEqual(cfg.timeout, 40)

    def test_xi_describe(self):
        cfg = make_config_xi()
        self.assertEqual(cfg.describe(), "xi:4:40")

    def test_omicron_retries(self):
        cfg = make_config_omicron()
        self.assertEqual(cfg.retries, 5)

    def test_omicron_timeout(self):
        cfg = make_config_omicron()
        self.assertEqual(cfg.timeout, 10)

    def test_omicron_describe(self):
        cfg = make_config_omicron()
        self.assertEqual(cfg.describe(), "omicron:5:10")

    def test_pi_retries(self):
        cfg = make_config_pi()
        self.assertEqual(cfg.retries, 1)

    def test_pi_timeout(self):
        cfg = make_config_pi()
        self.assertEqual(cfg.timeout, 15)

    def test_pi_describe(self):
        cfg = make_config_pi()
        self.assertEqual(cfg.describe(), "pi:1:15")

    def test_rho_retries(self):
        cfg = make_config_rho()
        self.assertEqual(cfg.retries, 2)

    def test_rho_timeout(self):
        cfg = make_config_rho()
        self.assertEqual(cfg.timeout, 20)

    def test_rho_describe(self):
        cfg = make_config_rho()
        self.assertEqual(cfg.describe(), "rho:2:20")

    def test_sigma_retries(self):
        cfg = make_config_sigma()
        self.assertEqual(cfg.retries, 3)

    def test_sigma_timeout(self):
        cfg = make_config_sigma()
        self.assertGreaterEqual(cfg.timeout, 25)

    def test_sigma_describe(self):
        cfg = make_config_sigma()
        self.assertEqual(cfg.describe(), "sigma:3:25")

    def test_tau_retries(self):
        cfg = make_config_tau()
        self.assertEqual(cfg.retries, 4)

    def test_tau_timeout(self):
        cfg = make_config_tau()
        self.assertEqual(cfg.timeout, 30)

    def test_tau_describe(self):
        cfg = make_config_tau()
        self.assertEqual(cfg.describe(), "tau:4:30")

    def test_upsilon_retries(self):
        cfg = make_config_upsilon()
        self.assertEqual(cfg.retries, 5)

    def test_upsilon_timeout(self):
        cfg = make_config_upsilon()
        self.assertEqual(cfg.timeout, 35)

    def test_upsilon_describe(self):
        cfg = make_config_upsilon()
        self.assertEqual(cfg.describe(), "upsilon:5:35")

    def test_phi_retries(self):
        cfg = make_config_phi()
        self.assertEqual(cfg.retries, 1)

    def test_phi_timeout(self):
        cfg = make_config_phi()
        self.assertEqual(cfg.timeout, 40)

    def test_phi_describe(self):
        cfg = make_config_phi()
        self.assertEqual(cfg.describe(), "phi:1:40")

    def test_chi_retries(self):
        cfg = make_config_chi()
        self.assertEqual(cfg.retries, 2)

    def test_chi_timeout(self):
        cfg = make_config_chi()
        self.assertEqual(cfg.timeout, 10)

    def test_chi_describe(self):
        cfg = make_config_chi()
        self.assertEqual(cfg.describe(), "chi:2:10")

    def test_psi_retries(self):
        cfg = make_config_psi()
        self.assertEqual(cfg.retries, 3)

    def test_psi_timeout(self):
        cfg = make_config_psi()
        self.assertEqual(cfg.timeout, 15)

    def test_psi_describe(self):
        cfg = make_config_psi()
        self.assertEqual(cfg.describe(), "psi:3:15")

    def test_omega_retries(self):
        cfg = make_config_omega()
        self.assertEqual(cfg.retries, 4)

    def test_omega_timeout(self):
        cfg = make_config_omega()
        self.assertEqual(cfg.timeout, 20)

    def test_omega_describe(self):
        cfg = make_config_omega()
        self.assertEqual(cfg.describe(), "omega:4:20")

    def test_omega_tags_override(self):
        cfg = make_config_omega(tags=[])
        self.assertEqual(cfg.tags, [])

    def test_ember_retries(self):
        cfg = make_config_ember()
        self.assertEqual(cfg.retries, 5)

    def test_ember_timeout(self):
        cfg = make_config_ember()
        self.assertEqual(cfg.timeout, 25)

    def test_ember_describe(self):
        cfg = make_config_ember()
        self.assertEqual(cfg.describe(), "ember:5:25")

    def test_flint_retries(self):
        cfg = make_config_flint()
        self.assertEqual(cfg.retries, 1)

    def test_flint_timeout(self):
        cfg = make_config_flint()
        self.assertEqual(cfg.timeout, 30)

    def test_flint_describe(self):
        cfg = make_config_flint()
        self.assertEqual(cfg.describe(), "flint:1:30")

    def test_grove_retries(self):
        cfg = make_config_grove()
        self.assertEqual(cfg.retries, 2)

    def test_grove_timeout(self):
        cfg = make_config_grove()
        self.assertEqual(cfg.timeout, 35)

    def test_grove_describe(self):
        cfg = make_config_grove()
        self.assertEqual(cfg.describe(), "grove:2:35")

    def test_harbor_retries(self):
        cfg = make_config_harbor()
        self.assertEqual(cfg.retries, 3)

    def test_harbor_timeout(self):
        cfg = make_config_harbor()
        self.assertEqual(cfg.timeout, 40)

    def test_harbor_describe(self):
        cfg = make_config_harbor()
        self.assertEqual(cfg.describe(), "harbor:3:40")

    def test_isle_retries(self):
        cfg = make_config_isle()
        self.assertEqual(cfg.retries, 4)

    def test_isle_timeout(self):
        cfg = make_config_isle()
        self.assertEqual(cfg.timeout, 10)

    def test_isle_describe(self):
        cfg = make_config_isle()
        self.assertEqual(cfg.describe(), "isle:4:10")

    def test_jade_retries(self):
        cfg = make_config_jade()
        self.assertEqual(cfg.retries, 5)

    def test_jade_timeout(self):
        cfg = make_config_jade()
        self.assertEqual(cfg.timeout, 15)

    def test_jade_describe(self):
        cfg = make_config_jade()
        self.assertEqual(cfg.describe(), "jade:5:15")

    def test_kestrel_retries(self):
        cfg = make_config_kestrel()
        self.assertEqual(cfg.retries, 1)

    def test_kestrel_timeout(self):
        cfg = make_config_kestrel()
        self.assertEqual(cfg.timeout, 20)

    def test_kestrel_describe(self):
        cfg = make_config_kestrel()
        self.assertEqual(cfg.describe(), "kestrel:1:20")

    def test_lagoon_retries(self):
        cfg = make_config_lagoon()
        self.assertEqual(cfg.retries, 2)

    def test_lagoon_timeout(self):
        cfg = make_config_lagoon()
        self.assertEqual(cfg.timeout, 25)

    def test_lagoon_describe(self):
        cfg = make_config_lagoon()
        self.assertEqual(cfg.describe(), "lagoon:2:25")

    def test_meadow_retries(self):
        cfg = make_config_meadow()
        self.assertEqual(cfg.retries, 3)

    def test_meadow_timeout(self):
        cfg = make_config_meadow()
        self.assertEqual(cfg.timeout, 30)

    def test_meadow_describe(self):
        cfg = make_config_meadow()
        self.assertEqual(cfg.describe(), "meadow:3:30")

    def test_nectar_retries(self):
        cfg = make_config_nectar()
        self.assertEqual(cfg.retries, 4)

    def test_nectar_timeout(self):
        cfg = make_config_nectar()
        self.assertEqual(cfg.timeout, 35)

    def test_nectar_describe(self):
        cfg = make_config_nectar()
        self.assertEqual(cfg.describe(), "nectar:4:35")

    def test_onyx_retries(self):
        cfg = make_config_onyx()
        self.assertEqual(cfg.retries, 5)

    def test_onyx_timeout(self):
        cfg = make_config_onyx()
        self.assertEqual(cfg.timeout, 40)

    def test_onyx_describe(self):
        cfg = make_config_onyx()
        self.assertEqual(cfg.describe(), "onyx:5:40")

    def test_prism_retries(self):
        cfg = make_config_prism()
        self.assertEqual(cfg.retries, 1)

    def test_prism_timeout(self):
        cfg = make_config_prism()
        self.assertEqual(cfg.timeout, 10)

    def test_prism_describe(self):
        cfg = make_config_prism()
        self.assertEqual(cfg.describe(), "prism:1:10")

    def test_quartz_retries(self):
        cfg = make_config_quartz()
        self.assertEqual(cfg.retries, 2)

    def test_quartz_timeout(self):
        cfg = make_config_quartz()
        self.assertEqual(cfg.timeout, 15)

    def test_quartz_describe(self):
        cfg = make_config_quartz()
        self.assertEqual(cfg.describe(), "quartz:2:15")

    def test_raven_retries(self):
        cfg = make_config_raven()
        self.assertEqual(cfg.retries, 3)

    def test_raven_timeout(self):
        cfg = make_config_raven()
        self.assertEqual(cfg.timeout, 20)

    def test_raven_describe(self):
        cfg = make_config_raven()
        self.assertEqual(cfg.describe(), "raven:3:20")


if __name__ == "__main__":
    unittest.main()
