# Architectural Decisions & Technical Analysis (DECISIONS.md)

## Part 1: Decisions D1, D2, and D3

### Decision D1: Fractional Unit Allocation on Late Cancellations
- **Choice**: The cancelling learner receives the integer division floor ($\lfloor \text{seatPrice} \times 0.6 \rfloor$), and the remaining fractional unit is retained for the instructor. For example, with $\text{seatPrice} = 1,001$, the learner receives $600$ units and the instructor retains $401$ units.
- **Why**: In Solidity, integer division truncates towards zero naturally. In a late cancellation (between 6 and 48 hours before session start), the learner is breaking a reservation window, while the instructor has already committed schedule, studio preparation, and capacity. Rewarding the non-cancelling instructor with the odd fractional unit aligns incentives against frivolous late cancellations and guarantees that $\text{refunded} + \text{retained} == \text{seatPrice}$ without math overflow or fractional leaks.
- **Alternative Rejected**: Rounding up the refund for the learner ($\lceil \text{seatPrice} \times 0.6 \rceil = 601$, instructor retains $400$). Rejected because favoring the cancelling party reduces the instructor's economic protection and requires additional custom ceiling logic.
- **Pinned Test**: `test_D1_fractionalRefundRounding` (in `test/SessionEscrow.t.sol`) and fuzz test `testFuzz_T6_lateSplit`.

---

### Decision D2: Platform Fee Rate Application
- **Choice**: The platform fee rate is snapshotted and locked at session creation time (`feeBpsAtCreation`).
- **Why**: Escrows operate on predictable terms of service. When an instructor publishes a workshop, they do so based on the agreed platform commission rate at that moment. Allowing administrative fee increases between session publishing and the claim window (which can be days or weeks later) would expose instructors to surprise retroactive fee increases.
- **Alternative Rejected**: Applying the live administrative `feeBps` at the time `claimEarnings()` is executed. Rejected because it introduces administrative hold-up risk where a platform admin could temporarily hike fees to the 12% cap just before major workshop payouts occur.
- **Pinned Test**: `test_D2_whichFeeRateApplies` (in `test/SessionEscrow.t.sol`).

---

### Decision D3: Gift Bookings Cancellation & Refund Authority
- **Choice**: Both the original `payer` and the registered `attendee` are authorized to invoke `cancelBooking()` and `claimRefund()`, but all refunded credits are **strictly transferred to the `payer`'s wallet**. A stranger who is neither payer nor attendee reverts `NotBookingParty`.
- **Why**: The attendee is the person attending in person and knows first-hand if their personal schedule conflicts. However, because the payer contributed their personal credit balance to purchase the gift, the financial capital belongs to the payer. Returning funds to the attendee would create an attack vector where recipients convert non-transferable gift bookings into liquid personal credits.
- **Alternative Rejected**: Permitting only the payer to cancel. Rejected because if the gift recipient falls ill, requiring the payer to coordinate the cancellation creates unnecessary UX friction and could cause the booking to miss the 6-hour cancellation cutoff.
- **Pinned Test**: `test_D3_giftBookingCancellationAndRefund` (in `test/SessionEscrow.t.sol`).

---

## Part 2: No-Shows

**Three-Question Analysis:**
1. **What the contracts do**: The smart contracts do not track physical attendance. If a learner does not attend and fails to cancel before the 6-hour cutoff, their full seat payment is credited to the instructor's earnings. Conversely, if an instructor fails to appear, the contract cannot autonomously detect it, and earnings become claimable 24 hours after start time.
2. **Who must be trusted**: The system currently trusts the instructor not to abandon an in-person session, and trusts the platform off-chain customer support/admin to intervene if fraud occurs.
3. **What could be abused**: A malicious instructor could schedule phantom sessions, collect bookings, never attend the venue, and withdraw the net earnings 24 hours later. To prevent this without full decentralization, off-chain check-ins (e.g. attendee QR code multi-signature or an escrow dispute window prior to `CLAIM_DELAY`) should be integrated.

---

## Part 3: Conflicts and Gaps in the Specification

1. **Retained Penalties in Cancelled Sessions**: When a session has retained late-cancellation penalties (e.g. Farhan cancels for 480 refund, leaving 320 retained) and the instructor subsequently cancels the entire session, `claimEarnings()` reverts with `SessionNotActive`. As observed in the Section 5 worked example (T1), the 320 credits remain in escrow. **Resolution**: The contract strictly adheres to `SessionNotActive` on cancelled session claims; in a production upgrade, a treasury sweep or prorated compensation function would distribute residual retained penalties.
2. **Cancellation Freeze under Contract Pause**: Stated requirement `R-PAUSE` mandates that *"no credits may enter or leave it"*. Pausing freezes `cancelBooking` and `claimRefund`. If an escrow is paused for 48 hours, a learner's cancellation notice window could expire unfairly. **Resolution**: Adhered strictly to `R-PAUSE` by freezing all token-moving functions (`book`, `claimEarnings`, `cancelBooking`, `claimRefund`), while allowing non-financial `cancelSession`.
3. **Duplicate Cancellations**: A session could be cancelled after individual learners have already cancelled. **Resolution**: Handled via state tracking—only bookings with status `Active` are refunded via `claimRefund()`, preventing double-refund exploits.

---

## Part 4: Threat Model & Key Compromises

- **Compromised Admin Key**: A rogue admin could attempt to raise platform fees to drain instructor revenues.
  - *Mitigation*: Hard cap enforced in code (`MAX_FEE_BPS = 1_200`, 12%), and fee rates locked per session at creation time (Decision D2). A multi-sig timelock is recommended for admin roles.
- **Compromised Issuer Key**: An attacker with `ISSUER_ROLE` could mint infinite credits, diluting the economy.
  - *Mitigation*: While the contract allows unconstrained issuance per spec, the token is non-transferable between learners (`R-NOTRANSFER`), restricting the attacker's ability to sell credits on secondary markets or drain external pools.
- **Malicious Learner / Reentrancy**: A learner could attempt to reenter `cancelBooking()` to receive multiple refunds.
  - *Mitigation*: Strict adherence to Checks-Effects-Interactions (CEI)—booking status is set to `Cancelled` and session counters are updated *before* invoking `token.transfer()`.

---

## Part 5: Invariants

1. **Non-Transferability Invariant**: No token transfer can succeed between two non-escrow addresses where neither address is zero.
   - *Mapped Test*: `test_T2_transferRule_learnerToLearnerReverts` and `test_T2_transferRule_transferFromLearnerToLearnerReverts`.
2. **Cancellation Conservation Invariant**: For every cancelled booking, the sum of credits returned to the learner and credits retained for the instructor equals the original seat price ($\text{refunded} + \text{retained} == \text{seatPrice}$).
   - *Mapped Test*: Property-based fuzz test `testFuzz_T6_lateSplit` across all price ranges $[100, 500\,000]$.
3. **Fee Conservation Invariant**: For any claimed session, the sum of net instructor earnings and platform treasury fee strictly equals the session gross ($\text{net} + \text{fee} == \text{gross}$), and $\text{fee} \times 10\,000 \ge \text{gross} \times \text{feeBps}$.
   - *Mapped Test*: Property-based fuzz test `testFuzz_T7_feeCalculation`.
