const hre = require("hardhat");
const chalk = require("chalk");

async function main() {
  // Replace with actual addresses for the L2 gateway and L1 counterpart
  const L2_GATEWAY_ADDRESS = "0xL2GatewayAddress";
  const L1_TOKEN_ADDRESS = "0xL1TokenAddress";

  const args = {
    L2_GATEWAY_ADDRESS,
    L1_TOKEN_ADDRESS,
  };

  await deploySESHL2(args);
}

async function deploySESHL2(args = {}, verify = true) {
  const [owner] = await hre.ethers.getSigners();
  const ownerAddress = await owner.getAddress();
  const networkName = hre.network.name;

  console.log("Deploying SESHL2 proxy contract to:", chalk.yellow(networkName));

  // Check for a valid API key in the Hardhat config (for verification)
  if (verify) {
    let apiKey;
    if (typeof hre.config.etherscan?.apiKey === "object") {
      apiKey = hre.config.etherscan.apiKey[networkName];
    } else {
      apiKey = hre.config.etherscan?.apiKey;
    }
    if (!apiKey || apiKey === "") {
      console.error(
        chalk.red("Error: API key for contract verification is missing.")
      );
      console.error(
        "Please set it in your Hardhat configuration under 'etherscan.apiKey'."
      );
      process.exit(1);
    }
  }

  const L2_GATEWAY_ADDRESS = args.L2_GATEWAY_ADDRESS;
  const L1_TOKEN_ADDRESS = args.L1_TOKEN_ADDRESS;

  const SESHL2 = await hre.ethers.getContractFactory("SESHL2", owner);

  let seshl2Proxy;
  try {
    seshl2Proxy = await hre.upgrades.deployProxy(
      SESHL2,
      [L2_GATEWAY_ADDRESS, L1_TOKEN_ADDRESS]
    );
  } catch (error) {
    console.error("Failed to deploy SESHL2 proxy contract:", error);
    process.exit(1);
  }

  console.log(
    "  ",
    chalk.cyan("SESHL2 Proxy Contract"),
    "deployed to:",
    chalk.greenBright(await seshl2Proxy.getAddress()),
    "on network:",
    chalk.yellow(networkName)
  );
  console.log("  ", "Deployment transaction sender:", chalk.green(ownerAddress));

  // Wait for a few confirmations to ensure the network has processed the transaction.
  await seshl2Proxy.deploymentTransaction().wait(6);

  if (verify) {
    console.log(chalk.yellow("\n--- Verifying SESHL2 Implementation ---\n"));
    try {
      await hre.run("verify:verify", {
        address: await seshl2Proxy.getAddress(),
        constructorArguments: [],
        contract: "contracts/SESHL2.sol:SESHL2",
        force: true,
      });
    } catch (error) {
      console.error(chalk.red("Verification failed:"), error);
    }
    console.log(chalk.green("Contract verification complete."));
  }
  return { seshl2Proxy };
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

