pragma solidity ^0.8.16;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "src/purchaser.sol";

interface IMintable {
    function mint(address, uint) external;
}

contract PurchaserTest is DSTest{
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant INV = IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address usdcHolder = 0x28C6c06298d514Db089934071355E5743bf21d60;
    address buyer = address(0xA);
    address hacker = address(0xB);
    Purchaser purchaser;
    
    function setUp() public{
        purchaser = new Purchaser();
        vm.prank(gov);
        purchaser.toggleWhitelist(buyer);
        vm.prank(usdcHolder);
        USDC.transfer(buyer, 1000_000 * 10**6);
        vm.prank(buyer);
        USDC.approve(address(purchaser), type(uint).max);
        vm.prank(gov);
        IMintable(address(INV)).mint(address(purchaser), 30_000 ether);
    }

    function test_buyUnderDailyLimit_succeed() public {
        uint invPrice = purchaser.getInvPrice();
        uint purchaseAmount = 5_000 * 10**6;
        uint dailyLimit = 10_000 * 10**6;
        uint totalLimit = 1000_000 * 10**6;
        uint bonusBps = 1500;
        vm.prank(gov);
        purchaser.init(block.timestamp-1, 10 days, dailyLimit, totalLimit, bonusBps, invPrice / 2);
        uint buyerInvBefore = INV.balanceOf(buyer);
        uint govUsdcBefore = USDC.balanceOf(gov);
        uint lifetimeBuyBefore = purchaser.lifetimeBuy();

        vm.startPrank(buyer);
        purchaser.buy(purchaseAmount, invPrice);
        vm.stopPrank(); 

        assertEq(USDC.balanceOf(gov), govUsdcBefore + purchaseAmount, "Gov didn't receive the right amount of USDC");
        uint invToReceive = purchaseAmount * 10**12 * 10**18 / purchaser.getInvPrice();
        invToReceive += invToReceive * purchaser.bonusBps() / 10_000;
        assertEq(INV.balanceOf(buyer), buyerInvBefore + invToReceive, "Buyer didn't receive right amount of INV");
        assertEq(purchaser.limitAvailable(), dailyLimit - purchaseAmount, "Daily limit did not decrease properly");
        assertEq(purchaser.lifetimeBuy(), lifetimeBuyBefore + purchaseAmount, "Total bought did not increase properly");
    }

    function test_buyFullDailyLimitAfterReset_succeed() public {
        uint invPrice = purchaser.getInvPrice();
        uint dailyLimit = 10_000 * 10**6;
        uint purchaseAmount = dailyLimit;
        uint totalLimit = 1000_000 * 10**6;
        uint bonusBps = 1500;
        vm.prank(gov);
        purchaser.init(block.timestamp-1, 10 days, dailyLimit, totalLimit, bonusBps, invPrice / 2);
        uint buyerInvBefore = INV.balanceOf(buyer);
        uint govUsdcBefore = USDC.balanceOf(gov);
        uint lifetimeBuyBefore = purchaser.lifetimeBuy();

        vm.startPrank(buyer);
        purchaser.buy(purchaseAmount, invPrice);
        vm.warp(block.timestamp + 1 days);
        purchaser.buy(purchaseAmount, invPrice);
        vm.stopPrank(); 

        assertEq(USDC.balanceOf(gov), govUsdcBefore + purchaseAmount * 2, "Gov didn't receive the right amount of USDC");
        uint invToReceive = purchaseAmount * 10**12 * 10**18 / purchaser.getInvPrice();
        invToReceive += invToReceive * purchaser.bonusBps() / 10_000;
        assertEq(INV.balanceOf(buyer), buyerInvBefore + invToReceive * 2, "Buyer didn't receive right amount of INV");
        assertEq(purchaser.limitAvailable(), 0, "Daily limit did not decrease properly");
        assertEq(purchaser.lifetimeBuy(), lifetimeBuyBefore + purchaseAmount * 2, "Total bought did not increase properly");
    }

    function test_buyExeedDailyLimit_reverts() public {
        uint invPrice = purchaser.getInvPrice();
        vm.prank(gov);
        purchaser.init(block.timestamp-1, 10 days, 10_000 ether, 1000_000 ether, 1500, invPrice / 2);
        vm.expectRevert("BUY EXCEED LIMIT");
        vm.startPrank(buyer);
        purchaser.buy(10_001 ether, invPrice);
        vm.stopPrank();   
    }

    function test_buyExeedTotalLimit_reverts() public {
        uint invPrice = purchaser.getInvPrice();
        vm.prank(gov);
        purchaser.init(block.timestamp-1, 10 days, 20_000 ether, 10_000 ether, 1500, invPrice / 2);
        vm.expectRevert("BUY EXCEED LIMIT");
        vm.startPrank(buyer);
        purchaser.buy(10_001 ether, invPrice);
        vm.stopPrank();   
    }

    function test_buyFromNonWhitelist_reverts() public {
        uint invPrice = purchaser.getInvPrice();
        vm.prank(gov);
        purchaser.init(block.timestamp, 10 days, 10_000 ether, 1000_000 ether, 1500, invPrice / 2);
        vm.expectRevert("ONLY WHITELIST");
        vm.startPrank(hacker);
        purchaser.buy(1000 ether, invPrice);
        vm.stopPrank();
    }

    function test_buyBeforeInit_reverts() public {
        uint invPrice = purchaser.getInvPrice();
        vm.expectRevert("NOT INITIALIZED");
        vm.startPrank(buyer);
        purchaser.buy(1000 ether, invPrice);
        vm.stopPrank();
    }

    function test_buyBeforeStart_reverts() public {
        uint invPrice = purchaser.getInvPrice();
        vm.prank(gov);
        purchaser.init(block.timestamp+1, 10 days, 10_000 ether, 1000_000 ether, 1500, invPrice / 2);
        vm.expectRevert("OUT OF BUY PERIOD");
        vm.startPrank(buyer);
        purchaser.buy(1000 ether, invPrice);
        vm.stopPrank();
    }

    function test_buyAfterEnd_reverts() public {
        uint invPrice = purchaser.getInvPrice();
        vm.prank(gov);
        purchaser.init(block.timestamp - 11 days, 10 days, 10_000 ether, 1000_000 ether, 1500, invPrice / 2);
        vm.expectRevert("OUT OF BUY PERIOD");
        vm.startPrank(buyer);
        purchaser.buy(1000 ether, invPrice);
        vm.stopPrank();
    }
}

