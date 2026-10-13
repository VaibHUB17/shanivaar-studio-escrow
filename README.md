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
git clone https://github.com/VaibHUB17/shanivaar-studio-escrow.git
cd shanivaar-studio-escrow
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

- **T1** `test_T1_workedExample`: Replays the Section 5 worked example across all 12 timestamps using `vm.warp`, asserting `seatsLeft` after every booking and cancellation, the `EarningsClaimed` event, and where every credit ends up.
- **T2** `test_T2_*` (in `StudioCredit.t.sol`): `CreditsNotTransferable` on learner-to-learner `transfer` and `transferFrom`, successful escrow pulls and payouts, and `issue` / `setEscrow` access control and validation.
- **T3** `test_T3_allCustomErrorsCovered`, `test_T3_constructorZeroAddress`, plus the `StudioCredit.t.sol` tests: all 4 `StudioCredit` and all 19 `SessionEscrow` custom errors.
- **T4** `test_T4_accessControlMatrix`: Role gating for `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `INSTRUCTOR_ROLE`, and the per-session instructor checks.
- **T5** `test_T5_boundary_*`: Every Section 6 boundary pair, to the exact second.
- **T6** `testFuzz_T6_lateSplit`: Prices in $[100, 500\,000]$ across the whole 60% tier; checks `refunded + retained == seatPrice` from balances and the `BookingCancelled` event, and the D1 floor direction.
- **T7** `testFuzz_T7_feeCalculation`: Prices and fee bps; checks ceiling-division bounds and balance conservation.
- **T8** `test_T8_pauseMatrix`, `test_T8_createSessionAllowedWhilePaused`, `test_T8_unknownIdRevertsBeforePauseCheck`: `book`, `claimEarnings`, `cancelBooking` and `claimRefund` freeze while paused; `createSession` and `cancelSession` stay open; unknown ids still revert `UnknownSession` / `UnknownBooking` first.
- **T9** `test_D1_fractionalRefundRounding`, `test_D2_whichFeeRateApplies`, `test_D3_giftBookingCancellationAndRefund`, `test_D3_giftBookingClaimRefundAndStranger`.

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

## 6. Optional Extras, Unfinished Work & Next Steps

- **Optional extra attempted**: None (S1–S3 not attempted).
- **Unfinished**: Nothing from T1–T9 is outstanding.
- **Next steps**:
  1. S1: a `StdInvariant` handler suite with ghost accounting (escrow balance ≥ amount owed, `totalSupply` == total issued).
  2. Let a learner who cancelled late reclaim the retained part if the instructor later cancels the session, so the escrow always ends at 0 (DECISIONS Part 3.1).
  3. A dispute window before `CLAIM_DELAY`, backed by attendee check-ins, to handle instructor no-shows (DECISIONS Part 2).
