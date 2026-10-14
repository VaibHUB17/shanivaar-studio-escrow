# Architectural Decisions & Technical Analysis (DECISIONS.md)

## Part 1: Decisions D1, D2, and D3

### D1: Fractional unit on late cancellations
- **Choice**: The learner receives `floor(seatPrice × 60%)`; the fractional unit stays with the instructor. A 1,001 seat refunds 600 and retains 401.
- **Why**: The learner is the party breaking the booking inside the late window, while the instructor has already committed time and capacity. Floor division also guarantees `refunded + retained == seatPrice` with no leftover dust.
- **Rejected**: Rounding the refund up (601 / 400). It rewards the cancelling party at the instructor's expense.
- **Tests**: `test_D1_fractionalRefundRounding`, `testFuzz_T6_lateSplit`.

### D2: Which fee rate applies
- **Choice**: The fee rate is snapshotted at session creation (`feeBpsAtCreation`) and used at claim time. `feeBps()` still returns the new value immediately.
- **Why**: Instructors price a workshop against the commission in force when they publish it. A later change should not apply retroactively to income already booked.
- **Rejected**: The live rate at claim time. It lets an admin raise the fee to 12% just before a large payout.
- **Test**: `test_D2_whichFeeRateApplies`.

### D3: Gift bookings
- **Choice**: Both payer and attendee may call `cancelBooking` and `claimRefund`; all refunds go to the **payer**. Anyone else reverts `NotBookingParty`.
- **Why**: The attendee knows first-hand when they cannot attend, so they should be able to cancel before the 6-hour cutoff. The credits belong to the payer, and paying the attendee would let a gift be turned into the recipient's own credits.
- **Rejected**: Payer-only cancellation. A sick attendee would have to reach the payer in time.
- **Tests**: `test_D3_giftBookingCancellationAndRefund`, `test_D3_giftBookingClaimRefundAndStranger`.

---

## Part 2: No-Shows

The contracts do nothing about no-shows: a learner who misses the session without cancelling pays in full, and an instructor who never turns up can still claim 24 hours after the start. Learners must trust instructors to deliver, and both must trust the platform to vet instructors (admin grants `INSTRUCTOR_ROLE`) and handle disputes off-chain. The obvious abuse is a phantom session: an instructor collects bookings, never appears, and claims. A dispute window before `CLAIM_DELAY` ends, backed by attendee check-ins, would be the next step.

---

## Part 3: Conflicts and Gaps

1. **Retained penalties in a cancelled session.** If a learner cancels late and the instructor later cancels the session, `claimEarnings` reverts `SessionNotActive`, so the retained amount stays in escrow (320 credits in T1). **Did**: followed the spec and asserted the 320 in `test_T1_workedExample`. A follow-up would let that learner reclaim the retained part via `claimRefund`.
2. **R-PAUSE vs. R-REFUND ("always").** No credits may leave while paused, so refunds pause too, and a learner's cancellation tier keeps running. **Did**: R-PAUSE wins; `book`, `cancelBooking`, `claimRefund` and `claimEarnings` all revert `EnforcedPause` (`test_T8_pauseMatrix`).
3. **Functions that move no credits while paused.** **Did**: `createSession` and `cancelSession` stay open, so instructors can still schedule or cancel safely (`test_T8_createSessionAllowedWhilePaused`, `test_T8_pauseMatrix`).
4. **Unknown ids vs. pause.** The "unknown id first" rule conflicts with a `whenNotPaused` modifier, which runs before the body. **Did**: the id check runs first, then `_requireNotPaused()` (`test_T8_unknownIdRevertsBeforePauseCheck`).
5. **Burning.** OZ `_update` treats `to == address(0)` as a burn. **Did**: it reverts `CreditsNotTransferable`, so no path can destroy credits.

---

## Part 4: Threat Model

- **Compromised pauser key**: can pause indefinitely, freezing every refund and payout. *Mitigation*: hold `PAUSER_ROLE` in a multisig, separate from the admin, with an off-chain unpause runbook; a maximum pause duration would be the code-level fix.
- **Compromised admin or issuer key**: the admin can grant itself `ISSUER_ROLE` and `INSTRUCTOR_ROLE`, mint unlimited credits, fill every session, and run fake sessions. Raising the fee is capped at 12% and does not affect existing sessions (D2). *Mitigation*: put the admin behind a timelocked multisig and monitor `Issued` and `RoleGranted` events.
- **Malicious instructor**: can collect bookings for a session they never hold and claim after 24 hours (Part 2), or cancel late to strand retained penalties (Part 3.1). *Mitigation*: KYC before granting `INSTRUCTOR_ROLE`, plus a dispute window before claims.

---

## Part 5: Invariants

1. **No learner-to-learner movement**: a transfer succeeds only if it is a mint or touches the escrow. *Tests*: `test_T2_transferRule_learnerToLearnerReverts`, `test_T2_transferRule_transferFromLearnerToLearnerReverts`.
2. **Cancellation conservation**: for every cancelled booking, `refunded + retained == seatPrice`, measured from balances and the event. Bookings do not store their own price: refunds read `session.seatPrice`, which is safe because the brief makes price immutable. *Test*: `testFuzz_T6_lateSplit`.
3. **Fee conservation**: for every claim, `fee + net == gross` and the fee is the exact ceiling of `gross × feeBps / 10,000`. *Test*: `testFuzz_T7_feeCalculation`.
