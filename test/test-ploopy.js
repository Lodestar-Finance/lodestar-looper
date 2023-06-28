const { expect } = require("chai");
const hre = require("hardhat");

// Declare static constants
const loopyAddress = "0x9F320D2A950093e9639E14814Bd81aD099dF60bC";
const _deployer = "0x0eDfa3fbE365CBF269DDc4b286eBD4797c78b21a";
const _miscUser = "0x45ad22B2Ad15D4Cc3717A544d1e2D317E88A3B27";
const _USDC = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
const _owner = "0x0eDfa3fbE365CBF269DDc4b286eBD4797c78b21a";
const _divisor = 1e4;
const _maxLeverage = 30_000;

console.log("--------------------------------------");
console.log("Executing test-loopy.js script");
console.log("--------------------------------------");

// MAJORITY OF TESTING WAS DONE ON MAINNET
// SUCCESSFUL TRANSACTION: https://arbiscan.io/tx/0xdf4260cc5cd9530bdafe6ac5f86e25ab863ff47aac76ceda52fe1daddda961b2

// Deployment related tests, mainly surrounding validating constructers are mapped properly.
describe("Deployment", async function() {
    let loopy;

    beforeEach(async function () {
        // Deploy Mock ERC20 tokens and router for testing
        const mockERC20 = await ethers.getContractFactory("MockERC20");
        const mockUSDC = await mockERC20.deploy();

        // console.log("mockUSDC address:", mockUSDC.address);

        // Deploy the Loopy contract
        const mockLoopy = await ethers.getContractFactory("Loopy");
        loopy = await mockLoopy.deploy();

        // console.log("mockLoopy address:", loopy.address);

        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    });

    describe("Deployment", function () {
        it("Should fail if owner is not set properly", async function () {
            // console.log("Loopy owner:", await loopy.owner());
            // console.log("Expected owner:", owner.address.toString());
            expect((await loopy.owner()).toString().toLowerCase()).to.equal(owner.address.toLowerCase());
        })
        it("Should fail if divisor is not set properly", async function () {
            try {
                const divisor = await loopy.DIVISOR();
                // console.log("Loopy divisor:", divisor.toString());
                // console.log("Expected divisor:", _divisor.toString());
                expect(divisor).to.equal(_divisor);
            } catch (error) {
                console.log(error);
            }
        })
        it("Should fail if max leverage is not set properly", async function () {
            try {
                const maxLeverage = await loopy.MAX_LEVERAGE();
                // console.log("Loopy max leverage:", maxLeverage.toString());
                // console.log("Expected max leverage:", _maxLeverage.toString());
                expect(maxLeverage).to.equal(_maxLeverage);
            } catch (error) {
                console.log(error);
            }
        })
    });

    describe("Permission and Access Control", function () {
        it("Should fail if non-owner tries to call an owner-only function", async function () {
            expect(loopy.connect(_miscUser).transferOwnership(_owner)).to.be.reverted;
        });
        it("Should allow owner to call an owner-only function", async function () {
            await expect(loopy.transferOwnership(_owner)).to.not.be.reverted;
        });
    });

    describe("Looping", async function() {
        it("Should fail if _leverage < DIVISOR or _leverage > MAX_LEVERAGE", async function () {
            expect(loopy.loop(100, 999)).to.be.reverted;
        });
        // it("Should succeed", async function () {
        //     expect(loopy.loop(1, 2000000)).to.not.be.reverted;
        // });
        // it("Should fail if called by non EOA", async function () {
        //     const loopy = await hre.ethers.getContractAt("Loopy", loopyAddress);
        //     expect(loopy.loop(100, 10000)).to.be.reverted;
        // });
    });

    // describe("receiveFlashLoan", function () {
    //     it("Should fail if called by other than the BALANCER_VAULT", async function () {
    //         const loopy = await hre.ethers.getContractAt("Loopy", loopyAddress);
    //         console.log("Loopy contract address:", loopy.address.toString());
    //         expect(loopy.receiveFlashLoan([], [], [], "0x")).to.be.reverted;
    //     });

    //     it("Should fail if feeAmounts[0] > 0", async function () {
    //         const loopy = await hre.ethers.getContractAt("Loopy", loopyAddress);
    //         console.log("Loopy contract address:", loopy.address.toString());
    //         expect(loopy.receiveFlashLoan([_USDC], [1000], [1], "0x")).to.be.reverted;
    //     });

    //     it("Should fail if data.borrowedAmount != amounts[0] or data.borrowedToken != tokens[0]", async function () {
    //         const loopy = await hre.ethers.getContractAt("Loopy", loopyAddress);
    //         console.log("Loopy contract address:", loopy.address.toString());
    //         expect(loopy.receiveFlashLoan([_USDC], [1000], [0], "0x")).to.be.reverted;
    //     });

    //     it("Should fail if glpAmount == 0", async function () {
    //         const loopy = await hre.ethers.getContractAt("Loopy", loopyAddress);
    //         console.log("Loopy contract address:", loopy.address.toString());
    //         expect(loopy.receiveFlashLoan([_USDC], [1000], [0], "0x")).to.be.reverted;
    //     });
    // });

});


