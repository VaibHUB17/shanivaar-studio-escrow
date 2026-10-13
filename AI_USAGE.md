# AI Usage Disclosure (AI_USAGE.md)

## 1. Tools Used and Workflow
- **Model / Tool**: Gemini 3.8 Flash (High) via Antigravity Coding Assistant; Claude Opus 5.5 via Claude Code for a final spec-compliance review and the fixes it found (see Output 4).
- **Purpose**:
  - Drafting interface declarations and contract skeletons matching Appendix A.
  - Reviewing Checks-Effects-Interactions (CEI) sequencing and custom error selector definitions.
  - Generating test scaffolding for the 12-timestamp timeline of the Section 5 worked example (T1).
  - Formulating invariant equations for Foundry fuzzing (T6, T7).

---

## 2. Outputs Changed, Rejected, or Verified

### Output 1: Prank Consumption by Getter Calls (Changed)
- **Initial AI Output**: The initial test setup generated helper scripts using `vm.prank(admin)` immediately followed by `token.grantRole(token.ISSUER_ROLE(), issuer)`.
- **Why It Failed**: In Foundry, `token.ISSUER_ROLE()` is an external contract view call. When executed, it consumed the single-call `vm.prank(admin)` before `token.grantRole(...)` was invoked, causing an unexpected `AccessControlUnauthorizedAccount` revert.
- **Correction Applied**: Rejected the single-prank inline view pattern. Cached role hashes as constants (`bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");`) and utilized scoped `vm.startPrank(admin)` / `vm.stopPrank()` blocks to prevent call consumption.

### Output 2: Fee Ceiling Arithmetic (Verified)
- **AI Output**: Implemented the ceiling division formula for the platform fee:
  $$\text{fee} = \frac{\text{gross} \times \text{feeBps} + 9\,999}{10\,000}$$
- **Verification Method**: Verified against the worked example ($1,750 \times 350 / 10,000 = 61.25 \rightarrow 62$) and validated through property-based fuzz test `testFuzz_T7_feeCalculation` over 256 randomized runs ensuring that $\text{fee} \times 10,000 \ge \text{seatPrice} \times \text{feeBps}$ and $(\text{fee} - 1) \times 10,000 < \text{seatPrice} \times \text{feeBps}$ strictly hold.

### Output 3: Reentrancy vs Pull-Refunds (Changed)
- **Initial AI Output**: Suggestion to push refunds automatically to all learners inside `cancelSession()`.
- **Why Rejected**: Rejected because an instructor cancelling a session with 40 attendees could hit block gas limits or be griefed by a reverting contract learner. Retained the strict pull-based model mandated by specification `R-REFUND` via individual `claimRefund()` calls.

### Output 4: Hollow T3 test and pause ordering (Verified, then fixed)
- **AI Output**: A review with Claude Code flagged that `test_T3_allCustomErrorsCovered` passed using only 8,900 gas, and that the `whenNotPaused` modifier ran before the unknown-id checks.
- **Verification Method**: A `forge test -vvvv` trace showed the test ending at its first `vm.expectRevert` + `new SessionEscrow(address(0), ...)`, so the other ~19 checks never ran. With that line removed, the rest of T3 passed at about 2M gas. The constructor checks now use `try`/`catch` in `test_T3_constructorZeroAddress`; the pause check now runs after the id check, pinned by `test_T8_unknownIdRevertsBeforePauseCheck`.
