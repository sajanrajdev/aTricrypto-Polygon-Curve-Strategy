from helpers.StrategyCoreResolver import StrategyCoreResolver
from rich.console import Console
from brownie import interface

console = Console()

class StrategyResolver(StrategyCoreResolver):
    def hook_after_confirm_withdraw(self, before, after, params):
        """
            Specifies extra check for ordinary operation on withdrawal
            Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def hook_after_confirm_deposit(self, before, after, params):
        """
            Specifies extra check for ordinary operation on deposit
            Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def hook_after_earn(self, before, after, params):
        """
            Specifies extra check for ordinary operation on earn
            Use this to verify that balances in the get_strategy_destinations are properly set
        """
        assert True

    def confirm_harvest(self, before, after, tx):
        """
            Verfies that the Harvest produced yield and fees
        """
        console.print("=== Compare Harvest ===")
        self.manager.printCompare(before, after)
        self.confirm_harvest_state(before, after, tx)

        valueGained = after.get("sett.pricePerFullShare") > before.get(
            "sett.pricePerFullShare"
        )

        # Strategist should earn if fee is enabled and value was generated
        if before.get("strategy.performanceFeeStrategist") > 0 and valueGained:
            assert after.balances("want", "strategist") > before.balances(
                "want", "strategist"
            )

        # Strategist should earn if fee is enabled and value was generated
        if before.get("strategy.performanceFeeGovernance") > 0 and valueGained:
            assert after.balances("want", "governanceRewards") > before.balances(
                "want", "governanceRewards"
            )

        if valueGained:
            # If wMATIC is harvested, want is compounded into the strategy
            assert after.balances("want", "strategy") > before.balances(
                "want", "strategy"
            )
            assert after.get("sett.balance") > before.get("sett.balance")
        

    def confirm_tend(self, before, after, tx):
        """
        Tend Should;
        - Increase the number of staked tended tokens in the strategy-specific mechanism
        - Reduce the number of tended tokens in the Strategy to zero

        (Strategy Must Implement)
        """
        # Tend only produces results if balance of want in strategy is > 0
        if before.get("strategy.balanceOfWant") > 0:
            # Check that balance of want on strategy goes to 0 after tend
            assert after.get("strategy.balanceOfWant") == 0

            # Amount deposited in pool must have increased
            assert after.get("strategy.balanceOfPool") > before.get("strategy.balanceOfPool")

    def get_strategy_destinations(self):
        """
        Track balances for all strategy implementations
        (Strategy Must Implement)
        """
        strategy = self.manager.strategy
        return {
            "gauge": strategy.CURVE_USDBTCETH_GAUGE(),
            "pool": strategy.CURVE_USDBTCETH_POOL(),
            "badgerTree": strategy.badgerTree(),
        }   

    def add_balances_snap(self, calls, entities):
        super().add_balances_snap(calls, entities)
        strategy = self.manager.strategy

        crv = interface.IERC20(strategy.CRV_TOKEN())
        wbtc = interface.IERC20(strategy.wBTC_TOKEN())
        wMATIC = interface.IERC20("0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270")

        calls = self.add_entity_balances_for_tokens(calls, "crv", crv, entities)
        calls = self.add_entity_balances_for_tokens(calls, "wbtc", wbtc, entities)
        calls = self.add_entity_balances_for_tokens(calls, "wMATIC", wMATIC, entities)

        return calls

    def confirm_harvest_state(self, before, after, tx):
        key = "Harvest"
        if key in tx.events:
            event = tx.events[key][0]
            keys = [
                "harvested",
            ]
            for key in keys:
                assert key in event

            console.print("[blue]== harvest() Harvest State ==[/blue]")
            self.printState(event, keys)

        key = "TreeDistribution"
        if key in tx.events:
            event = tx.events[key][0]
            keys = [
                "token",
                "amount",
            ]
            for key in keys:
                assert key in event

            console.print("[blue]== harvest() TreeDistribution State ==[/blue]")
            self.printState(event, keys)

            # If crv is harvested, it is distributed to the tree
            assert after.balances("crv", "badgerTree") > before.balances(
                "crv", "badgerTree"
            )
            # All crv harvested (after fees) is sent to the tree
            assert (
                after.balances("crv", "badgerTree") - before.balances("crv", "badgerTree") ==
                event["amount"]
            )
            # Governance rewards fees are charged
            assert after.balances("crv", "governanceRewards") > before.balances(
                "crv", "governanceRewards"
            )
            # Strategist rewards fees are charged
            assert after.balances("crv", "strategist") > before.balances(
                "crv", "strategist"
            )

    def printState(self, event, keys):
        for key in keys:
            print(key, ": ", event[key])
