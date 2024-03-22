// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/Pairing.sol";

interface IServiceNodeRewards {
    /// @notice Represents a service node in the network.
    struct ServiceNode {
        uint64 next;
        uint64 previous;
        address recipient;
        BN256G1.G1Point pubkey;
        uint256 leaveRequestTimestamp;
        uint256 deposit;
    }
    // Public Variables
    function IsActive() external view returns (bool);
    function designatedToken() external view returns (IERC20);
    function foundationPool() external view returns (IERC20);
    function nextServiceNodeID() external view returns (uint64);
    function totalNodes() external view returns (uint256);
    function blsNonSignerThreshold() external view returns (uint256);
    function proofOfPossessionTag() external view returns (bytes32);
    function rewardTag() external view returns (bytes32);
    function removalTag() external view returns (bytes32);
    function liquidateTag() external view returns (bytes32);
    function stakingRequirement() external view returns (uint256);
    function liquidatorRewardRatio() external view returns (uint256);
    function poolShareOfLiquidationRatio() external view returns (uint256);
    function recipientRatio() external view returns (uint256);
    function serviceNodes(uint64) external view returns (ServiceNode memory);
    function recipients(address) external view returns (uint256 rewards, uint256 claimed);
    function serviceNodeIDs(bytes memory) external view returns (uint64);
    function aggregate_pubkey() external view returns (BN256G1.G1Point memory);

    // Events
    event NewSeededServiceNode(uint64 indexed serviceNodeID, BN256G1.G1Point pubkey);
    event NewServiceNode(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey, uint256 serviceNodePubkey, uint256 serviceNodeSignature);
    event RewardsBalanceUpdated(address indexed recipientAddress, uint256 amount, uint256 previousBalance);
    event RewardsClaimed(address indexed recipientAddress, uint256 amount);
    event ServiceNodeLiquidated(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);
    event ServiceNodeRemoval(uint64 indexed serviceNodeID, address recipient, uint256 returnedAmount, BN256G1.G1Point pubkey);
    event ServiceNodeRemovalRequest(uint64 indexed serviceNodeID, address recipient, BN256G1.G1Point pubkey);

    // Function Signatures
    function updateRewardsBalance(
        address recipientAddress, 
        uint256 recipientAmount,
        uint256 sigs0,
        uint256 sigs1,
        uint256 sigs2,
        uint256 sigs3,
        uint64[] calldata ids
    ) external;
    function buildRecipientMessage(address recipientAddress, uint256 balance) external pure returns (bytes memory);
    function claimRewards() external;
    function addBLSPublicKey(uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint256 serviceNodePubkey, uint256 serviceNodeSignature) external;
    function initiateRemoveBLSPublicKey(uint64 serviceNodeID) external;
    function removeBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint64[] calldata ids) external;
    function removeBLSPublicKeyAfterWaitTime(uint64 serviceNodeID) external;
    function liquidateBLSPublicKeyWithSignature(uint64 serviceNodeID, uint256 pkX, uint256 pkY, uint256 sigs0, uint256 sigs1, uint256 sigs2, uint256 sigs3, uint64[] calldata ids) external;
    function seedPublicKeyList(uint256[] calldata pkX, uint256[] calldata pkY, uint256[] calldata amounts) external;
    function serviceNodesLength() external view returns (uint256 count);
    function updateServiceNodesLength() external;
    function start() external;
}
