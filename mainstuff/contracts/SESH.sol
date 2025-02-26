// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ICustomToken.sol";
import "./libraries/Shared.sol";

/**
 * @title Interface needed to call function registerTokenToL2 of the L1CustomGateway
 */
interface IL1CustomGateway {
    function registerTokenToL2(
        address _l2Address,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable returns (uint256);
}

/**
 * @title Interface needed to call function setGateway of the L2GatewayRouter
 */
interface IL2GatewayRouter {
    function setGateway(
        address _gateway,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        uint256 _maxSubmissionCost,
        address _creditBackAddress
    ) external payable returns (uint256);
}



/**
 * @title SESH contract
 * @notice The SESH utility token with Arbitrum Custom Gateway support
 */
contract SESH is ERC20, ERC20Permit, Shared, ICustomToken {
    using SafeERC20 for IERC20;

    address public immutable gateway;
    address public immutable router;
    bool private shouldRegisterGateway;

    constructor(
        uint256 totalSupply_,
        address receiverGenesisAddress,
        address _gateway,
        address _router
    ) ERC20("Session Token", "SESH") ERC20Permit("Session Token") nzAddr(receiverGenesisAddress) nzUint(totalSupply_) {
        _mint(receiverGenesisAddress, totalSupply_);
        gateway = _gateway;
        router = _router;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    /// @notice Returns `0xb1` to indicate the token is Arbitrum enabled
    function isArbitrumEnabled() external view override returns (uint8) {
        require(shouldRegisterGateway, "NOT_EXPECTED_CALL");
        return uint8(0xb1);
    }

    /// @notice Register token on L2 via the Arbitrum Custom Gateway
    function registerTokenOnL2(
        address l2CustomTokenAddress,
        uint256 maxSubmissionCostForCustomGateway,
        uint256 maxSubmissionCostForRouter,
        uint256 maxGasForCustomGateway,
        uint256 maxGasForRouter,
        uint256 gasPriceBid,
        uint256 valueForGateway,
        uint256 valueForRouter,
        address creditBackAddress
    ) public payable override {
        bool prev = shouldRegisterGateway;
        shouldRegisterGateway = true;

        IL1CustomGateway(gateway).registerTokenToL2{ value: valueForGateway }(
            l2CustomTokenAddress,
            maxGasForCustomGateway,
            gasPriceBid,
            maxSubmissionCostForCustomGateway,
            creditBackAddress
        );

        IL2GatewayRouter(router).setGateway{ value: valueForRouter }(
            gateway,
            maxGasForRouter,
            gasPriceBid,
            maxSubmissionCostForRouter,
            creditBackAddress
        );

        shouldRegisterGateway = prev;
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, ICustomToken) returns (bool) {
        return true;
    }

    function balanceOf(address account) public override(ERC20, ICustomToken) view virtual returns (uint256) {
        return 0;
    }
}

