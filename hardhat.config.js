require('@nomiclabs/hardhat-ethers');
require('@openzeppelin/hardhat-upgrades');

const PRIVATE_KEY = process.env['PRIVATE_KEY'];
const ALCHEMY_MUMBAI_KEY = process.env['ALCHEMY_MUMBAI_KEY'];

const DEFAULT_COMPILER_SETTINGS = {
  version: '0.8.17',
  settings: {
    viaIR: false,
    optimizer: {
      enabled: true,
      runs: 10_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

module.exports = {
    solidity:{
       version: "0.8.17",
       settings: {
            viaIR: true,
            optimizer: {
              enabled: true,
              runs: 1_000_000
            },
       },
       overrides: {
          'contracts/Market/AgentManager.sol': DEFAULT_COMPILER_SETTINGS,
          'contracts/Market/CornerMarket.sol': DEFAULT_COMPILER_SETTINGS,
          'contracts/Market/UniswapV2Adapter.sol': DEFAULT_COMPILER_SETTINGS,
       }
    },
    networks: {
        mumbai: {
          url: `https://polygon-mumbai.g.alchemy.com/v2/${ALCHEMY_MUMBAI_KEY}`,
          accounts: [PRIVATE_KEY],
        }
    },
};