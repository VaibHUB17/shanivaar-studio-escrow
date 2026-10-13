// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { StudioCredit } from "../src/StudioCredit.sol";
import { SessionEscrow } from "../src/SessionEscrow.sol";
import { ISessionEscrow } from "../src/interfaces/ISessionEscrow.sol";
import { IStudioCredit } from "../src/interfaces/IStudioCredit.sol";

contract SessionEscrowTest is Test {
    StudioCredit public token;
    SessionEscrow public escrow;

    address public admin = address(0xAD);
    address public treasury = address(0x78);
    address public issuer = address(0x15);
    address public ira = address(0x1A); // Instructor

    address public asha = address(0xA1);
    address public bhavesh = address(0xB1);
    address public chitra = address(0xC1);
    address public dev = address(0xD1);
    address public esha = address(0xE1);
    address public farhan = address(0xF1);

    bytes32 public constant INSTRUCTOR_ROLE = keccak256("INSTRUCTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    event EarningsClaimed(
        uint256 indexed sessionId,
        address indexed instructor,
        uint256 gross,
        uint16 feeBps,
        uint256 fee,
        uint256 net
    );

    function setUp() public {
        token = new StudioCredit(admin);
        escrow = new SessionEscrow(address(token), treasury, admin);

        vm.startPrank(admin);
        token.grantRole(ISSUER_ROLE, issuer);
        token.setEscrow(address(escrow));
        escrow.grantRole(INSTRUCTOR_ROLE, ira);
        vm.stopPrank();
    }

    function _issueAndApprove(address user, uint256 amount) internal {
        vm.prank(issuer);
        token.issue(user, amount);
        vm.prank(user);
        token.approve(address(escrow), type(uint256).max);
    }

    // ==========================================
    // T1: Worked Example
    // ==========================================
    function test_T1_workedExample() public {
        // Issuance
        _issueAndApprove(asha, 5000);
        _issueAndApprove(bhavesh, 5000);
        _issueAndApprove(dev, 5000);
        _issueAndApprove(esha, 5000);
        _issueAndApprove(farhan, 5000);

        uint64 startT1 = 1795860000;
        uint64 startT2 = 1796032800;

        // 1795341600 (T - 6 days): Ira creates session 1
        vm.warp(1795341600);
        vm.prank(ira);
        uint256 s1 = escrow.createSession(startT1, 1250, 3);
        assertEq(s1, 1);

        // 1795345200 (T - 6 days + 1 h): Ira creates session 2
        vm.warp(1795345200);
        vm.prank(ira);
        uint256 s2 = escrow.createSession(startT2, 800, 2);
        assertEq(s2, 2);

        // 1795428000 (T - 5 days): Asha books session 1 for herself
        vm.warp(1795428000);
        vm.prank(asha);
        uint256 b1 = escrow.book(1, asha);
        assertEq(b1, 1);
        assertEq(escrow.seatsLeft(1), 2);

        // 1795514400 (T - 4 days): Bhavesh books session 1 for Chitra
        vm.warp(1795514400);
        vm.prank(bhavesh);
        uint256 b2 = escrow.book(1, chitra);
        assertEq(b2, 2);
        assertEq(escrow.seatsLeft(1), 1);

        // 1795600800 (T - 3 days): Dev books session 1 for himself
        vm.warp(1795600800);
        vm.prank(dev);
        uint256 b3 = escrow.book(1, dev);
        assertEq(b3, 3);
        assertEq(escrow.seatsLeft(1), 0);

        // 1795604400 (T - 3 days + 1 h): Esha books session 2 for herself
        vm.warp(1795604400);
        vm.prank(esha);
        uint256 b4 = escrow.book(2, esha);
        assertEq(b4, 4);
        assertEq(escrow.seatsLeft(2), 1);

        // 1795608000 (T - 3 days + 2 h): Farhan books session 2 for himself
        vm.warp(1795608000);
        vm.prank(farhan);
        uint256 b5 = escrow.book(2, farhan);
        assertEq(b5, 5);
        assertEq(escrow.seatsLeft(2), 0);

        // 1795683600 (T - 49 h): Asha cancels booking 1 -> refunded 1250, retained 0
        vm.warp(1795683600);
        vm.prank(asha);
        escrow.cancelBooking(1);
        assertEq(escrow.seatsLeft(1), 1);

        // 1795752000 (T - 30 h): Dev cancels booking 3 -> refunded 750, retained 500
        vm.warp(1795752000);
        vm.prank(dev);
        escrow.cancelBooking(3);
        assertEq(escrow.seatsLeft(1), 2);

        // 1795924800 (session 2 start - 30 h): Farhan cancels booking 5 -> refunded 480, retained 320
        vm.warp(1795924800);
        vm.prank(farhan);
        escrow.cancelBooking(5);
        assertEq(escrow.seatsLeft(2), 1);

        // 1795946400 (T + 24 h): Ira claims session 1
        vm.warp(1795946400);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit EarningsClaimed(1, ira, 1750, 350, 62, 1688);
        vm.prank(ira);
        escrow.claimEarnings(1);

        // Check intermediate balances right after Ira claims session 1
        assertEq(token.balanceOf(asha), 5000);
        assertEq(token.balanceOf(bhavesh), 3750);
        assertEq(token.balanceOf(chitra), 0);
        assertEq(token.balanceOf(dev), 4500);
        assertEq(token.balanceOf(ira), 1688);
        assertEq(token.balanceOf(treasury), 62);

        // 1795996800 (session 2 start - 10 h): Ira cancels session 2
        vm.warp(1795996800);
        vm.prank(ira);
        escrow.cancelSession(2);

        // 1796000400 (session 2 start - 9 h): Esha claims a refund for booking 4
        vm.warp(1796000400);
        vm.prank(esha);
        escrow.claimRefund(4);
        assertEq(token.balanceOf(esha), 5000);

        // Assert final distribution of every single credit unit
        assertEq(token.balanceOf(asha), 5000);
        assertEq(token.balanceOf(bhavesh), 3750);
        assertEq(token.balanceOf(chitra), 0);
        assertEq(token.balanceOf(dev), 4500);
        assertEq(token.balanceOf(esha), 5000);
        assertEq(token.balanceOf(farhan), 4680);
        assertEq(token.balanceOf(ira), 1688);
        assertEq(token.balanceOf(treasury), 62);

        // Escrow balance remaining: 320 from Farhan's retained late-cancel penalty
        // (Since Session 2 was cancelled, Ira cannot claim it via claimEarnings)
        assertEq(token.balanceOf(address(escrow)), 320);
    }

    // ==========================================
    // T3: Comprehensive Custom Errors Coverage
    // ==========================================
    function test_T3_allCustomErrorsCovered() public {
        uint64 startT = 1795860000;
        vm.warp(1795341600);

        // 1. ZeroAddress
        vm.expectRevert(ISessionEscrow.ZeroAddress.selector);
        new SessionEscrow(address(0), treasury, admin);

        // 2. StartTooSoon
        vm.prank(ira);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionEscrow.StartTooSoon.selector,
                uint64(block.timestamp + 71 hours),
                block.timestamp + 72 hours
            )
        );
        escrow.createSession(uint64(block.timestamp + 71 hours), 1000, 10);

        // 3. InvalidPrice
        vm.startPrank(ira);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.InvalidPrice.selector, 99));
        escrow.createSession(startT, 99, 10);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.InvalidPrice.selector, 500001));
        escrow.createSession(startT, 500001, 10);

        // 4. InvalidCapacity
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.InvalidCapacity.selector, 0));
        escrow.createSession(startT, 1000, 0);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.InvalidCapacity.selector, 41));
        escrow.createSession(startT, 1000, 41);

        uint256 sId = escrow.createSession(startT, 1000, 1);
        vm.stopPrank();

        // 5. UnknownSession
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.UnknownSession.selector, 0));
        escrow.book(0, asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.UnknownSession.selector, 999));
        escrow.book(999, asha);

        // 6. ZeroAddress on attendee
        _issueAndApprove(asha, 5000);
        vm.prank(asha);
        vm.expectRevert(ISessionEscrow.ZeroAddress.selector);
        escrow.book(sId, address(0));

        // Book valid seat
        vm.prank(asha);
        uint256 bId = escrow.book(sId, asha);

        // 7. SessionFull
        _issueAndApprove(dev, 5000);
        vm.prank(dev);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.SessionFull.selector, sId));
        escrow.book(sId, dev);

        // 8. UnknownBooking
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.UnknownBooking.selector, 0));
        escrow.cancelBooking(0);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.UnknownBooking.selector, 999));
        escrow.cancelBooking(999);

        // 9. NotBookingParty
        vm.prank(dev);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.NotBookingParty.selector, bId, dev));
        escrow.cancelBooking(bId);

        // 10. TooLateToCancel (< 6h)
        vm.warp(startT - 5 hours);
        vm.prank(asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.TooLateToCancel.selector, bId));
        escrow.cancelBooking(bId);

        // 11. BookingClosed (>= startTime)
        vm.warp(startT);
        vm.prank(dev);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.BookingClosed.selector, sId));
        escrow.book(sId, dev);

        // 12. SessionAlreadyStarted
        vm.prank(ira);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.SessionAlreadyStarted.selector, sId));
        escrow.cancelSession(sId);

        // 13. NotSessionInstructor
        vm.prank(asha);
        vm.expectRevert(
            abi.encodeWithSelector(ISessionEscrow.NotSessionInstructor.selector, sId, asha)
        );
        escrow.cancelSession(sId);

        // 14. ClaimTooEarly
        vm.warp(startT + 23 hours);
        vm.prank(ira);
        vm.expectRevert(
            abi.encodeWithSelector(ISessionEscrow.ClaimTooEarly.selector, sId, startT + 24 hours)
        );
        escrow.claimEarnings(sId);

        // Claim earnings
        vm.warp(startT + 24 hours);
        vm.prank(ira);
        escrow.claimEarnings(sId);

        // 15. AlreadyClaimed
        vm.prank(ira);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.AlreadyClaimed.selector, sId));
        escrow.claimEarnings(sId);

        // 16. FeeTooHigh
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.FeeTooHigh.selector, 1201));
        escrow.setFeeBps(1201);

        // Setup session for SessionNotActive, BookingNotActive, RefundNotAvailable, NothingToClaim
        vm.warp(startT + 25 hours);
        vm.prank(ira);
        uint256 s2 = escrow.createSession(startT + 100 hours, 1000, 2);

        // 17. NothingToClaim
        vm.warp(startT + 125 hours);
        vm.prank(ira);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.NothingToClaim.selector, s2));
        escrow.claimEarnings(s2);

        // Cancel session testing
        vm.prank(ira);
        uint256 s3 = escrow.createSession(startT + 200 hours, 1000, 2);
        vm.prank(asha);
        uint256 b3 = escrow.book(s3, asha);

        // 18. RefundNotAvailable (session not cancelled)
        vm.prank(asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.RefundNotAvailable.selector, b3));
        escrow.claimRefund(b3);

        // Cancel s3
        vm.prank(ira);
        escrow.cancelSession(s3);

        // 19. SessionNotActive
        vm.prank(ira);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.SessionNotActive.selector, s3));
        escrow.cancelSession(s3);

        vm.prank(asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.SessionNotActive.selector, s3));
        escrow.book(s3, asha);

        vm.prank(asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.SessionNotActive.selector, s3));
        escrow.cancelBooking(b3);

        // Claim refund succeeds
        vm.prank(asha);
        escrow.claimRefund(b3);

        // 20. BookingNotActive
        vm.prank(asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.BookingNotActive.selector, b3));
        escrow.cancelBooking(b3);
    }

    // ==========================================
    // T4: Access Control
    // ==========================================
    function test_T4_accessControlMatrix() public {
        uint64 startT = 1795860000;
        vm.warp(1795341600);

        // Non-instructor cannot createSession
        vm.prank(asha);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, asha, INSTRUCTOR_ROLE
            )
        );
        escrow.createSession(startT, 1000, 5);

        // Non-admin cannot setFeeBps
        vm.prank(asha);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, asha, DEFAULT_ADMIN_ROLE
            )
        );
        escrow.setFeeBps(500);

        // Non-pauser cannot pause/unpause
        vm.prank(asha);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, asha, PAUSER_ROLE
            )
        );
        escrow.pause();

        vm.prank(asha);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, asha, PAUSER_ROLE
            )
        );
        escrow.unpause();

        // Non-session-instructor cannot cancel session or claim earnings
        vm.prank(ira);
        uint256 sId = escrow.createSession(startT, 1000, 5);

        address otherInstructor = address(0x99);
        vm.prank(admin);
        escrow.grantRole(INSTRUCTOR_ROLE, otherInstructor);

        vm.prank(otherInstructor);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionEscrow.NotSessionInstructor.selector, sId, otherInstructor
            )
        );
        escrow.cancelSession(sId);

        vm.warp(startT + 24 hours);
        vm.prank(otherInstructor);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionEscrow.NotSessionInstructor.selector, sId, otherInstructor
            )
        );
        escrow.claimEarnings(sId);
    }

    // ==========================================
    // T5: Exact Boundaries to the Second
    // ==========================================
    function test_T5_boundary_createSession() public {
        uint64 startT = 1795860000;

        // Fresh deployment 1
        SessionEscrow escrow1 = new SessionEscrow(address(token), treasury, admin);
        vm.prank(admin);
        escrow1.grantRole(INSTRUCTOR_ROLE, ira);

        vm.warp(1795600800); // Exactly 72h before
        vm.prank(ira);
        uint256 s1 = escrow1.createSession(startT, 1250, 3);
        assertEq(s1, 1);

        // Fresh deployment 2
        SessionEscrow escrow2 = new SessionEscrow(address(token), treasury, admin);
        vm.prank(admin);
        escrow2.grantRole(INSTRUCTOR_ROLE, ira);

        vm.warp(1795600801); // 72h - 1s
        vm.prank(ira);
        vm.expectRevert(
            abi.encodeWithSelector(ISessionEscrow.StartTooSoon.selector, startT, 1795860001)
        );
        escrow2.createSession(startT, 1250, 3);
    }

    function _deployFresh() internal returns (StudioCredit tok, SessionEscrow esc) {
        tok = new StudioCredit(admin);
        esc = new SessionEscrow(address(tok), treasury, admin);

        vm.startPrank(admin);
        tok.grantRole(ISSUER_ROLE, issuer);
        tok.setEscrow(address(esc));
        esc.grantRole(INSTRUCTOR_ROLE, ira);
        vm.stopPrank();
    }

    function _issueAndApproveWith(StudioCredit tok, SessionEscrow esc, address user, uint256 amount)
        internal
    {
        vm.prank(issuer);
        tok.issue(user, amount);

        vm.prank(user);
        tok.approve(address(esc), type(uint256).max);
    }

    function _createAndBookSession(StudioCredit tok, SessionEscrow esc, uint64 startT) internal {
        vm.warp(1795341600);
        vm.prank(ira);
        esc.createSession(startT, 1250, 3);

        _issueAndApproveWith(tok, esc, asha, 5000);

        vm.warp(1795428000);
        vm.prank(asha);
        esc.book(1, asha);
    }

    function test_T5_boundary_cancelBooking() public {
        uint64 startT = 1795860000;

        // Row: T - 48h refunds 100%
        (StudioCredit t1, SessionEscrow e1) = _deployFresh();
        _createAndBookSession(t1, e1, startT);
        vm.warp(1795687200);
        vm.prank(asha);
        e1.cancelBooking(1);
        assertEq(t1.balanceOf(asha), 5000);

        // Row: T - 48h + 1s refunds 60%
        (StudioCredit t2, SessionEscrow e2) = _deployFresh();
        _createAndBookSession(t2, e2, startT);
        vm.warp(1795687201);
        vm.prank(asha);
        e2.cancelBooking(1);
        assertEq(t2.balanceOf(asha), 5000 - 1250 + 750); // 750 refunded

        // Row: T - 6h refunds 60%
        (StudioCredit t3, SessionEscrow e3) = _deployFresh();
        _createAndBookSession(t3, e3, startT);
        vm.warp(1795838400);
        vm.prank(asha);
        e3.cancelBooking(1);
        assertEq(t3.balanceOf(asha), 5000 - 1250 + 750);

        // Row: T - 6h + 1s reverts TooLateToCancel
        (StudioCredit t4, SessionEscrow e4) = _deployFresh();
        _createAndBookSession(t4, e4, startT);
        vm.warp(1795838401);
        vm.prank(asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.TooLateToCancel.selector, 1));
        e4.cancelBooking(1);

        // Row: T + 1h reverts TooLateToCancel
        (StudioCredit t5, SessionEscrow e5) = _deployFresh();
        _createAndBookSession(t5, e5, startT);
        vm.warp(1795863600);
        vm.prank(asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.TooLateToCancel.selector, 1));
        e5.cancelBooking(1);
    }

    function test_T5_boundary_book() public {
        uint64 startT = 1795860000;

        // Row: T - 1s succeeds
        (StudioCredit t1, SessionEscrow e1) = _deployFresh();
        vm.warp(1795341600);
        vm.prank(ira);
        e1.createSession(startT, 1250, 3);
        _issueAndApproveWith(t1, e1, asha, 5000);

        vm.warp(1795859999);
        vm.prank(asha);
        uint256 b1 = e1.book(1, asha);
        assertEq(b1, 1);

        // Row: T reverts BookingClosed(1)
        (StudioCredit t2, SessionEscrow e2) = _deployFresh();
        vm.warp(1795341600);
        vm.prank(ira);
        e2.createSession(startT, 1250, 3);
        _issueAndApproveWith(t2, e2, asha, 5000);

        vm.warp(1795860000);
        vm.prank(asha);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.BookingClosed.selector, 1));
        e2.book(1, asha);
    }

    function test_T5_boundary_cancelSession() public {
        uint64 startT = 1795860000;

        // Row: T - 1s succeeds
        (, SessionEscrow e1) = _deployFresh();
        vm.warp(1795341600);
        vm.prank(ira);
        e1.createSession(startT, 1250, 3);

        vm.warp(1795859999);
        vm.prank(ira);
        e1.cancelSession(1);

        // Row: T reverts SessionAlreadyStarted(1)
        (, SessionEscrow e2) = _deployFresh();
        vm.warp(1795341600);
        vm.prank(ira);
        e2.createSession(startT, 1250, 3);

        vm.warp(1795860000);
        vm.prank(ira);
        vm.expectRevert(abi.encodeWithSelector(ISessionEscrow.SessionAlreadyStarted.selector, 1));
        e2.cancelSession(1);
    }

    function test_T5_boundary_claimEarnings() public {
        uint64 startT = 1795860000;

        // Row: T + 24h - 1s reverts ClaimTooEarly(1, T + 24h)
        (StudioCredit t1, SessionEscrow e1) = _deployFresh();
        _createAndBookSession(t1, e1, startT);
        vm.warp(1795946399);
        vm.prank(ira);
        vm.expectRevert(
            abi.encodeWithSelector(ISessionEscrow.ClaimTooEarly.selector, 1, 1795946400)
        );
        e1.claimEarnings(1);

        // Row: T + 24h succeeds
        (StudioCredit t2, SessionEscrow e2) = _deployFresh();
        _createAndBookSession(t2, e2, startT);
        vm.warp(1795946400);
        vm.prank(ira);
        e2.claimEarnings(1);
    }

    // ==========================================
    // T6: Fuzz Late Split
    // ==========================================
    function testFuzz_T6_lateSplit(uint256 seatPrice, uint256 warpOffset) public {
        seatPrice = bound(seatPrice, 100, 500_000);
        warpOffset = bound(warpOffset, 6 hours, 48 hours - 1 seconds);

        uint64 startT = 1795860000;
        (StudioCredit fuzzToken, SessionEscrow fuzzEscrow) = _deployFresh();

        vm.warp(1795341600);
        vm.prank(ira);
        fuzzEscrow.createSession(startT, seatPrice, 2);

        _issueAndApproveWith(fuzzToken, fuzzEscrow, asha, seatPrice);

        vm.warp(1795428000);
        vm.prank(asha);
        fuzzEscrow.book(1, asha);

        uint256 cancelTime = startT - warpOffset;
        vm.warp(cancelTime);

        uint256 balBefore = fuzzToken.balanceOf(asha);
        vm.prank(asha);
        fuzzEscrow.cancelBooking(1);
        uint256 balAfter = fuzzToken.balanceOf(asha);

        uint256 refunded = balAfter - balBefore;
        uint256 expectedRefund = (seatPrice * 6_000) / 10_000;
        uint256 retained = seatPrice - refunded;

        assertEq(refunded, expectedRefund);
        assertEq(refunded + retained, seatPrice);
    }

    // ==========================================
    // T7: Fuzz Platform Fee
    // ==========================================
    function testFuzz_T7_feeCalculation(uint256 seatPrice, uint16 feeBps) public {
        seatPrice = bound(seatPrice, 100, 500_000);
        feeBps = uint16(bound(feeBps, 0, 1_200));

        uint64 startT = 1795860000;
        (StudioCredit fuzzToken, SessionEscrow fuzzEscrow) = _deployFresh();
        vm.prank(admin);
        fuzzEscrow.setFeeBps(feeBps);

        vm.warp(1795341600);
        vm.prank(ira);
        fuzzEscrow.createSession(startT, seatPrice, 2);

        _issueAndApproveWith(fuzzToken, fuzzEscrow, asha, seatPrice);

        vm.warp(1795428000);
        vm.prank(asha);
        fuzzEscrow.book(1, asha);

        vm.warp(startT + 24 hours);

        uint256 treasuryBefore = fuzzToken.balanceOf(treasury);
        uint256 instructorBefore = fuzzToken.balanceOf(ira);

        vm.prank(ira);
        fuzzEscrow.claimEarnings(1);

        uint256 treasuryChange = fuzzToken.balanceOf(treasury) - treasuryBefore;
        uint256 instructorChange = fuzzToken.balanceOf(ira) - instructorBefore;

        assertEq(treasuryChange + instructorChange, seatPrice);
        assertGe(treasuryChange * 10_000, seatPrice * feeBps);
        if (treasuryChange > 0) {
            assertLt((treasuryChange - 1) * 10_000, seatPrice * feeBps);
        }
    }

    // ==========================================
    // T8: Pause Matrix
    // ==========================================
    function test_T8_pauseMatrix() public {
        uint64 startT = 1795860000;
        vm.warp(1795341600);
        vm.prank(ira);
        uint256 sId = escrow.createSession(startT, 1000, 5);

        _issueAndApprove(asha, 5000);

        // Pause contract
        vm.prank(admin);
        escrow.pause();

        // book reverts EnforcedPause
        vm.prank(asha);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.book(sId, asha);

        // claimEarnings reverts EnforcedPause
        vm.warp(startT + 24 hours);
        vm.prank(ira);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.claimEarnings(sId);

        // Unpause to create an active booking
        vm.prank(admin);
        escrow.unpause();

        vm.warp(1795428000);
        vm.prank(asha);
        uint256 bId = escrow.book(sId, asha);

        // Re-pause
        vm.prank(admin);
        escrow.pause();

        // cancelBooking reverts EnforcedPause
        vm.prank(asha);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.cancelBooking(bId);

        // cancelSession is allowed while paused (no credits move)
        vm.prank(ira);
        escrow.cancelSession(sId);

        // claimRefund reverts EnforcedPause (credits cannot move)
        vm.prank(asha);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.claimRefund(bId);

        // Unpause allows claimRefund
        vm.prank(admin);
        escrow.unpause();

        vm.prank(asha);
        escrow.claimRefund(bId);
        assertEq(token.balanceOf(asha), 5000);
    }

    // ==========================================
    // T9: Dedicated Decision Tests
    // ==========================================
    function test_D1_fractionalRefundRounding() public {
        // Seat price 1,001 -> 60% = 600.6
        // Learner gets 600 (floor), instructor retains 401 (ceiling)
        uint64 startT = 1795860000;
        (StudioCredit dToken, SessionEscrow dEscrow) = _deployFresh();

        vm.warp(1795341600);
        vm.prank(ira);
        dEscrow.createSession(startT, 1001, 2);

        _issueAndApproveWith(dToken, dEscrow, asha, 1001);

        vm.warp(1795428000);
        vm.prank(asha);
        dEscrow.book(1, asha);

        // Cancel at T - 30h (late refund tier)
        vm.warp(startT - 30 hours);
        vm.prank(asha);
        dEscrow.cancelBooking(1);

        assertEq(dToken.balanceOf(asha), 600); // 600 refunded
        assertEq(dToken.balanceOf(address(dEscrow)), 401); // 401 retained for instructor
    }

    function test_D2_whichFeeRateApplies() public {
        // Admin updates feeBps after session creation.
        // D2 Choice: Rate is locked at session creation time (350 bps).
        uint64 startT = 1795860000;
        vm.warp(1795341600);
        vm.prank(ira);
        uint256 sId = escrow.createSession(startT, 1000, 2);

        _issueAndApprove(asha, 1000);
        vm.warp(1795428000);
        vm.prank(asha);
        escrow.book(sId, asha);

        // Admin hikes fee to 12% (1,200 bps) before claim
        vm.prank(admin);
        escrow.setFeeBps(1200);
        assertEq(escrow.feeBps(), 1200);

        // Claim applies snapshot rate (350 bps = 3.5%) -> fee = 35, net = 965
        vm.warp(startT + 24 hours);
        vm.expectEmit(true, true, false, true, address(escrow));
        emit EarningsClaimed(sId, ira, 1000, 350, 35, 965);
        vm.prank(ira);
        escrow.claimEarnings(sId);

        assertEq(token.balanceOf(treasury), 35);
        assertEq(token.balanceOf(ira), 965);
    }

    function test_D3_giftBookingCancellationAndRefund() public {
        // Bhavesh pays for Chitra
        uint64 startT = 1795860000;
        vm.warp(1795341600);
        vm.prank(ira);
        uint256 sId = escrow.createSession(startT, 1000, 2);

        _issueAndApprove(bhavesh, 1000);

        vm.warp(1795428000);
        vm.prank(bhavesh);
        uint256 bId = escrow.book(sId, chitra);

        // Attendee Chitra triggers cancellation at T - 49h (100% refund)
        vm.warp(startT - 49 hours);
        vm.prank(chitra);
        escrow.cancelBooking(bId);

        // Refund goes to payer Bhavesh, NOT attendee Chitra
        assertEq(token.balanceOf(bhavesh), 1000);
        assertEq(token.balanceOf(chitra), 0);
    }

    function test_SessionEscrow_bookingStatus_views() public view {
        assertEq(uint8(escrow.bookingStatus(0)), uint8(ISessionEscrow.BookingStatus.None));
        assertEq(uint8(escrow.bookingStatus(999)), uint8(ISessionEscrow.BookingStatus.None));
    }
}
