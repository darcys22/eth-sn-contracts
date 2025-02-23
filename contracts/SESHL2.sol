// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@arbitrum/token-bridge-contracts/contracts/tokenbridge/libraries/L2GatewayToken.sol";

/**
 * @title SESHL2 Token
 * @notice L2 representation of the SESH token, bridged from L1
 */
contract SESHL2 is Initializable, L2GatewayToken {

    /**
     * @notice Initializes the L2 token with the same name, symbol, and decimals as L1
     * @param l2Gateway_ The L2 gateway that interacts with the Arbitrum bridge
     * @param l1Counterpart_ The corresponding L1 token address
     */
    function initialize(address l2Gateway_, address l1Counterpart_) public initializer {
        _initialize("Session Token", "SESH", 9, l2Gateway_, l1Counterpart_);
    }
}
