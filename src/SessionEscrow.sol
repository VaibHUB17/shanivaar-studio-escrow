// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISessionEscrow } from "./interfaces/ISessionEscrow.sol";

/// @title SessionEscrow
/// @notice Manages session creation, seat bookings, cancellations, refunds, and earnings claims for Shanivaar Studio.
/// @dev Implements Appendix A ISessionEscrow interface with strict Checks-Effects-Interactions ordering.
contract SessionEscrow is AccessControl, Pausable, ISessionEscrow {
    // --- Constants ---
    uint256 public constant MIN_LEAD_TIME = 72 hours;
    uint256 public constant FULL_REFUND_NOTICE = 48 hours;
    uint256 public constant CANCEL_CUTOFF = 6 hours;
    uint256 public constant CLAIM_DELAY = 24 hours;
    uint256 public constant LATE_REFUND_BPS = 6_000;
    uint256 public constant MIN_SEAT_PRICE = 100;
    uint256 public constant MAX_SEAT_PRICE = 500_000;
    uint16 public constant MAX_CAPACITY = 40;
    uint16 public constant DEFAULT_FEE_BPS = 350;
    uint16 public constant MAX_FEE_BPS = 1_200;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // --- Role Constants ---
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant override INSTRUCTOR_ROLE = keccak256("INSTRUCTOR_ROLE");

    // --- Data Structures ---
    struct Session {
        address instructor;
        uint64 startTime;
        uint256 seatPrice;
        uint16 capacity;
        uint16 seatsLeft;
        uint16 activeBookings;
        uint256 retainedLateCancel;
        uint16 feeBpsAtCreation;
        bool cancelled;
        bool claimed;
    }

    struct Booking {
        uint256 sessionId;
        address payer;
        address attendee;
        uint256 price;
        BookingStatus status;
    }

    // --- Immutables & State Variables ---
    IERC20 public immutable token;
    address public immutable treasury;

    uint16 private _feeBps;
    uint256 private _nextSessionId;
    uint256 private _nextBookingId;

    mapping(uint256 => Session) private _sessions;
    mapping(uint256 => Booking) private _bookings;

    /// @notice Initializes the SessionEscrow contract.
    /// @param token_ Address of the StudioCredit ERC20 token.
    /// @param treasury_ Address where platform fees are deposited.
    /// @param admin Address granted DEFAULT_ADMIN_ROLE and PAUSER_ROLE.
    constructor(address token_, address treasury_, address admin) {
        if (token_ == address(0) || treasury_ == address(0) || admin == address(0)) {
            revert ZeroAddress();
        }

        token = IERC20(token_);
        treasury = treasury_;
        _feeBps = DEFAULT_FEE_BPS;
        _nextSessionId = 1;
        _nextBookingId = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // --- External Functions ---

    /// @notice Creates a new workshop session.
    /// @dev Caller must hold INSTRUCTOR_ROLE. Session starts at least 72 hours from creation.
    /// @param startTime Unix timestamp when the workshop starts.
    /// @param seatPrice Cost per seat in Studio Credit units (between 100 and 500,000).
    /// @param capacity Total number of seats available (between 1 and 40).
    /// @return sessionId The unique identifier for the created session.
    function createSession(uint64 startTime, uint256 seatPrice, uint16 capacity)
        external
        override
        onlyRole(INSTRUCTOR_ROLE)
        returns (uint256 sessionId)
    {
        uint256 earliestStart = block.timestamp + MIN_LEAD_TIME;
        if (startTime < earliestStart) {
            revert StartTooSoon(startTime, earliestStart);
        }
        if (seatPrice < MIN_SEAT_PRICE || seatPrice > MAX_SEAT_PRICE) {
            revert InvalidPrice(seatPrice);
        }
        if (capacity < 1 || capacity > MAX_CAPACITY) {
            revert InvalidCapacity(capacity);
        }

        sessionId = _nextSessionId++;
        _sessions[sessionId] = Session({
            instructor: msg.sender,
            startTime: startTime,
            seatPrice: seatPrice,
            capacity: capacity,
            seatsLeft: capacity,
            activeBookings: 0,
            retainedLateCancel: 0,
            feeBpsAtCreation: _feeBps,
            cancelled: false,
            claimed: false
        });

        emit SessionCreated(sessionId, msg.sender, startTime, seatPrice, capacity);
    }

    /// @notice Books a seat in an active workshop session.
    /// @dev Pulls `seatPrice` tokens from the caller (the payer). Attendee can be a third party (gift booking).
    /// @param sessionId The ID of the session to book.
    /// @param attendee The address of the person who will attend the workshop.
    /// @return bookingId The unique global identifier for the booking.
    function book(uint256 sessionId, address attendee)
        external
        override
        whenNotPaused
        returns (uint256 bookingId)
    {
        if (sessionId == 0 || sessionId >= _nextSessionId) {
            revert UnknownSession(sessionId);
        }

        Session storage session = _sessions[sessionId];

        if (session.cancelled) {
            revert SessionNotActive(sessionId);
        }
        if (block.timestamp >= session.startTime) {
            revert BookingClosed(sessionId);
        }
        if (session.seatsLeft == 0) {
            revert SessionFull(sessionId);
        }
        if (attendee == address(0)) {
            revert ZeroAddress();
        }

        session.seatsLeft--;
        session.activeBookings++;

        bookingId = _nextBookingId++;
        _bookings[bookingId] = Booking({
            sessionId: sessionId,
            payer: msg.sender,
            attendee: attendee,
            price: session.seatPrice,
            status: BookingStatus.Active
        });

        emit Booked(bookingId, sessionId, msg.sender, attendee, session.seatPrice);

        bool success = token.transferFrom(msg.sender, address(this), session.seatPrice);
        require(success);
    }

    /// @notice Cancels an active booking and issues a full or partial refund.
    /// @dev Notice window determines refund percentage:
    /// - notice >= 48 hours: 100% refund, 0% retained.
    /// - 6 <= notice < 48 hours: 60% refund (floor), remainder retained for instructor (D1).
    /// - notice < 6 hours or session started: reverts TooLateToCancel.
    /// Refund is always returned to the original payer (D3).
    /// @param bookingId The ID of the booking to cancel.
    function cancelBooking(uint256 bookingId) external override whenNotPaused {
        if (bookingId == 0 || bookingId >= _nextBookingId) {
            revert UnknownBooking(bookingId);
        }

        Booking storage booking = _bookings[bookingId];
        if (booking.status != BookingStatus.Active) {
            revert BookingNotActive(bookingId);
        }

        Session storage session = _sessions[booking.sessionId];
        if (session.cancelled) {
            revert SessionNotActive(booking.sessionId);
        }

        // Caller must be payer or attendee (D3)
        if (msg.sender != booking.payer && msg.sender != booking.attendee) {
            revert NotBookingParty(bookingId, msg.sender);
        }

        if (block.timestamp >= session.startTime) {
            revert TooLateToCancel(bookingId);
        }

        uint256 notice = session.startTime - block.timestamp;
        if (notice < CANCEL_CUTOFF) {
            revert TooLateToCancel(bookingId);
        }

        uint256 refunded;
        uint256 retained;

        if (notice >= FULL_REFUND_NOTICE) {
            refunded = booking.price;
            retained = 0;
        } else {
            // 6 hours <= notice < 48 hours: 60% refund, 40% retained
            // Decision D1: Fractional unit favors the instructor (integer division floors for learner)
            refunded = (booking.price * LATE_REFUND_BPS) / BPS_DENOMINATOR;
            retained = booking.price - refunded;
        }

        booking.status = BookingStatus.Cancelled;
        session.seatsLeft++;
        session.activeBookings--;
        session.retainedLateCancel += retained;

        address refundTo = booking.payer;
        emit BookingCancelled(bookingId, msg.sender, refundTo, refunded, retained);

        if (refunded > 0) {
            bool success = token.transfer(refundTo, refunded);
            require(success);
        }
    }

    /// @notice Cancels an entire session before its start time.
    /// @dev Restricted to the session's recorded instructor. Active bookings become eligible for full refund via claimRefund.
    /// @param sessionId The ID of the session to cancel.
    function cancelSession(uint256 sessionId) external override {
        if (sessionId == 0 || sessionId >= _nextSessionId) {
            revert UnknownSession(sessionId);
        }

        Session storage session = _sessions[sessionId];

        if (msg.sender != session.instructor) {
            revert NotSessionInstructor(sessionId, msg.sender);
        }
        if (block.timestamp >= session.startTime) {
            revert SessionAlreadyStarted(sessionId);
        }
        if (session.cancelled) {
            revert SessionNotActive(sessionId);
        }

        session.cancelled = true;
        emit SessionCancelled(sessionId, msg.sender);
    }

    /// @notice Claims a 100% refund for a booking after an instructor cancels the session.
    /// @dev Pull-based refund. Reverts if session was not cancelled or booking is not active.
    /// Refund is paid to the original payer (D3). Caller can be payer or attendee.
    /// @param bookingId The ID of the booking to refund.
    function claimRefund(uint256 bookingId) external override whenNotPaused {
        if (bookingId == 0 || bookingId >= _nextBookingId) {
            revert UnknownBooking(bookingId);
        }

        Booking storage booking = _bookings[bookingId];
        Session storage session = _sessions[booking.sessionId];

        if (!session.cancelled || booking.status != BookingStatus.Active) {
            revert RefundNotAvailable(bookingId);
        }

        if (msg.sender != booking.payer && msg.sender != booking.attendee) {
            revert NotBookingParty(bookingId, msg.sender);
        }

        booking.status = BookingStatus.Refunded;
        address refundTo = booking.payer;
        uint256 amount = booking.price;

        emit RefundClaimed(bookingId, refundTo, amount);

        bool success = token.transfer(refundTo, amount);
        require(success);
    }

    /// @notice Claims session earnings 24 hours after session start.
    /// @dev Restricted to the recorded instructor. Deducts platform fee and transfers net takings.
    /// @param sessionId The ID of the session whose earnings are being claimed.
    function claimEarnings(uint256 sessionId) external override whenNotPaused {
        if (sessionId == 0 || sessionId >= _nextSessionId) {
            revert UnknownSession(sessionId);
        }

        Session storage session = _sessions[sessionId];

        if (msg.sender != session.instructor) {
            revert NotSessionInstructor(sessionId, msg.sender);
        }
        if (session.cancelled) {
            revert SessionNotActive(sessionId);
        }
        if (session.claimed) {
            revert AlreadyClaimed(sessionId);
        }

        uint256 claimableAt = session.startTime + CLAIM_DELAY;
        if (block.timestamp < claimableAt) {
            revert ClaimTooEarly(sessionId, claimableAt);
        }

        uint256 gross = (session.seatPrice * session.activeBookings) + session.retainedLateCancel;
        if (gross == 0) {
            revert NothingToClaim(sessionId);
        }

        session.claimed = true;

        // Decision D2: Fee rate locked at session creation time
        uint16 feeBpsApplied = session.feeBpsAtCreation;

        // Fee ceiling: ceil(gross * feeBps / 10_000)
        uint256 fee = 0;
        if (gross > 0 && feeBpsApplied > 0) {
            fee = (gross * feeBpsApplied + BPS_DENOMINATOR - 1) / BPS_DENOMINATOR;
        }
        uint256 net = gross - fee;

        emit EarningsClaimed(sessionId, session.instructor, gross, feeBpsApplied, fee, net);

        if (fee > 0) {
            bool feeSuccess = token.transfer(treasury, fee);
            require(feeSuccess);
        }
        if (net > 0) {
            bool netSuccess = token.transfer(session.instructor, net);
            require(netSuccess);
        }
    }

    /// @notice Updates the platform fee basis points.
    /// @dev Callable by DEFAULT_ADMIN_ROLE only. Must not exceed MAX_FEE_BPS (1,200).
    /// @param newBps The new fee basis points (between 0 and 1,200).
    function setFeeBps(uint16 newBps) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newBps > MAX_FEE_BPS) {
            revert FeeTooHigh(newBps);
        }

        uint16 oldBps = _feeBps;
        _feeBps = newBps;
        emit FeeBpsSet(oldBps, newBps);
    }

    /// @notice Pauses contract token transfers and booking operations.
    /// @dev Restricted to PAUSER_ROLE.
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev Restricted to PAUSER_ROLE.
    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // --- View Functions ---

    /// @notice Returns the current platform fee in basis points.
    /// @return Current fee in basis points.
    function feeBps() external view override returns (uint16) {
        return _feeBps;
    }

    /// @notice Returns the number of available seats remaining in a session.
    /// @param sessionId The ID of the session to inspect.
    /// @return Available seats.
    function seatsLeft(uint256 sessionId) external view override returns (uint16) {
        if (sessionId == 0 || sessionId >= _nextSessionId) {
            revert UnknownSession(sessionId);
        }
        return _sessions[sessionId].seatsLeft;
    }

    /// @notice Returns the status of a booking.
    /// @dev Returns BookingStatus.None for IDs that do not exist (does not revert).
    /// @param bookingId The ID of the booking to query.
    /// @return The status of the booking.
    function bookingStatus(uint256 bookingId) external view override returns (BookingStatus) {
        if (bookingId == 0 || bookingId >= _nextBookingId) {
            return BookingStatus.None;
        }
        return _bookings[bookingId].status;
    }
}
