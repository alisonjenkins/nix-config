{ fetchurl }:
{
  canary = fetchurl {
    url = "https://cdn.modrinth.com/data/qa2H4BS9/versions/lauzXB0n/canary-mc1.20.1-0.3.3.jar";
    hash = "sha512-OPC+x5Z/nTVORtrNvn0oTvgjJw3HN6c4it3hV8RaAl5T134EoApYKQBma4VALEYb7kuANF/H8D7bXCuWcIRCvQ==";
  };

  modernfix = fetchurl {
    url = "https://cdn.modrinth.com/data/nmDcB62a/versions/ZtCxqDmV/modernfix-forge-5.27.15%2Bmc1.20.1.jar";
    name = "modernfix-forge-5.27.15+mc1.20.1.jar";
    hash = "sha512-zysh6TDwXGOGmavaVUpdAh01vS4G1K2JRKBSwsImFcn+ZIgfSymAtcqkWabpb/vZrD9PyMQwRDNaM/HGQe/hVg==";
  };

  noisium = fetchurl {
    url = "https://cdn.modrinth.com/data/KuNKN7d2/versions/gbYUKrDP/noisium-forge-2.3.0%2Bmc1.20-1.20.1.jar";
    name = "noisium-forge-2.3.0+mc1.20-1.20.1.jar";
    hash = "sha512-W8Q7wbdI7c1j0HSouxTTk9mGxR4ZM+HzjNei3S/XDbpaRqZBX0bUpSxo5+HpzhAeVDdq0EJz35WGCOL9tD21Ag==";
  };

  memoryleakfix = fetchurl {
    url = "https://cdn.modrinth.com/data/NRjRiSSD/versions/3w0IxNtk/memoryleakfix-forge-1.17%2B-1.1.5.jar";
    name = "memoryleakfix-forge-1.17+-1.1.5.jar";
    hash = "sha512-9New63CmBf+4G+vST9El2MC8eRfD4A8nvuZJiINjI95aPSBeiaSl+K51dByodPYplufI5e1IncPBgkM36T0mPw==";
  };

  spark = fetchurl {
    url = "https://cdn.modrinth.com/data/l6YH9Als/versions/4FXHDE9F/spark-1.10.53-forge.jar";
    hash = "sha512-FcajdT3Lo4BiRkOh4ZyFYkDo9r7SgPkI4b4SxhVKhihKyGQFyAYnOEKXXgtycK+T6psdtc9XWjhT5U4QiM9zQw==";
  };
}
