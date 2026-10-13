// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Fixed interface of contract StudioCredit in src/StudioCredit.sol.
/// constructor(address admin): grants DEFAULT_ADMIN_ROLE to admin only;
/// reverts ZeroAddress() if admin is zero.
/// name() == "Studio Credit", symbol() == "SCRD", decimals() == 2.
interface IStudioCredit {
    /// @notice Emitted when credits are issued to `to` by `issuer`.
    event Issued(address indexed to, uint256 amount, address indexed issuer);
    /// @notice Emitted once, when the escrow address is set.
    event EscrowSet(address indexed newEscrow);

    error ZeroAmount();
    error ZeroAddress();
    error EscrowAlreadySet();
    error CreditsNotTransferable(address from, address to);

    /// @dev bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    function ISSUER_ROLE() external view returns (bytes32);

    function issue(address to, uint256 amount) external;
    function setEscrow(address newEscrow) external;
    function escrow() external view returns (address);
}
