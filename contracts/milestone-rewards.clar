(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-already-exists (err u202))
(define-constant err-insufficient-balance (err u203))
(define-constant err-invalid-amount (err u204))
(define-constant err-unauthorized (err u205))
(define-constant err-milestone-not-active (err u206))
(define-constant err-reward-already-claimed (err u207))
(define-constant err-threshold-not-met (err u208))

(define-data-var next-milestone-id uint u1)
(define-data-var reward-pool uint u0)
(define-data-var total-rewards-distributed uint u0)

(define-map milestone-configs
    { milestone-id: uint }
    {
        threshold-amount: uint,
        reward-amount: uint,
        active: bool,
        total-claimants: uint,
        max-claimants: uint,
        description: (string-ascii 100),
    }
)

(define-map user-progress
    { user: principal }
    {
        total-payments: uint,
        milestones-achieved: (list 20 uint),
        total-rewards-earned: uint,
        last-payment-block: uint,
        streak-count: uint,
    }
)

(define-map milestone-claims
    {
        user: principal,
        milestone-id: uint,
    }
    {
        claimed: bool,
        claim-block: uint,
        reward-amount: uint,
    }
)

(define-map user-streaks
    { user: principal }
    {
        current-streak: uint,
        longest-streak: uint,
        last-streak-block: uint,
        streak-bonus-earned: uint,
    }
)

(define-map reward-multipliers
    { streak-level: uint }
    {
        multiplier: uint,
        min-streak: uint,
        bonus-percentage: uint,
    }
)

(define-public (initialize-reward-system)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set reward-multipliers { streak-level: u1 } {
            multiplier: u110,
            min-streak: u5,
            bonus-percentage: u10,
        })
        (map-set reward-multipliers { streak-level: u2 } {
            multiplier: u125,
            min-streak: u15,
            bonus-percentage: u25,
        })
        (map-set reward-multipliers { streak-level: u3 } {
            multiplier: u150,
            min-streak: u30,
            bonus-percentage: u50,
        })
        (ok true)
    )
)

(define-public (fund-reward-pool (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set reward-pool (+ (var-get reward-pool) amount))
        (ok (var-get reward-pool))
    )
)

(define-public (create-milestone
        (threshold-amount uint)
        (reward-amount uint)
        (max-claimants uint)
        (description (string-ascii 100))
    )
    (let ((milestone-id (var-get next-milestone-id)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> threshold-amount u0) err-invalid-amount)
        (asserts! (> reward-amount u0) err-invalid-amount)
        (asserts! (> max-claimants u0) err-invalid-amount)
        (asserts! (>= (var-get reward-pool) (* reward-amount max-claimants)) err-insufficient-balance)
        (map-set milestone-configs { milestone-id: milestone-id } {
            threshold-amount: threshold-amount,
            reward-amount: reward-amount,
            active: true,
            total-claimants: u0,
            max-claimants: max-claimants,
            description: description,
        })
        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

(define-public (record-payment (user principal) (amount uint))
    (let (
            (current-progress (default-to {
                total-payments: u0,
                milestones-achieved: (list),
                total-rewards-earned: u0,
                last-payment-block: u0,
                streak-count: u0,
            }
                (map-get? user-progress { user: user })
            ))
            (user-streak (default-to {
                current-streak: u0,
                longest-streak: u0,
                last-streak-block: u0,
                streak-bonus-earned: u0,
            }
                (map-get? user-streaks { user: user })
            ))
            (blocks-since-last (- stacks-block-height (get last-payment-block current-progress)))
            (new-streak (if (or
                    (is-eq (get last-payment-block current-progress) u0)
                    (<= blocks-since-last u1008)
                )
                (+ (get current-streak user-streak) u1)
                u1
            ))
        )
        (asserts! (> amount u0) err-invalid-amount)
        (map-set user-progress { user: user }
            (merge current-progress {
                total-payments: (+ (get total-payments current-progress) amount),
                last-payment-block: stacks-block-height,
                streak-count: new-streak,
            })
        )
        (map-set user-streaks { user: user }
            (merge user-streak {
                current-streak: new-streak,
                longest-streak: (if (> new-streak (get longest-streak user-streak))
                    new-streak
                    (get longest-streak user-streak)
                ),
                last-streak-block: stacks-block-height,
            })
        )
        (ok true)
    )
)

(define-public (claim-milestone-reward (milestone-id uint))
    (let (
            (milestone (unwrap! (map-get? milestone-configs { milestone-id: milestone-id }) err-not-found))
            (user-data (unwrap! (map-get? user-progress { user: tx-sender }) err-not-found))
            (existing-claim (map-get? milestone-claims {
                user: tx-sender,
                milestone-id: milestone-id,
            }))
            (user-streak-data (default-to {
                current-streak: u0,
                longest-streak: u0,
                last-streak-block: u0,
                streak-bonus-earned: u0,
            }
                (map-get? user-streaks { user: tx-sender })
            ))
            (streak-multiplier (get-streak-multiplier (get current-streak user-streak-data)))
            (final-reward (/ (* (get reward-amount milestone) streak-multiplier) u100))
        )
        (asserts! (get active milestone) err-milestone-not-active)
        (asserts! (>= (get total-payments user-data) (get threshold-amount milestone)) err-threshold-not-met)
        (asserts! (< (get total-claimants milestone) (get max-claimants milestone)) err-insufficient-balance)
        (asserts! (is-none existing-claim) err-reward-already-claimed)
        (asserts! (>= (var-get reward-pool) final-reward) err-insufficient-balance)
        (try! (as-contract (stx-transfer? final-reward tx-sender tx-sender)))
        (map-set milestone-claims {
            user: tx-sender,
            milestone-id: milestone-id,
        } {
            claimed: true,
            claim-block: stacks-block-height,
            reward-amount: final-reward,
        })
        (map-set milestone-configs { milestone-id: milestone-id }
            (merge milestone { total-claimants: (+ (get total-claimants milestone) u1) })
        )
        (map-set user-progress { user: tx-sender }
            (merge user-data {
                milestones-achieved: (unwrap!
                    (as-max-len?
                        (append (get milestones-achieved user-data) milestone-id)
                        u20
                    )
                    err-invalid-amount
                ),
                total-rewards-earned: (+ (get total-rewards-earned user-data) final-reward),
            })
        )
        (var-set reward-pool (- (var-get reward-pool) final-reward))
        (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) final-reward))
        (ok final-reward)
    )
)

(define-public (update-milestone-status
        (milestone-id uint)
        (active bool)
    )
    (let ((milestone (unwrap! (map-get? milestone-configs { milestone-id: milestone-id }) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set milestone-configs { milestone-id: milestone-id }
            (merge milestone { active: active })
        )
        (ok active)
    )
)

(define-public (claim-streak-bonus)
    (let (
            (user-streak (unwrap! (map-get? user-streaks { user: tx-sender }) err-not-found))
            (bonus-amount (calculate-streak-bonus (get current-streak user-streak)))
        )
        (asserts! (> bonus-amount u0) err-threshold-not-met)
        (asserts! (>= (var-get reward-pool) bonus-amount) err-insufficient-balance)
        (try! (as-contract (stx-transfer? bonus-amount tx-sender tx-sender)))
        (map-set user-streaks { user: tx-sender }
            (merge user-streak {
                streak-bonus-earned: (+ (get streak-bonus-earned user-streak) bonus-amount),
            })
        )
        (var-set reward-pool (- (var-get reward-pool) bonus-amount))
        (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) bonus-amount))
        (ok bonus-amount)
    )
)

(define-private (get-streak-multiplier (streak uint))
    (if (>= streak u30)
        u150
        (if (>= streak u15)
            u125
            (if (>= streak u5)
                u110
                u100
            )
        )
    )
)

(define-private (calculate-streak-bonus (streak uint))
    (let ((base-bonus u1000))
        (if (>= streak u30)
            (* base-bonus u5)
            (if (>= streak u15)
                (* base-bonus u3)
                (if (>= streak u10)
                    (* base-bonus u2)
                    (if (>= streak u5)
                        base-bonus
                        u0
                    )
                )
            )
        )
    )
)

(define-read-only (get-milestone-info (milestone-id uint))
    (map-get? milestone-configs { milestone-id: milestone-id })
)

(define-read-only (get-user-progress (user principal))
    (map-get? user-progress { user: user })
)

(define-read-only (get-user-streak (user principal))
    (map-get? user-streaks { user: user })
)

(define-read-only (get-milestone-claim
        (user principal)
        (milestone-id uint)
    )
    (map-get? milestone-claims {
        user: user,
        milestone-id: milestone-id,
    })
)

(define-read-only (check-milestone-eligibility
        (user principal)
        (milestone-id uint)
    )
    (let (
            (milestone (map-get? milestone-configs { milestone-id: milestone-id }))
            (user-data (map-get? user-progress { user: user }))
            (existing-claim (map-get? milestone-claims {
                user: user,
                milestone-id: milestone-id,
            }))
        )
        (match milestone
            milestone-data (match user-data
                user-progress-data (ok {
                    eligible: (and
                        (get active milestone-data)
                        (>= (get total-payments user-progress-data) (get threshold-amount milestone-data))
                        (< (get total-claimants milestone-data) (get max-claimants milestone-data))
                        (is-none existing-claim)
                    ),
                    threshold-met: (>= (get total-payments user-progress-data) (get threshold-amount milestone-data)),
                    already-claimed: (is-some existing-claim),
                    milestone-active: (get active milestone-data),
                    slots-available: (< (get total-claimants milestone-data) (get max-claimants milestone-data)),
                })
                err-not-found
            )
            err-not-found
        )
    )
)

(define-read-only (get-available-milestones (user principal))
    (let ((user-data (unwrap! (map-get? user-progress { user: user }) err-not-found)))
        (ok (filter is-milestone-available-for-user
            (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10)
        ))
    )
)

(define-private (is-milestone-available-for-user (milestone-id uint))
    (match (map-get? milestone-configs { milestone-id: milestone-id })
        milestone (and
            (get active milestone)
            (< (get total-claimants milestone) (get max-claimants milestone))
        )
        false
    )
)

(define-read-only (get-reward-pool-balance)
    (var-get reward-pool)
)

(define-read-only (get-total-rewards-distributed)
    (var-get total-rewards-distributed)
)

(define-read-only (get-streak-multiplier-info (streak uint))
    (ok {
        multiplier: (get-streak-multiplier streak),
        bonus-amount: (calculate-streak-bonus streak),
        next-tier-at: (if (< streak u5)
            u5
            (if (< streak u15)
                u15
                (if (< streak u30)
                    u30
                    u0
                )
            )
        ),
    })
)

(define-read-only (get-user-milestone-summary (user principal))
    (let (
            (user-data (unwrap! (map-get? user-progress { user: user }) err-not-found))
            (user-streak (default-to {
                current-streak: u0,
                longest-streak: u0,
                last-streak-block: u0,
                streak-bonus-earned: u0,
            }
                (map-get? user-streaks { user: user })
            ))
        )
        (ok {
            total-payments: (get total-payments user-data),
            milestones-achieved: (get milestones-achieved user-data),
            total-rewards-earned: (get total-rewards-earned user-data),
            current-streak: (get current-streak user-streak),
            longest-streak: (get longest-streak user-streak),
            streak-bonus-earned: (get streak-bonus-earned user-streak),
            next-streak-bonus: (calculate-streak-bonus (+ (get current-streak user-streak) u1)),
        })
    )
)
