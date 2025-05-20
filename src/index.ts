import { ethers } from "ethers";
import { promisify } from "util";
import { exec } from "child_process";
import { privateKeyToAccount } from "viem/accounts";
import { http, encodeFunctionData, parseAbi, Hex } from "viem";
import { createBicoBundlerClient, createNexusClient, toNexusAccount } from "@biconomy/abstractjs";
import axios from "axios";

const execAsync = promisify(exec);

const LOCAL_RPC = "http://localhost:8545";
const MEE_NODE_URL = "http://localhost:3000/v3";
const CHAIN_ID = 31337;

const AAVE_POOL = "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2";
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const AUSDC = "0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c";
const USDC_WHALE = "0x55FE002aefF02F77364de339a1292923A15844B8";

const ERC20_ABI = parseAbi([
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
]);

const AAVE_POOL_ABI = parseAbi([
  "function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external",
  "function withdraw(address asset, uint256 amount, address to) external returns (uint256)",
]);

async function impersonate(address) {
  console.log(`Impersonating account: ${address}`);
  await execAsync(`cast rpc anvil_impersonateAccount ${address}`);
}

async function stopImpersonating(address) {
  console.log(`Stopping impersonation: ${address}`);
  await execAsync(`cast rpc anvil_stopImpersonatingAccount ${address}`);
}

async function checkMEENodeStatus() {
  const endpoints = ["/v3"];

  console.log("Checking MEE node status...");
  for (const endpoint of endpoints) {
    try {
      const response = await axios.get(`${MEE_NODE_URL}${endpoint}`, {
        timeout: 5000,
      });
      console.log(
        `✅ Endpoint ${endpoint} is available - Status: ${response.status}`
      );
      return {
        available: true,
        endpoint: endpoint,
        url: `${MEE_NODE_URL}${endpoint}`,
        response: response.data,
      };
    } catch (error) {
      if (error.response) {
        console.log(
          `❌ Endpoint ${endpoint} returned status: ${error.response.status}`
        );
      } else if (error.request) {
        console.log(`❌ Endpoint ${endpoint} - No response received`);
      } else {
        console.log(`❌ Endpoint ${endpoint} - Error: ${error.message}`);
      }
    }
  }

  console.log("❌ No MEE endpoints are available");
  return { available: false };
}

async function main() {
  try {
    console.log("=== BICONOMY MEE AAVE INTEGRATION (SIMPLIFIED) ===");

    console.log("Setting up provider and wallet...");
    const provider = new ethers.JsonRpcProvider(LOCAL_RPC);
    const adminKey =
      "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    const adminWallet = new ethers.Wallet(adminKey, provider);
    const adminAddress = await adminWallet.getAddress();

    console.log(`Admin EOA: ${adminAddress}`);

    console.log("\n--- TASK 3: FUNDING TEST EOA WITH USDC ---");

    await impersonate(USDC_WHALE);

    const usdcContract = new ethers.Contract(USDC, ERC20_ABI, provider);
    const decimals = await usdcContract.decimals();
    console.log(`USDC decimals: ${decimals}`);

    const fundAmount = ethers.parseUnits("1000", decimals);
    console.log(
      `Fund amount: ${ethers.formatUnits(fundAmount, decimals)} USDC`
    );

    const whaleSigner = await provider.getSigner(USDC_WHALE);
    const usdcWithWhaleSigner = new ethers.Contract(
      USDC,
      ERC20_ABI,
      whaleSigner
    );

    console.log(`Transferring 1000 USDC from whale to ${adminAddress}...`);
    const transferTx = await usdcWithWhaleSigner.transfer(
      adminAddress,
      fundAmount
    );
    console.log(`Transfer transaction hash: ${transferTx.hash}`);

    await transferTx.wait();

    const adminBalance = await usdcContract.balanceOf(adminAddress);
    console.log(
      `Admin USDC balance: ${ethers.formatUnits(adminBalance, decimals)} USDC`
    );

    await stopImpersonating(USDC_WHALE);

    console.log("\n--- INITIALIZING BICONOMY SDK ---");

    const meeStatus = await checkMEENodeStatus();
    let nexusClient;
    let smartAccountAddress;
    let bicoBundler;
    let useMEE = false;

    if (meeStatus.available) {
      try {
        const account = privateKeyToAccount(adminKey);

        console.log(`Connecting to MEE node at: ${MEE_NODE_URL}`);
        nexusClient = createNexusClient({
          account: await toNexusAccount({
            signer: account,
            transport: http(LOCAL_RPC),
            chain: {
              id: CHAIN_ID,
              name: "Local Eth Fork",
              nativeCurrency: {
                name: "ETH",
                symbol: "ETH",
                decimals: 18,
              },
              rpcUrls: {
                default: { http: [LOCAL_RPC] },
                public: { http: [LOCAL_RPC] },
              },
            },
          }),
          transport: http(MEE_NODE_URL, {
            methods: {
              include: ["POST", "GET", "PUT", "DELETE"],
            },
          }),
        });

        bicoBundler = createBicoBundlerClient({
          bundlerUrl: MEE_NODE_URL,
          account: nexusClient,
        });

        const gasFees = await bicoBundler.getGasFeeValues();
        console.log("Fast gas fees:", gasFees.fast);
        console.log("Standard gas fees:", gasFees.standard);
        console.log("Slow gas fees:", gasFees.slow);

        smartAccountAddress = await bicoBundler.account.address;
        console.log(`Smart Account address: ${smartAccountAddress}`);
        useMEE = true;
      } catch (sdkError) {
        console.error("Failed to connect to MEE node:", sdkError.message);
        console.log("Proceeding with direct AAVE interaction instead");
      }
    } else {
      console.log(
        "MEE node is not available. Will use direct AAVE interaction instead."
      );
    }

    console.log("\n--- TASK 5: EXECUTING TRANSACTION SEQUENCE ---");

    const supplyAmount = ethers.parseUnits("100", decimals);
    console.log(
      `Supply amount: ${ethers.formatUnits(supplyAmount, decimals)} USDC`
    );

    if (useMEE && bicoBundler && smartAccountAddress) {
      try {
        console.log("Using Biconomy MEE for transaction sequence...");

        console.log(
          `Transferring USDC to Smart Account: ${smartAccountAddress}`
        );
        const usdcWithAdmin = new ethers.Contract(USDC, ERC20_ABI, adminWallet);
        const transferToSCATx = await usdcWithAdmin.transfer(
          smartAccountAddress,
          supplyAmount
        );
        await transferToSCATx.wait();

        const scaUsdcBalance = await usdcContract.balanceOf(
          smartAccountAddress
        );
        console.log(
          `Smart Account USDC balance: ${ethers.formatUnits(
            scaUsdcBalance,
            decimals
          )} USDC`
        );

        console.log("Preparing approval transaction...");
        const approveCalldata = encodeFunctionData({
          abi: ERC20_ABI,
          functionName: "approve",
          args: [AAVE_POOL, BigInt(supplyAmount.toString())],
        });

        console.log("Preparing supply transaction...");
        const supplyCalldata = encodeFunctionData({
          abi: AAVE_POOL_ABI,
          functionName: "supply",
          args: [USDC, BigInt(supplyAmount.toString()), smartAccountAddress, 0],
        });

        console.log("Sending approval transaction...");
        const approveHash = await bicoBundler.sendTransaction({
          calls: [
            {
              to: USDC,
              data: approveCalldata,
            },
          ],
        });
        console.log(`Approval transaction hash: ${approveHash}`);

        await bicoBundler.waitForTransactionReceipt({ hash: approveHash });

        console.log("Sending supply transaction...");
        const supplyHash = await bicoBundler.sendTransaction({
          calls: [
            {
              to: AAVE_POOL,
              data: supplyCalldata,
            },
          ],
        });
        console.log(`Supply transaction hash: ${supplyHash}`);

        await bicoBundler.waitForTransactionReceipt({ hash: supplyHash });

        const aUsdcContract = new ethers.Contract(AUSDC, ERC20_ABI, provider);
        const aUsdcBalance = await aUsdcContract.balanceOf(smartAccountAddress);
        console.log(
          `Smart Account aUSDC balance: ${ethers.formatUnits(
            aUsdcBalance,
            decimals
          )} aUSDC`
        );

        console.log("Preparing transfer back transaction...");
        const transferBackCalldata = encodeFunctionData({
          abi: ERC20_ABI,
          functionName: "transfer",
          args: [adminAddress as Hex, BigInt(aUsdcBalance.toString())],
        });

        console.log("Transferring aUSDC back to EOA...");
        const transferBackHash = await bicoBundler.sendTransaction({
          calls: [
            {
              to: AUSDC,
              data: transferBackCalldata,
            },
          ],
        });
        console.log(`Transfer back transaction hash: ${transferBackHash}`);

        await bicoBundler.waitForTransactionReceipt({ hash: transferBackHash });

        const finalAUsdcBalance = await aUsdcContract.balanceOf(adminAddress);
        console.log(
          `Final EOA aUSDC balance: ${ethers.formatUnits(
            finalAUsdcBalance,
            decimals
          )} aUSDC`
        );

        console.log("\n=== MEE INTEGRATION COMPLETED SUCCESSFULLY ===");
        return;
      } catch (meeError) {
        console.error("MEE transaction failed:", meeError.message);
        console.log("Falling back to direct AAVE interaction...");
      }
    }

    console.log("\n--- DIRECT AAVE INTERACTION (FALLBACK) ---");

    const usdcWithAdmin = new ethers.Contract(USDC, ERC20_ABI, adminWallet);
    const aavePool = new ethers.Contract(AAVE_POOL, AAVE_POOL_ABI, adminWallet);
    const aUsdcContract = new ethers.Contract(AUSDC, ERC20_ABI, provider);

    console.log("Approving AAVE pool to spend USDC...");
    const approveTx = await usdcWithAdmin.approve(AAVE_POOL, supplyAmount);
    console.log(`Approve transaction hash: ${approveTx.hash}`);

    await approveTx.wait();

    console.log("Supplying USDC to AAVE pool...");
    const supplyTx = await aavePool.supply(USDC, supplyAmount, adminAddress, 0);
    console.log(`Supply transaction hash: ${supplyTx.hash}`);

    await supplyTx.wait();

    const aUsdcBalance = await aUsdcContract.balanceOf(adminAddress);
    console.log(
      `aUSDC balance: ${ethers.formatUnits(aUsdcBalance, decimals)} aUSDC`
    );

    console.log("\n=== DIRECT AAVE INTEGRATION COMPLETED SUCCESSFULLY ===");
  } catch (error) {
    console.error("Error:", error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
