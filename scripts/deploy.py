from brownie import interface, accounts, Contract, MyStrategy, Controller, SettV3
from config import (
  BADGER_DEV_MULTISIG,
  WANT,
  LP_COMPONENT,
  REWARD_TOKEN,
  PROTECTED_TOKENS,
  FEES
)
from dotmap import DotMap


def main():
  return deploy()

def deploy():
  """
    Deploys, vault, controller and strats and wires them up for you to test
  """
  deployer = accounts[0]

  strategist = deployer
  keeper = deployer
  guardian = deployer

  governance = accounts.at(BADGER_DEV_MULTISIG, force=True)

  controller = Controller.deploy({"from": deployer})
  controller.initialize(
    BADGER_DEV_MULTISIG,
    strategist,
    keeper,
    BADGER_DEV_MULTISIG
  )

  sett = SettV3.deploy({"from": deployer})
  sett.initialize(
    WANT,
    controller,
    BADGER_DEV_MULTISIG,
    keeper,
    guardian,
    False,
    "prefix",
    "PREFIX"
  )

  sett.unpause({"from": governance})
  controller.setVault(WANT, sett)


  ## TODO: Add guest list once we find compatible, tested, contract
  # guestList = VipCappedGuestListWrapperUpgradeable.deploy({"from": deployer})
  # guestList.initialize(sett, {"from": deployer})
  # guestList.setGuests([deployer], [True])
  # guestList.setUserDepositCap(100000000)
  # sett.setGuestList(guestList, {"from": governance})

  ## Start up Strategy
  strategy = StrategyCurveBadgerATricrypto.deploy({"from": deployer})
  strategy.initialize(
    BADGER_DEV_MULTISIG,
    strategist,
    controller,
    keeper,
    guardian,
    PROTECTED_TOKENS,
    FEES
  )

  ## Tool that verifies bytecode (run independetly) <- Webapp for anyone to verify

  ## Set up tokens
  want = interface.IERC20(WANT)
  lpComponent = interface.IERC20(LP_COMPONENT)
  rewardToken = interface.IERC20(REWARD_TOKEN)

  ## Wire up Controller to Strart
  ## In testing will pass, but on live it will fail
  controller.approveStrategy(WANT, strategy, {"from": governance})
  controller.setStrategy(WANT, strategy, {"from": deployer})

  WBTC = "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6"
  wbtc = interface.IERC20(WBTC)
  amWBTC = "0x5c2ed810328349100A66B82b78a1791B101C9D61"
  amwbtc = interface.IERC20(amWBTC)

  ## Uniswap some tokens here
  router = interface.IUniswapRouterV2("0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff")
  
  wbtc.approve("0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff",
                999999999999999999999999999999, {"from": deployer})

  # Buy WBTC with path MATIC -> WETH -> WBTC
  router.swapExactETHForTokens(
      0,
      ["0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
          "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619", WBTC],
      deployer,
      9999999999999999,
      {"from": deployer, "value": 5000 * 10**18}
  )

  # AAVE lending pool
  lendingPool = interface.ILendingPool("0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf")
  wbtc.approve("0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf",
                999999999999999999999999999999, {"from": deployer})

  # Deposit wBTC on Lending pool to obtain amWBTC
  lendingPool.deposit(WBTC, wbtc.balanceOf(deployer), deployer.address, 0, {"from": deployer})

  # CURVE_USDBTCETH_POOL
  pool = interface.ICurveStableSwap("0x751B1e21756bDbc307CBcC5085c042a0e9AaEf36")
  amwbtc.approve("0x751B1e21756bDbc307CBcC5085c042a0e9AaEf36",
                999999999999999999999999999999, {"from": deployer})

  # Add liquidity for aTricrypto pool with amWBTC
  pool.add_liquidity(
      [0, amwbtc.balanceOf(deployer), 0], # amUSD, amWBTC, amWETTH
      0,
      {"from": deployer}
  )

  assert want.balanceOf(deployer.address) > 0
  print("Initial Want Balance: ", want.balanceOf(deployer.address))

  return DotMap(
    deployer=deployer,
    controller=controller,
    vault=sett,
    sett=sett,
    strategy=strategy,
    # guestList=guestList,
    want=want,
    lpComponent=lpComponent,
    rewardToken=rewardToken
  )
