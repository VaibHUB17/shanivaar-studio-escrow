// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { StudioCredit } from "../src/StudioCredit.sol";
import { IStudioCredit } from "../src/interfaces/IStudioCredit.sol";

contract StudioCreditTest is Test {
    StudioCredit public token;

    address public admin = address(0xAD);
    address public issuer = address(0x15);
    address public escrow = address(0xEC);
    address public alice = address(0xA1);
    address public bob = address(0xB2);
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        token = new StudioCredit(admin);

        vm.startPrank(admin);
        token.grantRole(ISSUER_ROLE, issuer);
        token.setEscrow(escrow);
        vm.stopPrank();
    }

    // --- T2: Movement Rules ---

    function test_T2_transferRule_learnerToLearnerReverts() public {
        vm.prank(issuer);
        token.issue(alice, 1000);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IStudioCredit.CreditsNotTransferable.selector, alice, bob)
        );
        token.transfer(bob, 500);
    }

    function test_T2_transferRule_transferFromLearnerToLearnerReverts() public {
        vm.prank(issuer);
        token.issue(alice, 1000);

        vm.prank(alice);
        token.approve(bob, 500);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IStudioCredit.CreditsNotTransferable.selector, alice, bob)
        );
        token.transferFrom(alice, bob, 500);
    }

    function test_T2_escrowPullsAndPayoutsSucceed() public {
        vm.prank(issuer);
        token.issue(alice, 1000);

        // Alice approves escrow and escrow pulls
        vm.prank(alice);
        token.approve(escrow, 1000);

        vm.prank(escrow);
        token.transferFrom(alice, escrow, 1000);
        assertEq(token.balanceOf(escrow), 1000);
        assertEq(token.balanceOf(alice), 0);

        // Escrow pays out to Bob
        vm.prank(escrow);
        token.transfer(bob, 1000);
        assertEq(token.balanceOf(bob), 1000);
        assertEq(token.balanceOf(escrow), 0);
    }

    function test_T2_issueAccessControlAndValidations() public {
        // Admin cannot issue without ISSUER_ROLE
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, ISSUER_ROLE
            )
        );
        token.issue(alice, 1000);

        // Random caller cannot issue
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ISSUER_ROLE
            )
        );
        token.issue(alice, 1000);

        // Zero address and zero amount reverts
        vm.startPrank(issuer);
        vm.expectRevert(IStudioCredit.ZeroAddress.selector);
        token.issue(address(0), 1000);

        vm.expectRevert(IStudioCredit.ZeroAmount.selector);
        token.issue(alice, 0);

        // Successful issue
        token.issue(alice, 5000);
        assertEq(token.balanceOf(alice), 5000);
        vm.stopPrank();
    }

    function test_T2_setEscrowRestrictions() public {
        // Re-deploy a fresh token to test initial setEscrow behavior
        vm.prank(admin);
        StudioCredit freshToken = new StudioCredit(admin);

        // Non-admin reverts
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE
            )
        );
        freshToken.setEscrow(escrow);

        // Zero address reverts
        vm.prank(admin);
        vm.expectRevert(IStudioCredit.ZeroAddress.selector);
        freshToken.setEscrow(address(0));

        // Setting escrow succeeds once
        vm.prank(admin);
        freshToken.setEscrow(escrow);
        assertEq(freshToken.escrow(), escrow);

        // Second call reverts EscrowAlreadySet
        vm.prank(admin);
        vm.expectRevert(IStudioCredit.EscrowAlreadySet.selector);
        freshToken.setEscrow(address(0x999));
    }

    function test_StudioCredit_constructorZeroAddress() public {
        vm.expectRevert(IStudioCredit.ZeroAddress.selector);
        new StudioCredit(address(0));
    }

    function test_StudioCredit_decimals() public view {
        assertEq(token.decimals(), 2);
    }
}
