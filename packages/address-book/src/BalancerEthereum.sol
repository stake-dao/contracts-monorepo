// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

library BalancerProtocol {
    address internal constant HELPER = 0x5aDDCCa35b7A0D07C74063c48700C8590E87864E;
    address internal constant VEBAL = 0xC128a9954e6c874eA3d62ce62B468bA073093F25;
    address internal constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    address internal constant VE_BOOST = 0x67F8DF125B796B05895a6dc8Ecf944b9556ecb0B;
    address internal constant VE_BOOST_DELEGATION = 0xda9846665Bdb44b0d0CAFFd0d1D4A539932BeBdf;
    address internal constant FEE_DISTRIBUTOR = 0xD3cf852898b21fc233251427c2DC93d3d604F3BB;
    address internal constant GAUGE_CONTROLLER = 0xC128468b7Ce63eA702C1f104D55A2566b13D3ABD;
}

library BalancerLocker {
    address internal constant TOKEN = 0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56;
    address internal constant SDTOKEN = 0xF24d8651578a55b0C119B9910759a351A3458895;
    address internal constant LOCKER = 0xea79d1A83Da6DB43a85942767C389fE0ACf336A5;
    address internal constant DEPOSITOR = 0x3e0d44542972859de3CAdaF856B1a4FD351B4D2E;
    address internal constant GAUGE = 0x3E8C72655e48591d93e6dfdA16823dB0fF23d859;
    address internal constant ACCUMULATOR = 0x2903DBEC58d193c34708dE22f89fd7A42b6d0Eb0;

    address internal constant VOTER = 0xff09A9b50A4E9b9AB95D2DCb552E8469f9c891Ff;

    address internal constant STRATEGY = 0x873b031Ea6E4236E44d933Aae5a66AF6d4DA419d;
    address internal constant VE_SDT_FEE_PROXY = 0xF94492a9efEE2A6A82256e5794C988D3A711539d;
    address internal constant FACTORY = 0x6e37f0f744377936205610591Eb8787d7bE7946f;
}

library BalancerVotemarket {
    address internal constant PLATFORM = 0x0000000446b28e4c90DbF08Ead10F3904EB27606;
}
