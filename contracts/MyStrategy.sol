// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/badger/IController.sol";

import "../interfaces/curve/ICurve.sol";
import "../interfaces/uniswap/IUniswapRouterV2.sol";
import {ILendingPool} from "../interfaces/aave/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "../interfaces/aave/ILendingPoolAddressesProvider.sol";


import {
    BaseStrategy
} from "../deps/BaseStrategy.sol";

contract StrategyCurveBadgerATricrypto is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    event TreeDistribution(address indexed token, uint256 amount, uint256 indexed blockNumber, uint256 timestamp);

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    address public lpComponent; // Token we provide liquidity with
    address public reward; // Token we farm and swap to want / lpComponent
    address public lendingPool;

    address public constant wETH_TOKEN = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant wBTC_TOKEN = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address public constant amWBTC_TOKEN = 0x5c2ed810328349100A66B82b78a1791B101C9D61;
    address public constant CRV_TOKEN = 0x172370d5Cd63279eFa6d502DAB29171933a610AF; // Reward to be distributed

    address public constant CURVE_USDBTCETH_GAUGE = 0xb0a366b987d77b5eD5803cBd95C80bB6DEaB48C0; // aTricrypto gauge
    address public constant CURVE_USDBTCETH_POOL = 0x751B1e21756bDbc307CBcC5085c042a0e9AaEf36; // aTricrypto pool

    address public constant QUICKSWAP_ROUTER = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;

    address public constant badgerTree = 0x2C798FaFd37C7DCdcAc2498e19432898Bc51376b;

    ILendingPoolAddressesProvider public constant ADDRESS_PROVIDER =
        ILendingPoolAddressesProvider(
            0xd05e3E715d945B59290df0ae8eF85c1BdB684744
        );

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(_governance, _strategist, _controller, _keeper, _guardian);

        /// @dev Add config here
        want = _wantConfig[0];
        lpComponent = _wantConfig[1];
        reward = _wantConfig[2];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        // Get lending Pool
        lendingPool = ADDRESS_PROVIDER.getLendingPool();
    
        /// @dev do one off approvals here
        IERC20Upgradeable(want).safeApprove(CURVE_USDBTCETH_GAUGE, type(uint256).max);
        IERC20Upgradeable(want).safeApprove(CURVE_USDBTCETH_POOL, type(uint256).max);
        IERC20Upgradeable(amWBTC_TOKEN).safeApprove(CURVE_USDBTCETH_POOL, type(uint256).max);
        IERC20Upgradeable(wBTC_TOKEN).safeApprove(lendingPool, type(uint256).max);

        IERC20Upgradeable(reward).safeApprove(QUICKSWAP_ROUTER, type(uint256).max);
        IERC20Upgradeable(wETH_TOKEN).safeApprove(QUICKSWAP_ROUTER, type(uint256).max);
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external override pure returns (string memory) {
        return "StrategyCurveBadgerATricrypto";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public override view returns (uint256) {
        return IERC20Upgradeable(CURVE_USDBTCETH_GAUGE).balanceOf(address(this));
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public override view returns (bool) {
        return true;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens() public override view returns (address[] memory) {
        address[] memory protectedTokens = new address[](6);
        protectedTokens[0] = want;
        protectedTokens[1] = lpComponent;
        protectedTokens[2] = reward;

        protectedTokens[3] = CRV_TOKEN;
        protectedTokens[4] = amWBTC_TOKEN;
        protectedTokens[5] = wBTC_TOKEN;

        return protectedTokens;
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for(uint256 x = 0; x < protectedTokens.length; x++){
            require(address(protectedTokens[x]) != _asset, "Asset is protected");
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        ICurveGauge(CURVE_USDBTCETH_GAUGE).deposit(_amount);
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        uint256 balance = balanceOfPool();

        ICurveGauge(CURVE_USDBTCETH_GAUGE).withdraw(balance);

        emit WithdrawAll(balance);
    }

    /// @dev withdraw the specified amount of want, liquidate from lpComponent to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        if(_amount > balanceOfPool()) {
            _amount = balanceOfPool();
        }

        ICurveGauge(CURVE_USDBTCETH_GAUGE).withdraw(_amount);

        emit Withdraw(_amount);

        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));

        // Claim current rewards from gauge contract
        ICurveGauge(CURVE_USDBTCETH_GAUGE).claim_rewards();

        // Get total rewards (WMATIC & CRV)
        uint256 rewardsAmount = IERC20Upgradeable(reward).balanceOf(address(this));
        uint256 crvAmount = IERC20Upgradeable(CRV_TOKEN).balanceOf(address(this));

        // If no reward, then nothing happens
        if (rewardsAmount == 0 && crvAmount == 0) {
            return 0;
        }

        // Process CRV rewards if existing
        if (crvAmount > 0) {
            // Process fees on CRV Rewards
            _processRewardsFees(crvAmount, CRV_TOKEN);

            // Transfer balance of CRV to the Badger Tree
            uint256 crvBalance = IERC20Upgradeable(CRV_TOKEN).balanceOf(address(this));
            IERC20Upgradeable(CRV_TOKEN).safeTransfer(badgerTree, crvBalance);

            emit TreeDistribution(CRV_TOKEN, crvBalance, block.number, block.timestamp);
        }


        // Swap rewarded wMATIC for wBTC through wETH path
        if (rewardsAmount > 0) {
            address[] memory path = new address[](3);
            path[0] = reward;
            path[1] = wETH_TOKEN;
            path[2] = wBTC_TOKEN;
            IUniswapRouterV2(QUICKSWAP_ROUTER).swapExactTokensForTokens(rewardsAmount, 0, path, address(this), now);

            // Deposit wBTC on AAVE and get amWBTC in return
            uint256 wbtcBalance = IERC20Upgradeable(wBTC_TOKEN).balanceOf(address(this));
            ILendingPool(lendingPool).deposit(address(wBTC_TOKEN), wbtcBalance, address(this), 0);

            // Add liquidity for aTricrypto pool by depositing amWBTC
            ICurveStableSwap(CURVE_USDBTCETH_POOL).add_liquidity(
                [0, IERC20Upgradeable(amWBTC_TOKEN).balanceOf(address(this)), 0], 0
            );
        }

        uint256 earned = IERC20Upgradeable(want).balanceOf(address(this)).sub(_before);

        /// @notice Keep this in so you get paid!
        (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) = _processPerformanceFees(earned);

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earned, block.number);

        return earned;
    }

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();

        if(balanceOfWant() > 0) {
            _deposit(balanceOfWant());
        }
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _processPerformanceFees(uint256 _amount) internal returns (uint256 governancePerformanceFee, uint256 strategistPerformanceFee) {
        governancePerformanceFee = _processFee(want, _amount, performanceFeeGovernance, IController(controller).rewards());

        strategistPerformanceFee = _processFee(want, _amount, performanceFeeStrategist, strategist);
    }

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address token) internal returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee) {
        governanceRewardsFee = _processFee(token, _amount, performanceFeeGovernance, IController(controller).rewards());

        strategistRewardsFee = _processFee(token, _amount, performanceFeeStrategist, strategist);
    }

}
