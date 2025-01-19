// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Handler} from "../fuzz/Handler.t.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address public USER = makeAddr("USER");
    address public NO_TOKEN_USER = makeAddr("NO_TOKEN_USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant DSC_MINTED = 1000 ether;
    uint256 public constant HEALTH_FACTOR_BREAKER = 0.5 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Constructor Tests
    address[] public tokensAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthsDoesntMatchPriceFeeds() public {
        tokensAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokensAddresses, priceFeedAddresses, address(dsc));
    }

    function testTokenPriceFeedsAndCollateralTokensAreSetCorrectly() public {
        tokensAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);

        DSCEngine newEngine = new DSCEngine(tokensAddresses, priceFeedAddresses, address(dsc));

        (address expectedWethPriceFeedAddress, address[] memory collateralTokens) =
            newEngine.getPriceFeedAndCollateralTokens(weth);

        assertEq(ethUsdPriceFeed, expectedWethPriceFeedAddress);
        assertEq(weth, collateralTokens[0]);
    }

    function testDSCInitializesCorrectly() public {
        DSCEngine newEngine = new DSCEngine(tokensAddresses, priceFeedAddresses, address(dsc));

        assert(dsc == newEngine.getDSCContract());
    }

    // Price Tests
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 btcAmount = 15e18;

        uint256 expectedEthValue = 30000e18;
        uint256 expectedBtcValue = 375000e18;

        uint256 actualEthValue = engine.getUSDValue(weth, ethAmount);
        uint256 actualBtcValue = engine.getUSDValue(wbtc, btcAmount);

        assertEq(expectedEthValue, actualEthValue);
        assertEq(expectedBtcValue, actualBtcValue);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;

        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    // depositCollateral Tests
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        _;
    }

    modifier depositedCollateralAndMintedDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_MINTED);

        _;
    }

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnaaprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN");
        ranToken.mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateralAndMintedDSC {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInfo(USER);

        uint256 expectedTotalDscMinted = DSC_MINTED;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositCollateralEMitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // mintDSC Tests
    function testUserDSCAmountIncreasesAfterMiniting() public depositedCollateral {
        uint256 startingDSC = engine.getDSCMinted(USER);
        engine.mintDSC(1000 ether);
        uint256 endingDSC = engine.getDSCMinted(USER);

        assertEq(startingDSC + 1000 ether, endingDSC);
    }

    function testRevertsMintIfHealthFactorIsBroken() public depositedCollateral {
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, HEALTH_FACTOR_BREAKER)
        );
        engine.mintDSC(20000 ether);
    }

    // burnDSC Tests
    function testUserDSCAmountReducesAfterBurning() public depositedCollateralAndMintedDSC {
        uint256 startingDSC = engine.getDSCMinted(USER);
        ERC20Mock(address(dsc)).approve(address(engine), 100 ether);
        engine.burnDSC(100 ether);
        uint256 endingDSC = engine.getDSCMinted(USER);
        vm.stopPrank();

        assertEq(startingDSC - 100 ether, endingDSC);
    }

    // liquidate Tests
    function testLiquidationRevertsIfHealthFactorIsNotBroken() public depositedCollateralAndMintedDSC {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, DSC_MINTED);
    }

    // function testLiquidationRevertsIfHealthFactorIsNotImproved() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    //     engine.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, DSC_MINTED);

    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
    //     engine.liquidate(weth, USER, 500 ether);
    //     vm.stopPrank();
    // }

    // redeemCollateral Tests
    function testCollateralDepositedReducesAfterRedeeming() public depositedCollateralAndMintedDSC {
        uint256 startingCollateral = engine.getCollateralDeposited(USER, weth);
        console.log("Starting Collateral: ", startingCollateral);
        engine.redeemCollateral(weth, 1 ether);
        uint256 endingCollateral = engine.getCollateralDeposited(USER, weth);
        console.log("Ending Collateral: ", endingCollateral);

        assert(startingCollateral == endingCollateral + 1 ether);
    }

    function testRedeemCollateralEmitsEvent() public depositedCollateralAndMintedDSC {
        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(USER, USER, weth, 1 ether);
        engine.redeemCollateral(weth, 1 ether);
    }

    function testRevertsIfHealthFactorIsBrokenIfNoDSCIsMinted() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.getHealthFactor();
    }

    function testReturnsHealthFactor() public depositedCollateralAndMintedDSC {
        uint256 healthFactor = engine.getHealthFactor();
        uint256 expectedHealthFactor = 10e18;

        assertEq(healthFactor, expectedHealthFactor);
    }

    // function testRevertsIfHealthFactorIsBrokenIfNotOvercollaterized() public depositedCollateralAndMintedDSC {
    //     vm.expectRevert(
    //         abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, engine.getHealthFactor())
    //     );
    //     engine.redeemCollateral(weth, 5 ether);

    //     // engine.getHealthFactor();
    //     vm.stopPrank();
    // }
}
