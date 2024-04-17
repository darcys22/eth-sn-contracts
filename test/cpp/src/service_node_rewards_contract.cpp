#include "service_node_rewards/service_node_rewards_contract.hpp"

#include <iostream>

ServiceNodeRewardsContract::ServiceNodeRewardsContract(const std::string& _contractAddress, std::shared_ptr<Provider> _provider)
        : contractAddress(_contractAddress), provider(_provider) {}

Transaction ServiceNodeRewardsContract::addBLSPublicKey(const std::string& publicKey, const std::string& sig, const std::string& serviceNodePubkey, const std::string& serviceNodeSignature, const uint64_t fee) {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("addBLSPublicKey((uint256,uint256),(uint256,uint256,uint256,uint256),(uint256,uint256,uint256,uint16),(address,uint256)[])");

    const std::string serviceNodePubkeyPadded = utils::padTo32Bytes(utils::toHexString(serviceNodePubkey), utils::PaddingDirection::LEFT);
    const std::string serviceNodeSignaturePadded = utils::padToNBytes(utils::toHexString(serviceNodeSignature), 64, utils::PaddingDirection::LEFT);
    const std::string fee_padded = utils::padTo32Bytes(utils::decimalToHex(fee), utils::PaddingDirection::LEFT);

    // 11 parameters before the contributors array
    const std::string contributors_offset = utils::padTo32Bytes(utils::decimalToHex(11 * 32), utils::PaddingDirection::LEFT);
    // empty for now
    const std::string contributors = utils::padTo32Bytes(utils::decimalToHex(0), utils::PaddingDirection::LEFT);

    tx.data = functionSelector + publicKey + sig + serviceNodePubkeyPadded + serviceNodeSignaturePadded + fee_padded + contributors_offset + contributors;

    return tx;
}

ContractServiceNode ServiceNodeRewardsContract::serviceNodes(uint64_t index)
{
    ReadCallData callData            = {};
    std::string  indexABI            = utils::padTo32Bytes(utils::decimalToHex(index), utils::PaddingDirection::LEFT);
    callData.contractAddress         = contractAddress;
    callData.data                    = utils::getFunctionSignature("serviceNodes(uint64)") + indexABI;
    nlohmann::json     callResult    = provider->callReadFunctionJSON(callData);
    const std::string& callResultHex = callResult.get_ref<nlohmann::json::string_t&>();
    std::string_view   callResultIt  = utils::trimPrefix(callResultHex, "0x");

    const size_t        U256_HEX_SIZE                  = (256 / 8) * 2;
    const size_t        BLS_PKEY_XY_COMPONENT_HEX_SIZE = 32 * 2;
    const size_t        BLS_PKEY_HEX_SIZE              = BLS_PKEY_XY_COMPONENT_HEX_SIZE + BLS_PKEY_XY_COMPONENT_HEX_SIZE;
    const size_t        ADDRESS_HEX_SIZE               = 32 * 2;

    ContractServiceNode result                   = {};
    size_t              walkIt                   = 0;
    std::string_view    nextHex                  = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += nextHex.size();
    std::string_view    prevHex                  = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += prevHex.size();
    std::string_view    recipientHex             = callResultIt.substr(walkIt, ADDRESS_HEX_SIZE);  walkIt += recipientHex.size();
    std::string_view    pubkeyHex                = callResultIt.substr(walkIt, BLS_PKEY_HEX_SIZE); walkIt += pubkeyHex.size();
    std::string_view    leaveRequestTimestampHex = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += leaveRequestTimestampHex.size();
    std::string_view    depositHex               = callResultIt.substr(walkIt, U256_HEX_SIZE);     walkIt += depositHex.size();
    assert(walkIt == callResultIt.size());

    // NOTE: Deserialize linked list
    result.next                = utils::fromHexStringToUint64(nextHex);
    result.prev                = utils::fromHexStringToUint64(prevHex);

    // NOTE: Deserialise recipient
    std::vector<unsigned char> recipientBytes = utils::fromHexString(utils::trimLeadingZeros(recipientHex));
    assert(recipientBytes.size() == result.recipient.max_size());
    std::memcpy(result.recipient.data(), recipientBytes.data(), recipientBytes.size());

    // NOTE: Deserialise key hex into BLS key
    result.pubkey = utils::HexToBLSPublicKey(pubkeyHex);

    // NOTE: Deserialise metadata
    result.leaveRequestTimestamp = utils::fromHexStringToUint64(leaveRequestTimestampHex);
    result.deposit               = depositHex;
    return result;
}

uint64_t ServiceNodeRewardsContract::serviceNodeIDs(const bls::PublicKey& pKey)
{
    // NOTE: Generate the ABI caller data
    std::string pKeyABI             = utils::BLSPublicKeyToHex(pKey);
    std::string methodABI           = utils::getFunctionSignature("serviceNodeIDs(bytes)");
    std::string offsetToPKeyDataABI = utils::padTo32Bytes(utils::decimalToHex(32) /*offset includes the 32 byte offset itself*/, utils::PaddingDirection::LEFT);
    std::string bytesSizeABI        = utils::padTo32Bytes(utils::decimalToHex(pKeyABI.size() / 2), utils::PaddingDirection::LEFT);

    // NOTE: Setup call data
    ReadCallData callData    = {};
    callData.contractAddress = contractAddress;

    // NOTE: Fill in ABI
    callData.data.reserve(methodABI.size() + offsetToPKeyDataABI.size() + bytesSizeABI.size() + pKeyABI.size());
    callData.data += methodABI;
    callData.data += offsetToPKeyDataABI;
    callData.data += bytesSizeABI;
    callData.data += pKeyABI;

    // NOTE: Call function
    nlohmann::json     callResult = provider->callReadFunctionJSON(callData);
    const std::string& resultHex  = callResult.get_ref<nlohmann::json::string_t&>();
    uint64_t           result     = utils::fromHexStringToUint64(resultHex);
    return result;
}

uint64_t ServiceNodeRewardsContract::serviceNodesLength() {
    ReadCallData callData;
    callData.contractAddress = contractAddress;
    callData.data = utils::getFunctionSignature("serviceNodesLength()");
    std::string result = provider->callReadFunction(callData);
    return utils::fromHexStringToUint64(result);
}

std::string ServiceNodeRewardsContract::designatedToken() {
    ReadCallData callData;
    callData.contractAddress = contractAddress;
    callData.data = utils::getFunctionSignature("designatedToken()");
    return provider->callReadFunction(callData);
}

std::string ServiceNodeRewardsContract::aggregatePubkey() {
    ReadCallData callData;
    callData.contractAddress = contractAddress;
    callData.data = utils::getFunctionSignature("aggregatePubkey()");
    return provider->callReadFunction(callData);
}

Recipient ServiceNodeRewardsContract::viewRecipientData(const std::string& address) {
    ReadCallData callData;
    callData.contractAddress = contractAddress;

    std::string rewardAddressOutput = address;
    if (rewardAddressOutput.substr(0, 2) == "0x")
        rewardAddressOutput = rewardAddressOutput.substr(2);  // remove "0x"
    rewardAddressOutput = utils::padTo32Bytes(rewardAddressOutput, utils::PaddingDirection::LEFT);
    callData.data = utils::getFunctionSignature("recipients(address)") + rewardAddressOutput;

    std::string result = provider->callReadFunction(callData);

    // This assumes both the returned integers fit into a uint64_t but they are actually uint256 and dont have a good way of storing the 
    // full amount. In tests this will just mean that we need to keep our numbers below the 64bit max.
    std::string rewardsHex = result.substr(2 + 64-8, 8);
    std::string claimedHex = result.substr(2 + 64 + 64-8, 8);

    uint64_t rewards = std::stoull(rewardsHex, nullptr, 16);
    uint64_t claimed = std::stoull(claimedHex, nullptr, 16);

    return Recipient(rewards, claimed);
}

Transaction ServiceNodeRewardsContract::liquidateBLSPublicKeyWithSignature(const uint64_t service_node_id, const std::string& pubkey, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("liquidateBLSPublicKeyWithSignature(uint64,uint256,uint256,uint256,uint256,uint256,uint256,uint64[])");
    std::string node_id_padded = utils::padTo32Bytes(utils::decimalToHex(service_node_id), utils::PaddingDirection::LEFT);
    // 8 Params: id, 2x pubkey, 4x sig, pointer to array
    std::string indices_padded = utils::padTo32Bytes(utils::decimalToHex(8*32), utils::PaddingDirection::LEFT);
    indices_padded += utils::padTo32Bytes(utils::decimalToHex(non_signer_indices.size()), utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += utils::padTo32Bytes(utils::decimalToHex(index), utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + node_id_padded + pubkey + sig + indices_padded;

    return tx;
}

Transaction ServiceNodeRewardsContract::removeBLSPublicKeyWithSignature(const uint64_t service_node_id, const std::string& pubkey, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("removeBLSPublicKeyWithSignature(uint64,uint256,uint256,uint256,uint256,uint256,uint256,uint64[])");
    std::string node_id_padded = utils::padTo32Bytes(utils::decimalToHex(service_node_id), utils::PaddingDirection::LEFT);
    // 8 Params: id, 2x pubkey, 4x sig, pointer to array
    std::string indices_padded = utils::padTo32Bytes(utils::decimalToHex(8*32), utils::PaddingDirection::LEFT);
    indices_padded += utils::padTo32Bytes(utils::decimalToHex(non_signer_indices.size()), utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += utils::padTo32Bytes(utils::decimalToHex(index), utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + node_id_padded + pubkey + sig + indices_padded;

    return tx;
}

Transaction ServiceNodeRewardsContract::initiateRemoveBLSPublicKey(const uint64_t service_node_id) {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("initiateRemoveBLSPublicKey(uint64)");
    std::string node_id_padded = utils::padTo32Bytes(utils::decimalToHex(service_node_id), utils::PaddingDirection::LEFT);
    tx.data = functionSelector + node_id_padded;
    return tx;
}

Transaction ServiceNodeRewardsContract::removeBLSPublicKeyAfterWaitTime(const uint64_t service_node_id) {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("removeBLSPublicKeyAfterWaitTime(uint64)");
    std::string node_id_padded = utils::padTo32Bytes(utils::decimalToHex(service_node_id), utils::PaddingDirection::LEFT);
    tx.data = functionSelector + node_id_padded;
    return tx;
}

Transaction ServiceNodeRewardsContract::updateRewardsBalance(const std::string& address, const uint64_t amount, const std::string& sig, const std::vector<uint64_t>& non_signer_indices) {
    Transaction tx(contractAddress, 0, 30000000);
    std::string functionSelector = utils::getFunctionSignature("updateRewardsBalance(address,uint256,uint256,uint256,uint256,uint256,uint64[])");
    std::string rewardAddressOutput = address;
    if (rewardAddressOutput.substr(0, 2) == "0x")
        rewardAddressOutput = rewardAddressOutput.substr(2);  // remove "0x"
    rewardAddressOutput = utils::padTo32Bytes(rewardAddressOutput, utils::PaddingDirection::LEFT);
    std::string amount_padded = utils::padTo32Bytes(utils::decimalToHex(amount), utils::PaddingDirection::LEFT);
    // 7 Params: addr, amount, 4x sig, pointer to array
    std::string indices_padded = utils::padTo32Bytes(utils::decimalToHex(7*32), utils::PaddingDirection::LEFT);
    indices_padded += utils::padTo32Bytes(utils::decimalToHex(non_signer_indices.size()), utils::PaddingDirection::LEFT);
    for (const auto index: non_signer_indices) {
        indices_padded += utils::padTo32Bytes(utils::decimalToHex(index), utils::PaddingDirection::LEFT);
    }
    tx.data = functionSelector + rewardAddressOutput + amount_padded + sig + indices_padded;

    return tx;
}

Transaction ServiceNodeRewardsContract::claimRewards() {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("claimRewards()");
    tx.data = functionSelector;
    return tx;
}

Transaction ServiceNodeRewardsContract::start() {
    Transaction tx(contractAddress, 0, 3000000);
    std::string functionSelector = utils::getFunctionSignature("start()");
    tx.data = functionSelector;
    return tx;
}
