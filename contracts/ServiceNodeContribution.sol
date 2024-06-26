// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./libraries/Shared.sol";
import "./interfaces/IServiceNodeRewards.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Service Node Contribution Contract
 * @dev This contract allows for the collection of contributions towards a service node. Operators usually generate one of these smart contracts 
 * for every service node they start and wish to allow other external persons to contribute to using the parent factory contract. 
 * Contributors can fund the service node until the staking requirement is met. After this point the operator will 
 * finalize the node setup, which will send the necessary node information and funds to the ServiceNodeRewards contract. This contract also allows for the
 * withdrawal of contributions before finalization, and cancel the node setup with refunds to contributors.
 **/
contract ServiceNodeContribution is Shared {
    using SafeERC20 for IERC20;

    // Staking
    // solhint-disable-next-line var-name-mixedcase
    IERC20                                 public immutable SENT;
    IServiceNodeRewards                    public immutable stakingRewardsContract;
    uint256                                public immutable stakingRequirement;

    // Service Node
    BN256G1.G1Point                        public           blsPubkey;
    IServiceNodeRewards.ServiceNodeParams  public           serviceNodeParams;
    IServiceNodeRewards.BLSSignatureParams public           blsSignature;

    // Contributions
    address                                public immutable operator;
    mapping(address => uint256)            public           contributions;
    mapping(address => uint256)            public           contributionTimestamp;
    address[]                              public           contributorAddresses;
    uint256                                public immutable maxContributors;
    uint256                                public           operatorContribution;
    uint256                                public           totalContribution;
    uint256                                public           numberContributors;

    // Smart Contract
    bool                                   public           finalized = false;
    bool                                   public           cancelled = false;

    uint64 public constant WITHDRAWAL_DELAY = 1 days;

    // MODIFIERS
    modifier onlyOperator() {
        require(msg.sender == operator, "Only the operator can perform this action.");
        _;
    }

    // EVENTS
    event Cancelled      (uint256 indexed serviceNodePubkey);
    event Finalized      (uint256 indexed serviceNodePubkey);
    event NewContribution(address indexed contributor, uint256 amount);
    event StakeWithdrawn (address indexed contributor, uint256 amount);

    /// @notice Constructs the ServiceNodeContribution contract. This is usually done by the parent factory contract
    /// @param _stakingRewardsContract Address of the staking rewards contract.
    /// @param _maxContributors Maximum number of contributors allowed.
    /// @param _blsPubkey - 64 bytes bls public key
    /// @param _serviceNodeParams - Service node public key, signature proving ownership of public key and fee that operator is charging
    constructor(address _stakingRewardsContract, uint256 _maxContributors, BN256G1.G1Point memory _blsPubkey, IServiceNodeRewards.ServiceNodeParams memory _serviceNodeParams) 
        nzAddr(_stakingRewardsContract)
        nzUint(_maxContributors)
    {
        stakingRewardsContract = IServiceNodeRewards(_stakingRewardsContract);
        SENT                   = IERC20(stakingRewardsContract.designatedToken());
        stakingRequirement     = stakingRewardsContract.stakingRequirement();
        maxContributors        = _maxContributors;
        operator               = tx.origin; // NOTE: Creation is delegated by operator through factory
        blsPubkey              = _blsPubkey;
        serviceNodeParams      = _serviceNodeParams;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  State-changing functions                //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Allows the operator to contribute funds towards their own node.
     * @dev This function sets the operator's contribution and emits a NewContribution event.
     * @param _blsSignature - 128 byte bls proof of possession signature
     * It can only be called once by the operator and must be done before any other contributions are made.
     */
    function contributeOperatorFunds(uint256 amount, IServiceNodeRewards.BLSSignatureParams memory _blsSignature) public onlyOperator {
        require(operatorContribution == 0, "Operator already contributed funds");
        require(!cancelled, "Node has been cancelled.");
        require(amount >= minimumContribution(), "Contribution is below minimum requirement");
        operatorContribution = amount;
        blsSignature = _blsSignature;
        contributeFunds(operatorContribution);
    }

    /**
     * @notice Allows contributors to fund the service node. This is the main entry point for contributors wanting to stake to a node.
     * @dev Contributions are only accepted if the operator has already contributed, the node has not been finalized or cancelled, and the contribution amount is above the minimum requirement.
     * @param amount The amount of funds to contribute.
     */
    function contributeFunds(uint256 amount) public {
        require(operatorContribution > 0, "Operator has not contributed funds");
        require(amount >= minimumContribution(), "Contribution is below the minimum requirement.");
        require(totalContribution + amount <= stakingRequirement, "Contribution exceeds the funding goal.");
        require(!finalized, "Node has already been finalized.");
        require(!cancelled, "Node has been cancelled.");
        if (contributions[msg.sender] == 0) {
            numberContributors += 1;
            contributorAddresses.push(msg.sender);
        }
        contributions[msg.sender] += amount;
        contributionTimestamp[msg.sender] = block.timestamp;
        totalContribution += amount;
        SENT.safeTransferFrom(msg.sender, address(this), amount);
        emit NewContribution(msg.sender, amount);
        if (totalContribution == stakingRequirement)
            finalizeNode();
    }

    /**
     * @notice When the contribute Funds function fills the contract this is called to call the AddBLSPublicKey function on the rewards contract and send funds to it
     */
    function finalizeNode() internal {
        require(totalContribution == stakingRequirement, "Funding goal has not been met.");
        require(!finalized, "Node has already been finalized.");
        require(!cancelled, "Node has been cancelled.");
        finalized = true;
        IServiceNodeRewards.Contributor[] memory contributors = new IServiceNodeRewards.Contributor[](numberContributors);
        for (uint256 i = 0; i < numberContributors; i++) {
            address contributorAddress = contributorAddresses[i];
            contributors[i] = IServiceNodeRewards.Contributor(contributorAddress, contributions[contributorAddress]);
        }
        SENT.approve(address(stakingRewardsContract), stakingRequirement);
        stakingRewardsContract.addBLSPublicKey(blsPubkey, blsSignature, serviceNodeParams, contributors);

        emit Finalized(serviceNodeParams.serviceNodePubkey);
    }

    /**
     * @notice Function to reset the contract to an empty state
     * @param amount The amount of funds the operator is to contribute.
     */
    function resetContract(uint256 amount) external onlyOperator {
        require(finalized, "Contract has not been finalized yet.");
        finalized = false;
        operatorContribution = 0;
        totalContribution = 0;
        numberContributors = 0;
        delete contributorAddresses;
        contributeOperatorFunds(amount, blsSignature);
    }

    /**
     * @notice Function to allow owner to rescue ERC20 tokens if the contract is finalized
     * @param tokenAddress the ERC20 token to rescue
     */
    function rescueERC20(address tokenAddress) external onlyOperator {
        require(finalized, "Contract has not been finalized yet.");
        require(!cancelled, "Contract has been cancelled.");
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Contract has no balance of the specified token.");
        token.transfer(operator, balance);
    }


    /**
     * @notice Allows contributors to withdraw their stake before the node is finalized.
     * @dev Withdrawals are only allowed if the node has not been finalized or cancelled. The operator cannot withdraw their contribution through this method. Operator should call cancelNode() instead.
     */
    function withdrawStake() public {
        require(contributions[msg.sender] > 0, "You have not contributed.");
        require(block.timestamp - contributionTimestamp[msg.sender] > WITHDRAWAL_DELAY, "Withdrawal unavailable: 24 hours have not passed");
        require(!finalized, "Node has already been finalized.");
        require(msg.sender != operator, "Operator cannot withdraw");
        uint256 refundAmount = contributions[msg.sender];
        contributions[msg.sender] = 0;
        numberContributors -= 1;
        totalContribution -= refundAmount;
        SENT.safeTransfer(msg.sender, refundAmount);
        emit StakeWithdrawn(msg.sender, refundAmount);
    }

    /**
     * @notice Cancels the service node setup. Will refund the operator and the contributors will be able to call withdrawStake to get their stake back.
     * @dev This can only be done by the operator and only if the node has not been finalized or already cancelled.
     */
    function cancelNode() public onlyOperator {
        require(!finalized, "Cannot cancel a finalized node.");
        require(!cancelled, "Node has already been cancelled.");

        // NOTE: Refund
        uint256 refundAmount       = contributions[msg.sender];
        contributions[msg.sender]  = 0;
        totalContribution         -= refundAmount;
        SENT.safeTransfer(msg.sender, refundAmount);

        // NOTE: Cancel registration
        require(refundAmount == operatorContribution, "Refund to operator on cancel must match operator contribution");
        cancelled                  = true;
        numberContributors         = numberContributors > 0 ? (numberContributors - 1) : 0;
        operatorContribution       = 0;

        emit Cancelled(serviceNodeParams.serviceNodePubkey);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                Non-state-changing functions              //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice Calculates the minimum contribution amount.
     * @dev The minimum contribution is dynamically calculated based on the number of contributors and the staking requirement. It returns math.ceilDiv of the calculation
     * @return The minimum contribution amount.
     */
    function minimumContribution() public view returns (uint256) {
        if (operatorContribution == 0)
            return (stakingRequirement - 1) / 4 + 1;
        return _minimumContribution(stakingRequirement - totalContribution, numberContributors, maxContributors);
    }

    function _minimumContribution(uint256 _contributionRemaining, uint256 _numberContributors, uint256 _maxContributors) public pure returns (uint256) {
        require(_maxContributors > _numberContributors, "Contributors exceed permitted maximum number of contributors");
        uint256 numContributionsRemainingAvail = _maxContributors - _numberContributors;
        return (_contributionRemaining - 1) / numContributionsRemainingAvail + 1;
    }
}

