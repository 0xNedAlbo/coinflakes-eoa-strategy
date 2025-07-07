// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { AccessControlDefaultAdminRules } from "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";

import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BaseStrategy } from "@tokenized-strategy/BaseStrategy.sol";

contract CoinflakesEoaStrategy is BaseStrategy, AccessControlDefaultAdminRules {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet allowedDepositors;

    event AllowDepositor(address indexed depositor);
    event DisallowDepositor(address indexed depositor);

    bytes32 public constant SET_ASSETS_IN_USE_ROLE = keccak256("SET_ASSETS_IN_USE_ROLE");
    bytes32 public constant DEPOSITOR_ADMIN_ROLE = keccak256("DEPOSITOR_ADMIN_ROLE");

    address public assetManager;
    uint256 public assetsInUse;

    event UseAssets(address indexed receiver, uint256 amount, uint256 assetsInUse);
    event ReturnAssets(address indexed sender, uint256 amount, uint256 assetsInUse);
    event SetAssetsInUse(uint256 amount);
    event SetAssetManager(address indexed newAssetManager);

    event EmergencyWithdraw(address indexed receiver, uint256 amount);

    constructor(
        string memory strategyName,
        address assetAddress,
        address managerAddress
    )
        BaseStrategy(assetAddress, strategyName)
        AccessControlDefaultAdminRules(1 hours, managerAddress)
    {
        assetManager = managerAddress;
        //grantRole(SET_ASSETS_IN_USE_ROLE, managerAddress);
    }

    function _deployFunds(uint256 amount) internal override {
        asset.safeTransfer(assetManager, amount);
        assetsInUse += amount;
        emit UseAssets(assetManager, amount, assetsInUse);
    }

    function _freeFunds(uint256 amount) internal override {
        asset.safeTransferFrom(assetManager, address(this), amount);
        assetsInUse -= amount;
        emit ReturnAssets(assetManager, amount, assetsInUse);
    }

    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        uint256 idleFunds = IERC20(asset).balanceOf(address(this));
        return idleFunds + assetsInUse;
    }

    function setAssetsInUse(uint256 amount) public onlyRole(SET_ASSETS_IN_USE_ROLE) {
        assetsInUse = amount;
        emit SetAssetsInUse(amount);
    }

    function availableDepositLimit(address owner) public view virtual override returns (uint256) {
        if (allowedDepositors.contains(owner)) return type(uint256).max;
        return 0;
    }

    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        _freeFunds(_amount);
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    function allowDepositor(address depositor) public onlyRole(DEPOSITOR_ADMIN_ROLE) {
        if (allowedDepositors.add(depositor)) emit AllowDepositor(depositor);
    }

    function disallowDepositor(address depositor) public onlyRole(DEPOSITOR_ADMIN_ROLE) {
        if (allowedDepositors.remove(depositor)) emit DisallowDepositor(depositor);
    }

    function isAllowedDepositor(address depositor) public view returns (bool) {
        return allowedDepositors.contains(depositor);
    }

    function setAssetManager(address newAssetManager) public onlyManagement {
        assetManager = newAssetManager;
        emit SetAssetManager(assetManager);
    }
}
