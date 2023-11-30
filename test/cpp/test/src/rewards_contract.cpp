#include <iostream>
#include <limits>

#include "ethyl/provider.hpp"
#include "ethyl/signer.hpp"
#include "service_node_rewards/config.hpp"
#include "service_node_rewards/service_node_rewards_contract.hpp"
#include "service_node_rewards/erc20_contract.hpp"
#include "service_node_rewards/service_node_list.hpp"

#include <catch2/catch_test_macros.hpp>
#include <catch2/catch_all.hpp>

const auto& config = ethbls::get_config(ethbls::network_type::LOCAL);
auto provider = std::make_shared<Provider>("Client", std::string(config.RPC_URL));

std::string contract_address = provider->getContractDeployedInLatestBlock();

ServiceNodeRewardsContract rewards_contract(contract_address, provider);
Signer signer(provider);    
std::vector<unsigned char> seckey = utils::fromHexString(std::string(config.PRIVATE_KEY));

std::string erc20_address = utils::trimAddress(rewards_contract.designatedToken());
ERC20Contract erc20_contract(erc20_address, provider);
std::string snapshot_id = provider->evm_snapshot();

TEST_CASE( "Rewards Contract", "[ethereum]" ) {
    bool success_resetting_to_snapshot = provider->evm_revert(snapshot_id);
    snapshot_id = provider->evm_snapshot();
    REQUIRE(success_resetting_to_snapshot);

    // Check rewards contract is responding and set to zero
    REQUIRE(rewards_contract.serviceNodesLength() == 0);
    REQUIRE(contract_address != "");

    // Approve our contract and make sure it was successful
    auto tx = erc20_contract.approve(contract_address, std::numeric_limits<std::uint64_t>::max());;
    auto hash = signer.sendTransaction(tx, seckey);
    REQUIRE(hash != "");
    REQUIRE(provider->transactionSuccessful(hash));

    SECTION( "Add a public key to the smart contract" ) {
        REQUIRE(rewards_contract.serviceNodesLength() == 0);
        ServiceNodeList snl(1);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address);
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession);
            hash = signer.sendTransaction(tx, seckey);
            REQUIRE(hash != "");
            REQUIRE(provider->transactionSuccessful(hash));
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 1);
    }

    SECTION( "Add several public keys to the smart contract and check aggregate pubkey" ) {
        ServiceNodeList snl(2);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address);
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession);
            hash = signer.sendTransaction(tx, seckey);
            REQUIRE(hash != "");
            REQUIRE(provider->transactionSuccessful(hash));
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Add several public keys to the smart contract and liquidate one of them with everyone signing (including the liquidated node)" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address);
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size());
        const auto sig = snl.liquidateNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.liquidateBLSPublicKeyWithSignature(service_node_to_remove, sig, {});
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Add several public keys to the smart contract and liquidate one of them with a single non signer" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address);
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession);
            signer.sendTransaction(tx, seckey);
        }
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        const auto signers = snl.randomSigners(snl.nodes.size() - 1);
        const auto sig = snl.liquidateNodeFromIndices(service_node_to_remove, config.CHAIN_ID, contract_address, signers);
        const auto non_signers = snl.findNonSigners(signers);
        tx = rewards_contract.liquidateBLSPublicKeyWithSignature(service_node_to_remove, sig, non_signers);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 2);
        snl.deleteNode(service_node_to_remove);
        REQUIRE(rewards_contract.aggregatePubkey() == "0x" + snl.aggregatePubkeyHex());
    }

    SECTION( "Initiate remove public key with correct signer" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address);
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        hash = signer.sendTransaction(tx, seckey);
        REQUIRE(hash != "");
        REQUIRE(provider->transactionSuccessful(hash));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
    }

    SECTION( "Initiate remove public key with incorrect signer" ) {
        ServiceNodeList snl(3);
        for(auto& node : snl.nodes) {
            const auto pubkey = node.getPublicKeyHex();
            const auto proof_of_possession = node.proofOfPossession(config.CHAIN_ID, contract_address);
            tx = rewards_contract.addBLSPublicKey(pubkey, proof_of_possession);
            signer.sendTransaction(tx, seckey);
        }
        const uint64_t service_node_to_remove = snl.randomServiceNodeID();
        tx = rewards_contract.initiateRemoveBLSPublicKey(service_node_to_remove);
        std::vector<unsigned char> badseckey = utils::fromHexString(std::string(config.ADDITIONAL_PRIVATE_KEY1));
        REQUIRE_THROWS(signer.sendTransaction(tx, badseckey));
        REQUIRE(rewards_contract.serviceNodesLength() == 3);
    }
}
