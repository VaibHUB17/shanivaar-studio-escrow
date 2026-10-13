// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Fixed interface of contract SessionEscrow in src/SessionEscrow.sol.
/// constructor(address token, address treasury, address admin):
/// admin gets DEFAULT_ADMIN_ROLE and PAUSER_ROLE; feeBps starts at 350.
interface ISessionEscrow {
    enum BookingStatus {
        None,
        Active,
        Cancelled,
        Refunded
    }

    /// @notice Emitted when an instructor creates a session.
    event SessionCreated(
        uint256 indexed sessionId,
        address indexed instructor,
        uint64 startTime,
        uint256 seatPrice,
        uint16 capacity
    );

    /// @notice Emitted when a seat is booked; `payer` funded it, `attendee` holds the seat.
    event Booked(
        uint256 indexed bookingId,
        uint256 indexed sessionId,
        address indexed payer,
        address attendee,
        uint256 price
    );

    /// @notice Emitted when a booking is cancelled; `refunded + retained` equals the seat price.
    event BookingCancelled(
        uint256 indexed bookingId,
        address indexed by,
        address indexed refundTo,
        uint256 refunded,
        uint256 retained
    );

    /// @notice Emitted when an instructor cancels a whole session.
    event SessionCancelled(uint256 indexed sessionId, address indexed by);
    /// @notice Emitted when a booking in a cancelled session is refunded in full.
    event RefundClaimed(uint256 indexed bookingId, address indexed to, uint256 amount);
    /// @notice Emitted when an instructor claims earnings; `fee + net` equals `gross`.
    event EarningsClaimed(
        uint256 indexed sessionId,
        address indexed instructor,
        uint256 gross,
        uint16 feeBps,
        uint256 fee,
        uint256 net
    );

    /// @notice Emitted when the admin changes the platform fee.
    event FeeBpsSet(uint16 oldBps, uint16 newBps);

    error ZeroAddress();
    error UnknownSession(uint256 sessionId);
    error UnknownBooking(uint256 bookingId);
    error StartTooSoon(uint64 startTime, uint256 earliestStart);
    error InvalidPrice(uint256 price);
    error InvalidCapacity(uint16 capacity);
    error SessionNotActive(uint256 sessionId);
    error BookingClosed(uint256 sessionId);
    error SessionFull(uint256 sessionId);
    error BookingNotActive(uint256 bookingId);
    error TooLateToCancel(uint256 bookingId);
    error NotBookingParty(uint256 bookingId, address caller);
    error NotSessionInstructor(uint256 sessionId, address caller);
    error SessionAlreadyStarted(uint256 sessionId);
    error RefundNotAvailable(uint256 bookingId);
    error ClaimTooEarly(uint256 sessionId, uint256 claimableAt);
    error AlreadyClaimed(uint256 sessionId);
    error NothingToClaim(uint256 sessionId);
    error FeeTooHigh(uint16 bps);

    /// @dev keccak256("PAUSER_ROLE") and keccak256("INSTRUCTOR_ROLE")
    function PAUSER_ROLE() external view returns (bytes32);
    function INSTRUCTOR_ROLE() external view returns (bytes32);

    function createSession(uint64 startTime, uint256 seatPrice, uint16 capacity)
        external
        returns (uint256 sessionId);

    function book(uint256 sessionId, address attendee) external returns (uint256 bookingId);

    function cancelBooking(uint256 bookingId) external;
    function cancelSession(uint256 sessionId) external;
    function claimRefund(uint256 bookingId) external;
    function claimEarnings(uint256 sessionId) external;
    function setFeeBps(uint16 newBps) external;
    function pause() external;
    function unpause() external;

    function feeBps() external view returns (uint16);
    function seatsLeft(uint256 sessionId) external view returns (uint16);
    function bookingStatus(uint256 bookingId) external view returns (BookingStatus);
}
