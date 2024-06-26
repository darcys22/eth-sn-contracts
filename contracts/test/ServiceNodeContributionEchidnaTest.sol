// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../ServiceNodeContribution.sol";
import "./MockERC20.sol";
import "./MockServiceNodeRewards.sol";

// NOTE: We conduct assertion based testing for the service node contribution
// contract in Echidna. When we use property based-testing, the sender of the
// transactions to `ServiceNodeContribution.sol` is limited to this contract's
// address.
//
// However, `ServiceNodeContribution` is a contract that wants to be tested by
// taking in arbitrary contributions from different wallets. This is possible in
// `assertion` mode instead of `property` mode. This means that tests have to
// enforce invariants using `assert` instead of returning bools.
//
// We've left the `property` based testing in the contract but instead used them
// with asserts to test arbitrary invariants at any point in the contract.

contract ServiceNodeContributionEchidnaTest {

    // TODO: Max contributors is hard-coded
    // TODO: Staking requirement is currently hard-coded to value in script/deploy-local-test.js
    // TODO: Immutable variables in the testing contract causes Echidna 2.2.3 to crash
    uint256                               public STAKING_REQUIREMENT      = 100000000000;
    uint256                               public MAX_CONTRIBUTORS         = 10;

    IERC20                                public sentToken;
    MockServiceNodeRewards                public stakingRewardsContract;
    ServiceNodeContribution               public snContribution;
    IServiceNodeRewards.ServiceNodeParams public snParams;
    address                               public snOperator;
    BN256G1.G1Point                       public blsPubkey;


    constructor() {
        snOperator = msg.sender;
        sentToken = new MockERC20("Session Token", "SENT", 9);
        stakingRewardsContract = new MockServiceNodeRewards(address(sentToken), STAKING_REQUIREMENT);

        snContribution = new ServiceNodeContribution(
            /*stakingRewardsContract*/ address(stakingRewardsContract),
            /*maxContributors*/        MAX_CONTRIBUTORS,
            /*blsPubkey*/              blsPubkey,
            /*serviceNodeParams*/      snParams);
        
    }

    function mintTokensForTesting() internal {
        if (sentToken.allowance(msg.sender, address(stakingRewardsContract)) <= 0) {
            sentToken.transferFrom(address(0), msg.sender, type(uint64).max);
            sentToken.approve(address(snContribution), type(uint64).max);
        }
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  Property Testing                        //
    //                                                          //
    //////////////////////////////////////////////////////////////
    function echidna_prop_max_contributor_limit() public view returns (bool) {
        bool result = snContribution.numberContributors() < snContribution.maxContributors();
        assert(result);
        return result;
    }

    function echidna_prop_total_contribution_is_staking_requirement() public view returns (bool) {
        bool result = snContribution.totalContribution() == snContribution.maxContributors() ? (snContribution.totalContribution() == snContribution.stakingRequirement())
                                                                                             : (snContribution.totalContribution() <  snContribution.stakingRequirement());
        assert(result);
        return result;
    }

    function echidna_prop_operator_has_contribution() public view returns (bool) {
        bool result = snContribution.totalContribution() > 0 ? (snContribution.contributions(snContribution.operator()) > 0)
                                                             : (snContribution.contributions(snContribution.operator()) == 0);
        assert(result);
        return result;
    }

    function echidna_prop_check_immutable_props() public view returns (bool) {

        (uint256 serviceNodePubkey,
         uint256 serviceNodeSignature1,
         uint256 serviceNodeSignature2,
         uint16 fee) = snContribution.serviceNodeParams();

        bool snParamsLockedIn = (snParams.serviceNodePubkey     == serviceNodePubkey)     &&
                                (snParams.serviceNodeSignature1 == serviceNodeSignature1) &&
                                (snParams.serviceNodeSignature2 == serviceNodeSignature2) &&
                                (snParams.fee                   == fee);
        assert(snParamsLockedIn);

        (uint256 blsPKeyX, uint256 blsPKeyY) = snContribution.blsPubkey();

        bool result = address(stakingRewardsContract) == address(snContribution.stakingRewardsContract())          &&
                      STAKING_REQUIREMENT             == snContribution.stakingRequirement()                       &&
                      MAX_CONTRIBUTORS                == snContribution.maxContributors()                          &&
                      snOperator                      == snContribution.operator()                                 &&
                      sentToken                       == snContribution.stakingRewardsContract().designatedToken() &&
                      blsPubkey.X                     == blsPKeyX                                                  &&
                      blsPubkey.Y                     == blsPKeyY                                                  &&
                      snParamsLockedIn;
        assert(result);
        return result;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                  Contract Wrapper                        //
    //                                                          //
    //////////////////////////////////////////////////////////////
    function testContributeOperatorFunds(uint256 _amount, IServiceNodeRewards.BLSSignatureParams memory _blsSignature) public {
        mintTokensForTesting();
        if (snOperator                            == msg.sender &&
            snContribution.operatorContribution() == 0          &&
            _amount                               >= snContribution.minimumContribution()          &&
            !snContribution.cancelled()) {

            uint256 balanceBeforeContribute = sentToken.balanceOf(msg.sender);

            assert(snContribution.contributions(snContribution.operator()) == 0);
            assert(snContribution.operatorContribution()                   == 0);
            assert(snContribution.totalContribution()                      == 0);
            assert(snContribution.numberContributors()                     == 0);

            try snContribution.contributeOperatorFunds(_amount, _blsSignature) {
            } catch {
                assert(false); // Contribute must succeed as all necessary preconditions are met
            }

            assert(snContribution.contributions(snContribution.operator()) >= snContribution.minimumContribution());
            assert(snContribution.operatorContribution()                   >= snContribution.minimumContribution());
            assert(snContribution.totalContribution()                      >= snContribution.minimumContribution());
            assert(snContribution.numberContributors()                     == 1);

            assert(sentToken.balanceOf(msg.sender) == balanceBeforeContribute - _amount);
        } else {
            try snContribution.contributeOperatorFunds(_amount, _blsSignature) {
                assert(false); // Contribute as operator must not succeed
            } catch {
            }
        }

    }

    function testContributeFunds(uint256 amount) public {
        mintTokensForTesting();
        uint256 balanceBeforeContribute = sentToken.balanceOf(msg.sender);

        if (snContribution.totalContribution() < STAKING_REQUIREMENT) {
            try snContribution.contributeFunds(amount) {
            } catch {
                assert(false); // Contribute must not fail as we have tokens and are under the staking requirement
            }
        } else {
            try snContribution.contributeFunds(amount) {
                assert(false); // Contribute must not succeed as we have hit the staking requirement
            } catch {
            }
        }
        assert(snContribution.numberContributors() < snContribution.maxContributors());
        assert(snContribution.totalContribution() <= STAKING_REQUIREMENT);

        assert(sentToken.balanceOf(msg.sender) == balanceBeforeContribute - amount);

        if (snContribution.totalContribution() == STAKING_REQUIREMENT) {
            assert(snContribution.finalized());
            assert(sentToken.balanceOf(address(snContribution)) == 0);
        }
    }

    function testWithdrawStake() public {
        uint256 contribution             = snContribution.contributions(msg.sender);
        uint256 balanceBeforeWithdraw    = sentToken.balanceOf(msg.sender);
        uint256 numberContributorsBefore = snContribution.numberContributors();

        try snContribution.withdrawStake() {
            // Withdraw can succeed if we are not the operator and we had
            // contributed to the contract
            assert(snOperator != msg.sender);
            assert(contribution > 0);
            assert(snContribution.numberContributors() == (numberContributorsBefore - 1));
        } catch {
            assert(numberContributorsBefore == 0);
            assert(contribution == 0);
        }

        assert(!snContribution.finalized());
        assert(snContribution.operatorContribution() >=  0 && snContribution.operatorContribution() <= STAKING_REQUIREMENT);
        assert(snContribution.totalContribution()    >=  0 && snContribution.totalContribution()    <= STAKING_REQUIREMENT);

        assert(sentToken.balanceOf(msg.sender) == balanceBeforeWithdraw + contribution);
    }

    function testCancelNode() public {
        uint256 operatorContribution = snContribution.contributions(msg.sender);
        uint256 balanceBeforeCancel  = sentToken.balanceOf(msg.sender);

        if (snContribution.finalized() || snContribution.cancelled()) {
            try snContribution.cancelNode() {
                assert(false); // Can't cancel after finalized or cancelled
            } catch {
            }
        } else {
            if (msg.sender == snOperator) {
                try snContribution.cancelNode() {
                } catch {
                    assert(false); // Can cancel at any point before finalization
                }
                assert(snContribution.cancelled());
                assert(snContribution.contributions(msg.sender) == 0);
            } else {
                try snContribution.cancelNode() {
                    assert(false); // Can never cancel because we are not operator
                } catch {
                }
            }
            assert(!snContribution.finalized());
        }

        assert(sentToken.balanceOf(msg.sender) == balanceBeforeCancel + operatorContribution);
    }

    function testResetNode(uint256 _amount) public {
        if (!snContribution.finalized() || snContribution.cancelled()) {
            try snContribution.resetContract(_amount) {
                assert(false); // Can't reset until after finalized
            } catch {
            }
        } else {
            if (msg.sender == snOperator && _amount >= snContribution.minimumContribution()) {
                uint256 balanceBeforeContribute = sentToken.balanceOf(msg.sender);
                try snContribution.resetContract(_amount) {
                } catch {
                    assert(false); // Can reset if finalized
                }
                assert(!snContribution.finalized());
                assert(snContribution.contributions(msg.sender) == _amount);
                assert(snContribution.operatorContribution() == _amount);
                assert(sentToken.balanceOf(msg.sender) == balanceBeforeContribute - _amount);
            } else {
                try snContribution.resetContract(_amount) {
                    assert(false); // Can not reset
                } catch {
                }
            }
            assert(!snContribution.finalized());
        }
    }

    function testMinimumContribution() public view returns (uint256) {
        uint256 result = snContribution.minimumContribution();
        assert(result <= STAKING_REQUIREMENT);
        return result;
    }

    /*
     * @notice Fuzz all branches of `_minimumContribution`
     */
    function test_MinimumContribution(uint256 _contributionRemaining, uint256 _numberContributors, uint256 _maxContributors) public view returns (uint256) {
        uint256 result = snContribution._minimumContribution(_contributionRemaining,
                                                             _numberContributors,
                                                             _maxContributors);
        return result;
    }

    /*
     * @notice Fuzz the non-reverting branch of `_minimumContribution` by
     * sanitising inputs into the desired ranges.
     */
    function testFiltered_MinimumContribution(uint256 _contributionRemaining, uint256 _numberContributors, uint256 _maxContributors) public view returns (uint256) {
        uint256 maxContributors    = (_maxContributors    % (MAX_CONTRIBUTORS + 1));
        uint256 numberContributors = (_numberContributors % (maxContributors  + 1));
        uint256 result             = snContribution._minimumContribution(_contributionRemaining,
                                                                         numberContributors,
                                                                         maxContributors);
        assert(result <= _contributionRemaining);
        return result;
    }
}
