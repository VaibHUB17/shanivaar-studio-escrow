// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IStudioCredit } from "./interfaces/IStudioCredit.sol";

/// @title StudioCredit
/// @notice Non-transferable credit token for Shanivaar Studio workshop seat bookings.
/// @dev Implements ERC-20 with decimals = 2 and restricts token transfers strictly to/from the escrow contract.
contract StudioCredit is ERC20, AccessControl, IStudioCredit {
    /// @notice Role authorized to issue new credits.
    bytes32 public constant override ISSUER_ROLE = keccak256("ISSUER_ROLE");

    /// @notice Address of the designated SessionEscrow contract.
    address public override escrow;

    /// @notice Decimals configured for the credit token (1.00 credit = 100 units).
    uint8 private constant DECIMALS = 2;

    /// @notice Initializes the Studio Credit token contract.
    /// @dev Grants DEFAULT_ADMIN_ROLE to `admin`. The admin cannot issue credits unless explicitly granted ISSUER_ROLE.
    /// @param admin The initial administrator address.
    constructor(address admin) ERC20("Studio Credit", "SCRD") {
        if (admin == address(0)) {
            revert ZeroAddress();
        }
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Returns the number of decimals used by the token (2).
    /// @return The decimal places.
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /// @notice Issues (mints) new studio credits to a recipient.
    /// @dev Requires the caller to hold ISSUER_ROLE.
    /// @param to The address receiving the credits.
    /// @param amount The quantity of credit units to issue.
    function issue(address to, uint256 amount) external override onlyRole(ISSUER_ROLE) {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        _mint(to, amount);
        emit Issued(to, amount, msg.sender);
    }

    /// @notice Sets the authorized escrow contract address.
    /// @dev Can only be called once by an account with DEFAULT_ADMIN_ROLE.
    /// @param newEscrow The address of the SessionEscrow contract.
    function setEscrow(address newEscrow) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newEscrow == address(0)) {
            revert ZeroAddress();
        }
        if (escrow != address(0)) {
            revert EscrowAlreadySet();
        }

        escrow = newEscrow;
        emit EscrowSet(newEscrow);
    }

    /// @notice Enforces the non-transferability rule (R-NOTRANSFER).
    /// @dev Overrides OpenZeppelin v5's _update hook.
    /// - Minting (from == address(0)) is allowed.
    /// - Burning (to == address(0)) is prohibited.
    /// - Any other movement is only allowed if either `from` or `to` is the registered escrow contract.
    /// @param from The sender address.
    /// @param to The recipient address.
    /// @param value The amount of credit units being moved.
    function _update(address from, address to, uint256 value) internal override {
        // Issuance from zero address is allowed
        if (from == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Burning is not supported
        if (to == address(0)) {
            revert CreditsNotTransferable(from, to);
        }

        // Movements are only permitted to or from the escrow contract
        if (from != escrow && to != escrow) {
            revert CreditsNotTransferable(from, to);
        }

        super._update(from, to, value);
    }
}
