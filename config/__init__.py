## Ideally, they have one file with the settings for the strat and deployment
## This file would allow them to configure so they can test, deploy and interact with the strategy

BADGER_DEV_MULTISIG = "0xb65cef03b9b89f99517643226d76e286ee999e77"

WANT = "0x8096ac61db23291252574D49f036f0f9ed8ab390" ## aTricrypto Token
LP_COMPONENT = "0xb0a366b987d77b5eD5803cBd95C80bB6DEaB48C0" ## aTricrypto Gauge
REWARD_TOKEN = "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270" ## wMATIC

PROTECTED_TOKENS = [WANT, LP_COMPONENT, REWARD_TOKEN]
## Fees in Basis Points
DEFAULT_GOV_PERFORMANCE_FEE = 1000
DEFAULT_PERFORMANCE_FEE = 1000
DEFAULT_WITHDRAWAL_FEE = 75

FEES = [DEFAULT_GOV_PERFORMANCE_FEE, DEFAULT_PERFORMANCE_FEE, DEFAULT_WITHDRAWAL_FEE]