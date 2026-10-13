# Shanivaar Studio: Workshop Seat Escrow

This repository contains the smart contract implementation and comprehensive test suite for the **Shanivaar Studio** workshop seat escrow platform, built for the Hikari Infotech Blockchain Developer take-home assessment.

---

## 1. Prerequisites & Version Pinning

- **Foundry / Forge**: `1.8.5` (or higher)
- **Solidity (`solc`)**: `0.8.24` (pinned in `foundry.toml`)
- **OpenZeppelin Contracts**: `v5.0.2` (pinned git submodule tag)

---

## 2. Run From a Clean Clone (5 Commands or Fewer)

```bash
git clone https://github.com/VaibHUB17/hikari-assessment.git
cd hikari-assessment
git submodule update --init --recursive
forge build
forge test
```

To verify code formatting compliance:
```bash
forge fmt --check
```

---

## 3. Architecture & Key Contracts

- **`src/StudioCredit.sol`**: Non-transferable ERC-20 credit token (`SCRD`, 2 decimals). Overrides `_update` to strictly enforce requirement `R-NOTRANSFER` (credits cannot move between learners; all movement must touch the Escrow contract).
- **`src/SessionEscrow.sol`**: Manages workshop session lifecycles, capacity controls, windowed cancellations (100% or 60% with late retention), pull-based emergency refunds, and instructor earnings claims with fee ceiling math.
- **`src/interfaces/`**: Fixed interface definitions from Appendix A (`IStudioCredit.sol`, `ISessionEscrow.sol`).

---

## 4. Test Suite Coverage (T1 – T9)

All tests are implemented in `test/StudioCredit.t.sol` and `test/SessionEscrow.t.sol` and pass with **0 skipped tests**:

- **`T1_workedExample`**: Replays the Section 5 worked example across all 12 timestamps using `vm.warp`, validating exact intermediate balances, earnings events, and credit conservation.
- **`T2_movementRules`**: Verifies `CreditsNotTransferable` reverts on learner-to-learner `transfer` and `transferFrom`, while escrow interactions succeed.
- **`T3_allCustomErrorsCovered`**: Triggers all 4 `StudioCredit` and all 19 `SessionEscrow` custom errors by selector.
- **`T4_accessControlMatrix`**: Validates role gating for `DEFAULT_ADMIN_ROLE`, `ISSUER_ROLE`, `PAUSER_ROLE`, and `INSTRUCTOR_ROLE`.
- **`T5_boundaries`**: Exhaustively tests all boundary conditions to the exact second ($T - 72\text{h}$, $T - 48\text{h}$, $T - 6\text{h}$, $T$, $T + 24\text{h}$).
- **`T6_lateSplit`**: Property-based fuzz test across prices $[100, 500\,000]$ verifying $\text{refunded} + \text{retained} == \text{seatPrice}$.
- **`T7_feeCalculation`**: Property-based fuzz test across prices and fee basis points verifying ceiling division and balance conservation.
- **`T8_pauseMatrix`**: Verifies that `book`, `claimEarnings`, `cancelBooking`, and `claimRefund` are frozen during pause, satisfying `R-PAUSE`.
- **`T9_decisionTests`**: Dedicated unit tests pinning Decisions D1, D2, and D3 (`test_D1_fractionalRefundRounding`, `test_D2_whichFeeRateApplies`, `test_D3_giftBookingCancellationAndRefund`).

---

## 5. Architectural Decisions & Documentation

See [DECISIONS.md](DECISIONS.md) for in-depth coverage of:
- **Part 1**: Decisions D1, D2, and D3 with rejected alternatives and test names.
- **Part 2**: Analysis of instructor no-shows, trust assumptions, and attack vectors.
- **Part 3**: Conflicts and specification gaps (including the escrow balance remainder from cancelled sessions).
- **Part 4**: Threat model covering compromised roles and mitigations.
- **Part 5**: Core system invariants.

See [AI_USAGE.md](AI_USAGE.md) for full disclosure of AI tooling, prompts, and verified outputs.

---

## 6. Optional Extras Attempted & Next Steps

- **Attempted**: Complete coverage of all foundational and fuzz test tiers (T1 through T9).
- **Future Work**:
  1. Add an invariant handler test suite (`StdInvariant`) driving randomized caller actions over time.
  2. Implement an on-chain attendance verification mechanism (e.g. attendee QR code / signature check-in) to eliminate trust in instructor physical presence.
  3. Implement a residual penalty distribution sweep for cancelled sessions with retained late-cancel balances.
