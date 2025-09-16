(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-payment (err u103))
(define-constant err-inactive-system (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-subscription-not-found (err u107))
(define-constant err-subscription-expired (err u108))
(define-constant err-subscription-exists (err u109))
(define-constant err-invalid-tier (err u110))
(define-constant err-pricing-not-found (err u111))

(define-data-var next-system-id uint u1)
(define-data-var contract-fee uint u1000)
(define-data-var next-subscription-id uint u1)
(define-data-var demand-multiplier uint u100)

(define-map solar-systems
    { system-id: uint }
    {
        owner: principal,
        location: (string-ascii 100),
        capacity-kwh: uint,
        rate-per-kwh: uint,
        active: bool,
        total-energy-generated: uint,
        total-payments-received: uint,
    }
)

(define-map user-accounts
    { user: principal }
    {
        balance: uint,
        total-usage: uint,
        systems-accessed: (list 20 uint),
        registration-block: uint,
    }
)

(define-map system-access
    {
        system-id: uint,
        user: principal,
    }
    {
        access-granted: bool,
        last-payment-block: uint,
        total-paid: uint,
        energy-consumed: uint,
    }
)

(define-map payment-history
    { payment-id: uint }
    {
        user: principal,
        system-id: uint,
        amount: uint,
        energy-kwh: uint,
        payment-block: uint,
    }
)

(define-map energy-subscriptions
    { subscription-id: uint }
    {
        user: principal,
        system-id: uint,
        monthly-kwh: uint,
        monthly-payment: uint,
        start-block: uint,
        last-renewal-block: uint,
        active: bool,
        auto-renew: bool,
    }
)

(define-map user-subscriptions
    { user: principal }
    {
        active-subscriptions: (list 10 uint),
        total-subscriptions: uint,
    }
)

(define-map system-pricing
    { system-id: uint }
    {
        tier-1-rate: uint,
        tier-2-rate: uint,
        tier-3-rate: uint,
        tier-1-threshold: uint,
        tier-2-threshold: uint,
        current-demand: uint,
        peak-hours-multiplier: uint,
        off-peak-hours-multiplier: uint,
        dynamic-pricing-enabled: bool,
    }
)

(define-map system-demand-stats
    { system-id: uint }
    {
        daily-requests: uint,
        peak-demand-block: uint,
        total-energy-requested: uint,
        last-update-block: uint,
    }
)

(define-data-var next-payment-id uint u1)

(define-public (register-solar-system
        (location (string-ascii 100))
        (capacity-kwh uint)
        (rate-per-kwh uint)
    )
    (let ((system-id (var-get next-system-id)))
        (asserts! (> capacity-kwh u0) (err u106))
        (asserts! (> rate-per-kwh u0) (err u106))
        (map-set solar-systems { system-id: system-id } {
            owner: tx-sender,
            location: location,
            capacity-kwh: capacity-kwh,
            rate-per-kwh: rate-per-kwh,
            active: true,
            total-energy-generated: u0,
            total-payments-received: u0,
        })
        (var-set next-system-id (+ system-id u1))
        (map-set system-pricing { system-id: system-id } {
            tier-1-rate: rate-per-kwh,
            tier-2-rate: (* rate-per-kwh u120),
            tier-3-rate: (* rate-per-kwh u150),
            tier-1-threshold: u100,
            tier-2-threshold: u500,
            current-demand: u0,
            peak-hours-multiplier: u130,
            off-peak-hours-multiplier: u80,
            dynamic-pricing-enabled: false,
        })
        (map-set system-demand-stats { system-id: system-id } {
            daily-requests: u0,
            peak-demand-block: u0,
            total-energy-requested: u0,
            last-update-block: stacks-block-height,
        })
        (ok system-id)
    )
)

(define-public (register-user)
    (let ((existing-account (map-get? user-accounts { user: tx-sender })))
        (asserts! (is-none existing-account) err-already-exists)
        (map-set user-accounts { user: tx-sender } {
            balance: u0,
            total-usage: u0,
            systems-accessed: (list),
            registration-block: stacks-block-height,
        })
        (ok true)
    )
)

(define-public (deposit-funds (amount uint))
    (let ((user-account (unwrap! (map-get? user-accounts { user: tx-sender }) err-not-found)))
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set user-accounts { user: tx-sender }
            (merge user-account { balance: (+ (get balance user-account) amount) })
        )
        (ok (+ (get balance user-account) amount))
    )
)

(define-public (pay-for-energy
        (system-id uint)
        (energy-kwh uint)
    )
    (let (
            (system (unwrap! (map-get? solar-systems { system-id: system-id })
                err-not-found
            ))
            (user-account (unwrap! (map-get? user-accounts { user: tx-sender }) err-not-found))
            (dynamic-rate (calculate-dynamic-rate system-id energy-kwh
                (get rate-per-kwh system)
            ))
            (cost (* energy-kwh dynamic-rate))
            (payment-id (var-get next-payment-id))
        )
        (asserts! (get active system) err-inactive-system)
        (asserts! (> energy-kwh u0) err-invalid-amount)
        (asserts! (>= (get balance user-account) cost) err-insufficient-payment)

        (map-set user-accounts { user: tx-sender }
            (merge user-account {
                balance: (- (get balance user-account) cost),
                total-usage: (+ (get total-usage user-account) energy-kwh),
            })
        )

        (map-set solar-systems { system-id: system-id }
            (merge system { total-payments-received: (+ (get total-payments-received system) cost) })
        )

        (let ((existing-access (map-get? system-access {
                system-id: system-id,
                user: tx-sender,
            })))
            (map-set system-access {
                system-id: system-id,
                user: tx-sender,
            } {
                access-granted: true,
                last-payment-block: stacks-block-height,
                total-paid: (+ (default-to u0 (get total-paid existing-access)) cost),
                energy-consumed: (+ (default-to u0 (get energy-consumed existing-access))
                    energy-kwh
                ),
            })
        )

        (map-set payment-history { payment-id: payment-id } {
            user: tx-sender,
            system-id: system-id,
            amount: cost,
            energy-kwh: energy-kwh,
            payment-block: stacks-block-height,
        })

        (var-set next-payment-id (+ payment-id u1))
        (try! (update-demand-stats system-id energy-kwh))
        (ok payment-id)
    )
)

(define-public (withdraw-earnings
        (system-id uint)
        (amount uint)
    )
    (let ((system (unwrap! (map-get? solar-systems { system-id: system-id }) err-not-found)))
        (asserts! (is-eq tx-sender (get owner system)) err-unauthorized)
        (asserts! (>= (get total-payments-received system) amount)
            err-insufficient-payment
        )
        (asserts! (> amount u0) err-invalid-amount)

        (try! (as-contract (stx-transfer? amount tx-sender (get owner system))))

        (map-set solar-systems { system-id: system-id }
            (merge system { total-payments-received: (- (get total-payments-received system) amount) })
        )
        (ok amount)
    )
)

(define-public (update-system-status
        (system-id uint)
        (active bool)
    )
    (let ((system (unwrap! (map-get? solar-systems { system-id: system-id }) err-not-found)))
        (asserts! (is-eq tx-sender (get owner system)) err-unauthorized)
        (map-set solar-systems { system-id: system-id }
            (merge system { active: active })
        )
        (ok active)
    )
)

(define-public (update-energy-generation
        (system-id uint)
        (energy-kwh uint)
    )
    (let ((system (unwrap! (map-get? solar-systems { system-id: system-id }) err-not-found)))
        (asserts! (is-eq tx-sender (get owner system)) err-unauthorized)
        (asserts! (> energy-kwh u0) err-invalid-amount)
        (map-set solar-systems { system-id: system-id }
            (merge system { total-energy-generated: (+ (get total-energy-generated system) energy-kwh) })
        )
        (ok (get total-energy-generated
            (merge system { total-energy-generated: (+ (get total-energy-generated system) energy-kwh) })
        ))
    )
)

(define-public (configure-dynamic-pricing
        (system-id uint)
        (tier-1-rate uint)
        (tier-2-rate uint)
        (tier-3-rate uint)
        (tier-1-threshold uint)
        (tier-2-threshold uint)
        (peak-multiplier uint)
        (off-peak-multiplier uint)
        (enable-dynamic bool)
    )
    (let ((system (unwrap! (map-get? solar-systems { system-id: system-id }) err-not-found)))
        (asserts! (is-eq tx-sender (get owner system)) err-unauthorized)
        (asserts! (> tier-1-rate u0) err-invalid-amount)
        (asserts! (> tier-2-rate u0) err-invalid-amount)
        (asserts! (> tier-3-rate u0) err-invalid-amount)
        (asserts! (> tier-1-threshold u0) err-invalid-amount)
        (asserts! (> tier-2-threshold tier-1-threshold) err-invalid-amount)
        (map-set system-pricing { system-id: system-id } {
            tier-1-rate: tier-1-rate,
            tier-2-rate: tier-2-rate,
            tier-3-rate: tier-3-rate,
            tier-1-threshold: tier-1-threshold,
            tier-2-threshold: tier-2-threshold,
            current-demand: (default-to u0
                (get current-demand
                    (map-get? system-pricing { system-id: system-id })
                )),
            peak-hours-multiplier: peak-multiplier,
            off-peak-hours-multiplier: off-peak-multiplier,
            dynamic-pricing-enabled: enable-dynamic,
        })
        (ok true)
    )
)

(define-public (update-demand-stats
        (system-id uint)
        (energy-requested uint)
    )
    (let (
            (system (unwrap! (map-get? solar-systems { system-id: system-id })
                err-not-found
            ))
            (current-stats (default-to {
                daily-requests: u0,
                peak-demand-block: u0,
                total-energy-requested: u0,
                last-update-block: stacks-block-height,
            }
                (map-get? system-demand-stats { system-id: system-id })
            ))
            (pricing (default-to {
                tier-1-rate: (get rate-per-kwh system),
                tier-2-rate: (* (get rate-per-kwh system) u120),
                tier-3-rate: (* (get rate-per-kwh system) u150),
                tier-1-threshold: u100,
                tier-2-threshold: u500,
                current-demand: u0,
                peak-hours-multiplier: u130,
                off-peak-hours-multiplier: u80,
                dynamic-pricing-enabled: false,
            }
                (map-get? system-pricing { system-id: system-id })
            ))
        )
        (asserts! (get active system) err-inactive-system)
        (map-set system-demand-stats { system-id: system-id }
            (merge current-stats {
                daily-requests: (+ (get daily-requests current-stats) u1),
                total-energy-requested: (+ (get total-energy-requested current-stats) energy-requested),
                last-update-block: stacks-block-height,
            })
        )
        (map-set system-pricing { system-id: system-id }
            (merge pricing { current-demand: (+ (get current-demand pricing) energy-requested) })
        )
        (ok true)
    )
)

(define-private (calculate-dynamic-rate
        (system-id uint)
        (energy-kwh uint)
        (base-rate uint)
    )
    (let (
            (pricing (map-get? system-pricing { system-id: system-id }))
            (current-block stacks-block-height)
        )
        (match pricing
            pricing-data (if (get dynamic-pricing-enabled pricing-data)
                (let (
                        (tier-rate (get-tier-rate pricing-data
                            (get current-demand pricing-data)
                        ))
                        (time-multiplier (get-time-multiplier pricing-data current-block))
                        (demand-factor (get-demand-factor (get current-demand pricing-data)))
                    )
                    (/ (* (* tier-rate time-multiplier) demand-factor) u10000)
                )
                base-rate
            )
            base-rate
        )
    )
)

(define-private (get-tier-rate
        (pricing-data {
            tier-1-rate: uint,
            tier-2-rate: uint,
            tier-3-rate: uint,
            tier-1-threshold: uint,
            tier-2-threshold: uint,
            current-demand: uint,
            peak-hours-multiplier: uint,
            off-peak-hours-multiplier: uint,
            dynamic-pricing-enabled: bool,
        })
        (demand uint)
    )
    (if (<= demand (get tier-1-threshold pricing-data))
        (get tier-1-rate pricing-data)
        (if (<= demand (get tier-2-threshold pricing-data))
            (get tier-2-rate pricing-data)
            (get tier-3-rate pricing-data)
        )
    )
)

(define-private (get-time-multiplier
        (pricing-data {
            tier-1-rate: uint,
            tier-2-rate: uint,
            tier-3-rate: uint,
            tier-1-threshold: uint,
            tier-2-threshold: uint,
            current-demand: uint,
            peak-hours-multiplier: uint,
            off-peak-hours-multiplier: uint,
            dynamic-pricing-enabled: bool,
        })
        (current-block uint)
    )
    (let ((hour-equivalent (mod current-block u144)))
        (if (or (< hour-equivalent u36) (> hour-equivalent u108))
            (get peak-hours-multiplier pricing-data)
            (get off-peak-hours-multiplier pricing-data)
        )
    )
)

(define-private (get-demand-factor (demand uint))
    (if (<= demand u100)
        u100
        (if (<= demand u500)
            u110
            (if (<= demand u1000)
                u125
                u140
            )
        )
    )
)

(define-read-only (get-system-info (system-id uint))
    (map-get? solar-systems { system-id: system-id })
)

(define-read-only (get-user-account (user principal))
    (map-get? user-accounts { user: user })
)

(define-read-only (get-user-access
        (system-id uint)
        (user principal)
    )
    (map-get? system-access {
        system-id: system-id,
        user: user,
    })
)

(define-read-only (get-payment-info (payment-id uint))
    (map-get? payment-history { payment-id: payment-id })
)

(define-read-only (calculate-energy-cost
        (system-id uint)
        (energy-kwh uint)
    )
    (let ((system (unwrap! (map-get? solar-systems { system-id: system-id }) err-not-found)))
        (ok (* energy-kwh (get rate-per-kwh system)))
    )
)

(define-read-only (check-access-status
        (system-id uint)
        (user principal)
    )
    (let (
            (access (map-get? system-access {
                system-id: system-id,
                user: user,
            }))
            (system (map-get? solar-systems { system-id: system-id }))
            (current-block stacks-block-height)
        )
        (match access
            access-data (let ((blocks-since-payment (- current-block (get last-payment-block access-data))))
                {
                    access-granted: (and (get access-granted access-data) (< blocks-since-payment u144)),
                    last-payment-block: (get last-payment-block access-data),
                    total-paid: (get total-paid access-data),
                    energy-consumed: (get energy-consumed access-data),
                }
            )
            {
                access-granted: false,
                last-payment-block: u0,
                total-paid: u0,
                energy-consumed: u0,
            }
        )
    )
)

(define-read-only (get-active-systems)
    (ok (filter is-system-active
        (map get-system-ids
            (list
                u1                 u2                 u3                 u4
                u5                 u6                 u7                 u8
                u9                 u10                 u11                 u12
                u13                 u14                 u15                 u16
                u17                 u18                 u19                 u20
            ))
    ))
)

(define-private (is-system-active (system-id uint))
    (match (map-get? solar-systems { system-id: system-id })
        system (get active system)
        false
    )
)

(define-private (get-system-ids (id uint))
    id
)

(define-read-only (get-user-balance (user principal))
    (match (map-get? user-accounts { user: user })
        account (ok (get balance account))
        err-not-found
    )
)

(define-read-only (get-system-earnings (system-id uint))
    (match (map-get? solar-systems { system-id: system-id })
        system (ok (get total-payments-received system))
        err-not-found
    )
)

(define-public (emergency-shutdown (system-id uint))
    (let ((system (unwrap! (map-get? solar-systems { system-id: system-id }) err-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set solar-systems { system-id: system-id }
            (merge system { active: false })
        )
        (ok true)
    )
)

(define-public (update-contract-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-fee new-fee)
        (ok new-fee)
    )
)

(define-read-only (get-contract-fee)
    (var-get contract-fee)
)

(define-read-only (get-next-system-id)
    (var-get next-system-id)
)

(define-public (create-energy-subscription
        (system-id uint)
        (monthly-kwh uint)
        (auto-renew bool)
    )
    (let (
            (subscription-id (var-get next-subscription-id))
            (system (unwrap! (map-get? solar-systems { system-id: system-id })
                err-not-found
            ))
            (user-account (unwrap! (map-get? user-accounts { user: tx-sender }) err-not-found))
            (dynamic-rate (calculate-dynamic-rate system-id monthly-kwh
                (get rate-per-kwh system)
            ))
            (monthly-payment (* monthly-kwh dynamic-rate))
            (user-subs (default-to {
                active-subscriptions: (list),
                total-subscriptions: u0,
            }
                (map-get? user-subscriptions { user: tx-sender })
            ))
        )
        (asserts! (get active system) err-inactive-system)
        (asserts! (> monthly-kwh u0) err-invalid-amount)
        (asserts! (>= (get balance user-account) monthly-payment)
            err-insufficient-payment
        )

        (try! (stx-transfer? monthly-payment tx-sender (as-contract tx-sender)))

        (map-set user-accounts { user: tx-sender }
            (merge user-account { balance: (- (get balance user-account) monthly-payment) })
        )

        (map-set energy-subscriptions { subscription-id: subscription-id } {
            user: tx-sender,
            system-id: system-id,
            monthly-kwh: monthly-kwh,
            monthly-payment: monthly-payment,
            start-block: stacks-block-height,
            last-renewal-block: stacks-block-height,
            active: true,
            auto-renew: auto-renew,
        })

        (map-set solar-systems { system-id: system-id }
            (merge system { total-payments-received: (+ (get total-payments-received system) monthly-payment) })
        )

        (map-set user-subscriptions { user: tx-sender }
            (merge user-subs {
                active-subscriptions: (unwrap!
                    (as-max-len?
                        (append (get active-subscriptions user-subs)
                            subscription-id
                        )
                        u10
                    )
                    err-invalid-amount
                ),
                total-subscriptions: (+ (get total-subscriptions user-subs) u1),
            })
        )

        (var-set next-subscription-id (+ subscription-id u1))
        (ok subscription-id)
    )
)

(define-public (renew-subscription (subscription-id uint))
    (let (
            (subscription (unwrap!
                (map-get? energy-subscriptions { subscription-id: subscription-id })
                err-subscription-not-found
            ))
            (user-account (unwrap! (map-get? user-accounts { user: (get user subscription) })
                err-not-found
            ))
            (blocks-since-renewal (- stacks-block-height (get last-renewal-block subscription)))
        )
        (asserts! (get active subscription) err-subscription-expired)
        (asserts! (>= blocks-since-renewal u4320) err-invalid-amount)
        (asserts!
            (or (is-eq tx-sender (get user subscription)) (get auto-renew subscription))
            err-unauthorized
        )
        (asserts!
            (>= (get balance user-account) (get monthly-payment subscription))
            err-insufficient-payment
        )

        (try! (stx-transfer? (get monthly-payment subscription) (get user subscription)
            (as-contract tx-sender)
        ))

        (map-set user-accounts { user: (get user subscription) }
            (merge user-account {
                balance: (- (get balance user-account) (get monthly-payment subscription)),
                total-usage: (+ (get total-usage user-account) (get monthly-kwh subscription)),
            })
        )

        (let ((system (unwrap!
                (map-get? solar-systems { system-id: (get system-id subscription) })
                err-not-found
            )))
            (map-set solar-systems { system-id: (get system-id subscription) }
                (merge system { total-payments-received: (+ (get total-payments-received system)
                    (get monthly-payment subscription)
                ) }
                ))
        )

        (map-set energy-subscriptions { subscription-id: subscription-id }
            (merge subscription { last-renewal-block: stacks-block-height })
        )

        (ok true)
    )
)

(define-public (cancel-subscription (subscription-id uint))
    (let ((subscription (unwrap!
            (map-get? energy-subscriptions { subscription-id: subscription-id })
            err-subscription-not-found
        )))
        (asserts! (is-eq tx-sender (get user subscription)) err-unauthorized)
        (asserts! (get active subscription) err-subscription-expired)

        (map-set energy-subscriptions { subscription-id: subscription-id }
            (merge subscription {
                active: false,
                auto-renew: false,
            })
        )

        (ok true)
    )
)

(define-public (update-subscription-auto-renew
        (subscription-id uint)
        (auto-renew bool)
    )
    (let ((subscription (unwrap!
            (map-get? energy-subscriptions { subscription-id: subscription-id })
            err-subscription-not-found
        )))
        (asserts! (is-eq tx-sender (get user subscription)) err-unauthorized)
        (asserts! (get active subscription) err-subscription-expired)

        (map-set energy-subscriptions { subscription-id: subscription-id }
            (merge subscription { auto-renew: auto-renew })
        )

        (ok auto-renew)
    )
)

(define-read-only (get-subscription-info (subscription-id uint))
    (map-get? energy-subscriptions { subscription-id: subscription-id })
)

(define-read-only (get-user-subscriptions (user principal))
    (map-get? user-subscriptions { user: user })
)

(define-read-only (check-subscription-status (subscription-id uint))
    (match (map-get? energy-subscriptions { subscription-id: subscription-id })
        subscription (let ((blocks-since-renewal (- stacks-block-height (get last-renewal-block subscription))))
            (ok {
                active: (get active subscription),
                needs-renewal: (and (get active subscription) (>= blocks-since-renewal u4320)),
                auto-renew: (get auto-renew subscription),
                blocks-until-expiry: (if (< blocks-since-renewal u4320)
                    (- u4320 blocks-since-renewal)
                    u0
                ),
                monthly-kwh: (get monthly-kwh subscription),
                monthly-payment: (get monthly-payment subscription),
            })
        )
        err-subscription-not-found
    )
)

(define-read-only (get-active-subscription-energy (user principal))
    (let ((user-subs (default-to {
            active-subscriptions: (list),
            total-subscriptions: u0,
        }
            (map-get? user-subscriptions { user: user })
        )))
        (fold +
            (map get-subscription-energy (get active-subscriptions user-subs))
            u0
        )
    )
)

(define-private (get-subscription-energy (subscription-id uint))
    (match (map-get? energy-subscriptions { subscription-id: subscription-id })
        subscription (if (and
                (get active subscription)
                (< (- stacks-block-height (get last-renewal-block subscription))
                    u4320
                )
            )
            (get monthly-kwh subscription)
            u0
        )
        u0
    )
)

(define-read-only (get-total-systems)
    (- (var-get next-system-id) u1)
)

(define-read-only (get-system-pricing (system-id uint))
    (map-get? system-pricing { system-id: system-id })
)

(define-read-only (get-system-demand-stats (system-id uint))
    (map-get? system-demand-stats { system-id: system-id })
)

(define-read-only (get-current-dynamic-rate
        (system-id uint)
        (energy-kwh uint)
    )
    (let ((system (unwrap! (map-get? solar-systems { system-id: system-id }) err-not-found)))
        (ok (calculate-dynamic-rate system-id energy-kwh (get rate-per-kwh system)))
    )
)

(define-read-only (get-pricing-tier (system-id uint))
    (match (map-get? system-pricing { system-id: system-id })
        pricing-data (let ((demand (get current-demand pricing-data)))
            (ok (if (<= demand (get tier-1-threshold pricing-data))
                u1
                (if (<= demand (get tier-2-threshold pricing-data))
                    u2
                    u3
                )
            ))
        )
        err-pricing-not-found
    )
)

(define-read-only (is-peak-hours (current-block uint))
    (let ((hour-equivalent (mod current-block u144)))
        (or (< hour-equivalent u36) (> hour-equivalent u108))
    )
)

(define-read-only (get-global-demand-multiplier)
    (var-get demand-multiplier)
)
