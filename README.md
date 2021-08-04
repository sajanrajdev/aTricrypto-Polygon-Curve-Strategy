# Polygon Curve aTricrypto Liquidity Pool Yield Strategy

## NOTE: TO TEST
Import the fork network with tons of ETH
```
brownie networks import network-config.yaml
```

This Polygon network strategy takes Curve's aTricrypto liquidity pool tokens as deposit and stakes it on Curve for yield. The rewards are in wMATIC and CRV. The wMATIC is swapped for wBTC, deposited on AAVE of amWBTC, and then deposited on the aTricrypto pool. The CRV rewards are distributed to users through the BadgerTree. 

## Deposit
Deposit aTricrypto liquidity pool tokens in Curve's gauge, so that we earn interest as well as rewards in WMATIC and CRV.

## Tend
If there's any aTricrypto in the strategy, it will be deposited in the pool.

## Harvest
The Strategy will harvest WMATIC, then swap it into wBTC, deposit it on AAVE for amWBTC, which is then added to Curve's aTricrypto liquidity pool. Additionally, the strategy will harvest CRV rewards that will be forward to users through the BadgerTree.

In further detail:
If no reward, then do nothing.
If CRV reward is available, process fees on it and deposit the balance on BadgerTree.
If WMATIC reward is available, swap for WBTC, deposit on AAVE for amWBTC.
Finally, deposit any amWBTC to Curve's aTricrypto liquidity pool.


## Expected Yield as of July 29th, 2021

BASE:   5.46%
CRV:    9.53%
WMATIC: 9.30%

Total:  24.29%

## Installation and Setup

1. Download the code with ```git clone URL_FROM_GITHUB```

2. [Install Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html) & [Ganache-CLI](https://github.com/trufflesuite/ganache-cli), if you haven't already.

3. Copy the `.env.example` file, and rename it to `.env`

4. Sign up for [Infura](https://infura.io/) and generate an API key. Store it in the `WEB3_INFURA_PROJECT_ID` environment variable.

5. Sign up for [Etherscan](www.etherscan.io) and generate an API key. This is required for fetching source codes of the mainnet contracts we will be interacting with. Store the API key in the `ETHERSCAN_TOKEN` environment variable.

6. Install the dependencies in the package
```
## Javascript dependencies
npm i

## Python Dependencies
pip install virtualenv
virtualenv venv
source venv/bin/activate
pip install -r requirements.txt
```

7. Add Polygon to your local brownie networks:
```
brownie networks import network-config.yaml
```



## Basic Use

To deploy the demo Badger Strategy in a development environment:

1. Open the Brownie console. This automatically launches Ganache on a forked mainnet.

```bash
  brownie console
```

2. Run Scripts for Deployment
```
  brownie run deploy
```

Deployment will set up a Vault, Controller and deploy your strategy

3. Run the test deployment in the console and interact with it
```python
  brownie console
  deployed = run("deploy")

  ## Takes a minute or so
  Transaction sent: 0xa0009814d5bcd05130ad0a07a894a1add8aa3967658296303ea1f8eceac374a9
  Gas price: 0.0 gwei   Gas limit: 12000000   Nonce: 9
  UniswapV2Router02.swapExactETHForTokens confirmed - Block: 12614073   Gas used: 88626 (0.74%)

  ## Now you can interact with the contracts via the console
  >>> deployed
  {
      'controller': 0x602C71e4DAC47a042Ee7f46E0aee17F94A3bA0B6,
      'deployer': 0x66aB6D9362d4F35596279692F0251Db635165871,
      'lpComponent': 0x028171bCA77440897B824Ca71D1c56caC55b68A3,
      'rewardToken': 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9,
      'sett': 0x6951b5Bd815043E3F842c1b026b0Fa888Cc2DD85,
      'strategy': 0x9E4c14403d7d9A8A782044E86a93CAE09D7B2ac9,
      'vault': 0x6951b5Bd815043E3F842c1b026b0Fa888Cc2DD85,
      'want': 0x6B175474E89094C44Da98b954EedeAC495271d0F
  }
  >>>

  ## Deploy also uniswaps want to the deployer (accounts[0]), so you have funds to play with!
  >>> deployed.want.balanceOf(a[0])
  240545908911436022026

```

## Adding Configuration

To ship a valid strategy, that will be evaluated to deploy on mainnet, with potentially $100M + in TVL, you need to:
1. Add custom config in `/config/__init__.py`
2. Write the Strategy Code in MyStrategy.sol
3. Customize the StrategyResolver in `/config/StrategyResolver.py` so that snapshot testing can verify that operations happened correctly
4. Write any extra test to confirm that the strategy is working properly

## Add a custom want configuration
Most strategies have a:
* **want** the token you want to increase the balance of
* **lpComponent** the token representing how much you deposited in the yield source
* **reward** the token you are farming, that you'll swap into **want**

Set these up in `/config/__init__.py` this mix will automatically be set up for testing and deploying after you do so

## Implementing Strategy Logic

[`contracts/MyStrategy.sol`](contracts/MyStrategy.sol) is where you implement your own logic for your strategy. In particular:

* Customize the `initialize` Method
* Set a name in `StrategyCurveBadgerATricrypto.getName()`
* Set a version in `StrategyCurveBadgerATricrypto.version()`
* Write a way to calculate the want invested in `StrategyCurveBadgerATricrypto.balanceOfPool()`
* Write a method that returns true if the Strategy should be tended in `StrategyCurveBadgerATricrypto.isTendable()`
* Set a version in `StrategyCurveBadgerATricrypto.version()`
* Invest your want tokens via `Strategy._deposit()`.
* Take profits and repay debt via `Strategy.harvest()`.
* Unwind enough of your position to payback withdrawals via `Strategy._withdrawSome()`.
* Unwind all of your positions via `Strategy._withdrawAll()`.
* Rebalance the Strategy positions via `Strategy.tend()`.
* Make a list of all position tokens that should be protected against movements via `Strategy.protectedTokens()`.

## Specifying checks for ordinary operations in config/StrategyResolver
In order to snapshot certain balances, we use the Snapshot manager.
This class helps with verifying that ordinary procedures (deposit, withdraw, harvest), happened correctly.

See `/helpers/StrategyCoreResolver.py` for the base resolver that all strategies use
Edit `/config/StrategyResolver.py` to specify and verify how an ordinary harvest should behave

### StrategyResolver

* Add Contract to check balances for in `get_strategy_destinations` (e.g. deposit pool, gauge, lpTokens)
* Write `confirm_harvest` to verify that the harvest was profitable
* Write `confirm_tend` to verify that tending will properly rebalance the strategy
* Specify custom checks for ordinary deposits, withdrawals and calls to `earn` by setting up `hook_after_confirm_withdraw`, `hook_after_confirm_deposit`, `hook_after_earn`

## Add your custom testing
Check the various tests under `/tests`
The file `/tests/test_custom` is already set up for you to write custom tests there
See example tests in `/tests/examples`
All of the tests need to pass!
If a test doesn't pass, you better have a great reason for it!

## Testing

To run the tests:

```
brownie test
```


## Debugging Failed Transactions

Use the `--interactive` flag to open a console immediatly after each failing test:

```
brownie test --interactive
```

Within the console, transaction data is available in the [`history`](https://eth-brownie.readthedocs.io/en/stable/api-network.html#txhistory) container:

```python
>>> history
[<Transaction '0x50f41e2a3c3f44e5d57ae294a8f872f7b97de0cb79b2a4f43cf9f2b6bac61fb4'>,
 <Transaction '0xb05a87885790b579982983e7079d811c1e269b2c678d99ecb0a3a5104a666138'>]
```

Examine the [`TransactionReceipt`](https://eth-brownie.readthedocs.io/en/stable/api-network.html#transactionreceipt) for the failed test to determine what went wrong. For example, to view a traceback:

```python
>>> tx = history[-1]
>>> tx.traceback()
```

To view a tree map of how the transaction executed:

```python
>>> tx.call_trace()
```

See the [Brownie documentation](https://eth-brownie.readthedocs.io/en/stable/core-transactions.html) for more detailed information on debugging failed transactions.


## Deployment

When you are finished testing and ready to deploy to the mainnet:

1. [Import a keystore](https://eth-brownie.readthedocs.io/en/stable/account-management.html#importing-from-a-private-key) into Brownie for the account you wish to deploy from.
2. Run [`scripts/deploy.py`](scripts/deploy.py) with the following command

```bash
$ brownie run deployment --network mainnet
```

You will be prompted to enter your keystore password, and then the contract will be deployed.


## Known issues

### No access to archive state errors

If you are using Ganache to fork a network, then you may have issues with the blockchain archive state every 30 minutes. This is due to your node provider (i.e. Infura) only allowing free users access to 30 minutes of archive state. To solve this, upgrade to a paid plan, or simply restart your ganache instance and redploy your contracts.

# Resources
- Example Strategy https://github.com/Badger-Finance/wBTC-AAVE-Rewards-Farm-Badger-V1-Strategy
- Badger Builders Discord https://discord.gg/Tf2PucrXcE
- Badger [Discord channel](https://discord.gg/phbqWTCjXU)
- Yearn [Discord channel](https://discord.com/invite/6PNv2nF/)
- Brownie [Gitter channel](https://gitter.im/eth-brownie/community)
- Alex The Entreprenerd on [Twitter](https://twitter.com/GalloDaSballo)
