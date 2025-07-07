// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { Test } from "forge-std/src/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ITokenizedStrategy } from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";

import { CoinflakesEoaStrategy } from "src/CoinflakesEoaStrategy.sol";

contract CoinflakesEoaStrategyTest is Test {
    using Math for uint256;

    address strategy;
    address assetManager;
    address vault;
    address unallowedUser;

    IERC20Metadata asset = IERC20Metadata(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI

    uint256 minFuzz = 10 ether; // DAI
    uint256 maxFuzz = 200_000 ether;

    function setUp() public virtual {
        setUp_fork();
        setUp_users();
        setUp_strategy();
    }

    function setUp_fork() internal {
        string memory url = vm.rpcUrl("mainnet");
        uint256 blockNumber = vm.envUint("BLOCK");
        assertGt(blockNumber, 0, "Please set BLOCK env variable");
        vm.createSelectFork(url, blockNumber);
    }

    function setUp_users() internal virtual {
        vault = address(1);
        vm.label(vault, "vault");
        assetManager = address(2);
        vm.label(assetManager, "assetManager");
        unallowedUser = address(3);
        vm.label(unallowedUser, "unallowedUser");
    }

    function setUp_strategy() internal virtual {
        strategy = address(new CoinflakesEoaStrategy("Coinflakes Yield Farming v1", address(asset), assetManager));
        ITokenizedStrategy(strategy).setPendingManagement(assetManager);
        //CoinflakesEoaStrategy(strategy).allowDepositor(vault);
        vm.startPrank(assetManager);
        ITokenizedStrategy(strategy).acceptManagement();
        CoinflakesEoaStrategy(strategy).grantRole(keccak256("DEPOSITOR_ADMIN_ROLE"), assetManager);
        CoinflakesEoaStrategy(strategy).grantRole(keccak256("SET_ASSETS_IN_USE_ROLE"), assetManager);
        CoinflakesEoaStrategy(strategy).allowDepositor(vault);
        asset.approve(strategy, type(uint256).max);
        vm.stopPrank();
    }

    function test_empty() public virtual { }

    function test_allowedDepositors_revertsWhenNotAllowed() public virtual {
        deal(address(asset), unallowedUser, minFuzz);
        vm.prank(unallowedUser);
        asset.approve(strategy, minFuzz);
        vm.expectRevert(bytes("ERC4626: deposit more than max"));
        vm.prank(unallowedUser);
        ITokenizedStrategy(strategy).deposit(minFuzz, unallowedUser);
    }

    function test_deposit(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        deal(address(asset), vault, amount);
        vm.startPrank(vault);
        deal(address(asset), assetManager, 0);
        asset.approve(strategy, amount);
        ITokenizedStrategy(strategy).deposit(amount, vault);
        vm.stopPrank();
        assertEq(asset.balanceOf(vault), 0, "not all assets deposited");
        assertEq(asset.balanceOf(assetManager), amount, "not all assets transferred to asset manager");
        assertEq(CoinflakesEoaStrategy(strategy).assetsInUse(), amount, "assets in use not updated");
        emit log_named_decimal_uint("assets deposited", amount, asset.decimals());
        emit log_named_decimal_uint("assets transferred to asset manager", amount, asset.decimals());
    }

    function test_withdraw_partialAmount(uint256 amount) public virtual {
        // This test should withdraw half of the deposited amount
        // and should result in the exact requested sum of assets.
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);
        vm.startPrank(vault);
        ITokenizedStrategy(strategy).withdraw(amount / 2, vault, vault);
        vm.stopPrank();
        assertEq(asset.balanceOf(vault), amount / 2, "wrong amount of assets received");
    }

    function test_withdraw_fullAmount(uint256 amount) public virtual {
        // This test should withdraw all of the deposited amount
        // and should result in an acceptable loss because of
        // slippage or fees.
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        uint256 acceptableLossBps = 300;

        vm.startPrank(vault);
        ITokenizedStrategy(strategy).withdraw(amount, vault, vault, acceptableLossBps);
        vm.stopPrank();
        assertEq(asset.balanceOf(vault), amount, "vault did not receive enough funds");
        assertEq(asset.balanceOf(assetManager), 0, "asset manager still has funds");
        assertEq(asset.balanceOf(strategy), 0, "strategy not empty");
    }

    function test_withdraw_notEnoughFreeFunds(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        deal(address(asset), assetManager, amount / 2);
        vm.expectRevert(bytes("Dai/insufficient-balance"));
        vm.startPrank(vault);
        ITokenizedStrategy(strategy).withdraw(amount, vault, vault, 0);
        vm.stopPrank();
    }

    function test_setAssetsInUse(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        vm.prank(assetManager);
        CoinflakesEoaStrategy(strategy).setAssetsInUse(amount);
        assertEq(CoinflakesEoaStrategy(strategy).assetsInUse(), amount, "Assets in use differs from stored amount");
    }

    function test_setAssetsInUse_revertsWhenNotAllowed() public virtual {
        deal(address(asset), unallowedUser, minFuzz);
        vm.prank(unallowedUser);
        asset.approve(strategy, minFuzz);
        vm.expectRevert(
            bytes(
                "AccessControl: account 0x0000000000000000000000000000000000000003 is missing role 0x39afacf1241040892fd6d58c14701e00f8731584b92e02cab560cfb7afa9e62a"
            )
        );
        vm.prank(unallowedUser);
        CoinflakesEoaStrategy(strategy).setAssetsInUse(minFuzz);
    }

    function test_report_withProfit(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);
        vm.prank(assetManager);
        CoinflakesEoaStrategy(strategy).setAssetsInUse(amount + 1);
        (uint256 profit, uint256 loss) = ITokenizedStrategy(strategy).report();
        assertEq(loss, 0, "unexpected loss reported");
        assertEq(profit, 1, "wrong profit reported");
    }

    function test_report_withLoss(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        vm.prank(assetManager);
        CoinflakesEoaStrategy(strategy).setAssetsInUse(amount - 1);

        (uint256 profit, uint256 loss) = ITokenizedStrategy(strategy).report();
        assertEq(profit, 0, "unexpected profit reported");
        assertEq(loss, 1, "wrong loss reported");
    }

    function test_emergencyWithdraw_partialAmount(uint256 amount) public virtual {
        // This test should swap strategy assets into vault assets
        // within the strategy.
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        ITokenizedStrategy(strategy).shutdownStrategy();
        uint256 withdrawAmount = amount / 2;
        ITokenizedStrategy(strategy).emergencyWithdraw(withdrawAmount);
        assertEq(asset.balanceOf(strategy), withdrawAmount, "incorrect amount of funds");
    }

    function test_emergencyWithdraw_fullAmount(uint256 amount) public virtual {
        vm.assume(amount >= minFuzz && amount <= maxFuzz);
        depositIntoStrategy(amount);

        vm.startPrank(assetManager);
        ITokenizedStrategy(strategy).shutdownStrategy();
        ITokenizedStrategy(strategy).emergencyWithdraw(amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(strategy), amount, "not enough funds recovered");
        assertEq(asset.balanceOf(assetManager), 0, "manager still has funds");
    }

    function airdrop(uint256 amount) internal virtual {
        require(address(asset) != address(0x0), "vault asset not initialized");
        require(address(vault) != address(0x0), "user not initialized");
        deal(address(asset), vault, amount);
        require(asset.balanceOf(vault) == amount, "funding failed");
    }

    function depositIntoStrategy(uint256 amount) internal virtual {
        airdrop(amount);
        vm.startPrank(vault);
        asset.approve(strategy, amount);
        ITokenizedStrategy(strategy).deposit(amount, vault);
        vm.stopPrank();
        assertEq(asset.balanceOf(vault), 0, "not all funds deposited");
    }
}
