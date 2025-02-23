// This script registers the L1 token with its L2 counterpart using the Arbitrum custom gateway
// and then bridges over some tokens via the custom bridge.
// It assumes that the tokens are already deployed and that the necessary gateway addresses are hardcoded.

const hre = require("hardhat");
const chalk = require("chalk");
const { getArbitrumNetwork } = require("@arbitrum/sdk");

const ethers = hre.ethers;

async function main() {
  const SESH_DECIMALS = 9;
  const SESH_TO_TRANSFER = "200000000";

  // Hardcoded addresses
  // TODO: replace with actual deployed contract addresses
  const L1_TOKEN_ADDRESS = "0xL1TokenAddress";
  const L2_TOKEN_ADDRESS = "0xL2TokenAddress";
  const L1_CUSTOM_GATEWAY_ADDRESS = "0xL1CustomGatewayAddress";
  const L1_GATEWAY_ROUTER_ADDRESS = "0xL1GatewayRouterAddress";

  const [owner] = await ethers.getSigners();
  const ownerAddress = await owner.getAddress();
  console.log(chalk.green(`Using deployer: ${ownerAddress}`));

  // --- Register token on L1 to token on L2 via the L1CustomGateway contract ---
  console.log(chalk.blue("\nRegistering L1 token to L2 token via L1CustomGateway..."));

  const l1CustomGatewayABI = [
    "function registerTokenToL2(address _l1Token, address _l2Token) external"
  ];

  const l1CustomGateway = new ethers.Contract(
    L1_CUSTOM_GATEWAY_ADDRESS,
    l1CustomGatewayABI,
    owner
  );

  try {
    const registerTx = await l1CustomGateway.registerTokenToL2(L1_TOKEN_ADDRESS, L2_TOKEN_ADDRESS);
    console.log("Registration transaction submitted, waiting for confirmation...");
    const registerReceipt = await registerTx.wait();
    console.log(chalk.green(`L1CustomGateway registration successful: ${registerReceipt.transactionHash}`));
  } catch (error) {
    console.error(chalk.red("Error during L1CustomGateway registration:"), error);
    process.exit(1);
  }

  // --- Register token on L1 to the L1GatewayRouter ---
  console.log(chalk.blue("\nRegistering token to L1GatewayRouter..."));

  const l1GatewayRouterABI = [
    "function setGateway(address _token, address _gateway) external",
    "function outboundTransferCustomRefund(address _token, address _refundTo, address _to, uint256 _amount, uint256 _maxGas, uint256 _gasPriceBid, bytes calldata _data) external payable returns (bytes memory)",
  ];

  const l1GatewayRouter = new ethers.Contract(
    L1_GATEWAY_ROUTER_ADDRESS,
    l1GatewayRouterABI,
    owner
  );

  try {
    const setGatewayTx = await l1GatewayRouter.setGateway(L1_TOKEN_ADDRESS, L1_CUSTOM_GATEWAY_ADDRESS);
    console.log("SetGateway transaction submitted, waiting for confirmation...");
    const setGatewayReceipt = await setGatewayTx.wait();
    console.log(chalk.green(`L1GatewayRouter registration successful: ${setGatewayReceipt.transactionHash}`));
  } catch (error) {
    console.error(chalk.red("Error during L1GatewayRouter registration:"), error);
    process.exit(1);
  }

  console.log(chalk.green("\nToken registration on L1 complete."));

  // --- Bridging Tokens over to L2 ---
  console.log(chalk.blue("\nInitiating token bridge via the custom bridge..."));


  // Approve the token for the gateway transfer.
  const depositAmount = ethers.parseUnits(SESH_TO_TRANSFER, SESH_DECIMALS);
  console.log(`Approving ${SESH_TO_TRANSFER} tokens for the L1 Gateway...`);
  const erc20ABI = [
    "function approve(address spender, uint256 amount) external returns (bool)"
  ];
  const l1TokenContract = new ethers.Contract(L1_TOKEN_ADDRESS, erc20ABI, owner);
  try {
    const approveTx = await l1TokenContract.approve(L1_CUSTOM_GATEWAY_ADDRESS, depositAmount);
    await approveTx.wait();
    console.log(chalk.green("Token approval complete."));
  } catch (error) {
    console.error(chalk.red("Error during token approval:"), error);
    process.exit(1);
  }

  // Calculate parameters for the outbound transfer
  const l1MaxGas = BigInt(300000);
  const l2MaxGas = BigInt(1000000);
  const feeData = await owner.provider.getFeeData();
  let l1GasPriceBid = feeData.gasPrice ? feeData.gasPrice * BigInt(2) : ethers.parseUnits('10', 'gwei');
  const l2GasPriceBid = BigInt("1000000000");
  const maxSubmissionCost = BigInt("500000000000000");
  const callHookData = "0x";
  const l2amount = ethers.parseEther("0.002");
  const totalL2GasCost = l2MaxGas * l2GasPriceBid;
  const totalL2Value = maxSubmissionCost + totalL2GasCost + l2amount;
  const extraData = ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint256", "bytes"],
    [maxSubmissionCost, callHookData]
  );

  console.log("Initiating outbound transfer on the custom bridge...");
  try {
    const outboundTx = await l1GatewayRouter.outboundTransferCustomRefund(
      L1_TOKEN_ADDRESS,
      ownerAddress,   // refund recipient
      ownerAddress,   // destination on L2
      depositAmount,
      l2MaxGas,
      l2GasPriceBid,
      extraData,
      {
        gasLimit: l1MaxGas,
        gasPrice: l1GasPriceBid,
        value: totalL2Value,
      }
    );
    console.log("Outbound transfer transaction submitted, waiting for confirmation...");
    const receipt = await outboundTx.wait();
    console.log(chalk.green(`Outbound transfer successful: ${receipt.transactionHash}`));
    console.log(`Track the retryable ticket here: https://retryable-dashboard.arbitrum.io/tx/${receipt.transactionHash}`);
  } catch (error) {
    console.error(chalk.red("Error during outbound transfer:"), error);
    process.exit(1);
  }

  console.log(chalk.green("\nToken registration and bridging complete."));
}

main().catch((error) => {
  console.error(chalk.red("Script encountered an error:"), error);
  process.exitCode = 1;
});

