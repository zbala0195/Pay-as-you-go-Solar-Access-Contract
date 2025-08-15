(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-payment (err u103))
(define-constant err-inactive-system (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-amount (err u106))

(define-data-var next-system-id uint u1)
(define-data-var contract-fee uint u1000)

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
            (cost (* energy-kwh (get rate-per-kwh system)))
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

(define-read-only (get-total-systems)
    (- (var-get next-system-id) u1)
)
