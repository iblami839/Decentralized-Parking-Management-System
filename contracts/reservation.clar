;; Reservation Contract
;; Manages booking of parking spaces in advance

;; Data variables
(define-data-var reservation-counter uint u0)

;; Data maps
(define-map reservations
{ id: uint }
{
  space-id: uint,
  user: principal,
  start-time: uint,
  end-time: uint,
  status: (string-ascii 16),
  payment-id: uint
}
)

(define-map space-reservations
{ space-id: uint, time: uint }
{ reservation-id: uint }
)

(define-map reservation-admins
{ address: principal }
{ active: bool }
)

;; Initialize contract
(define-public (initialize)
(begin
  (map-set reservation-admins { address: tx-sender } { active: true })
  (ok true)
)
)

;; Check if address is admin
(define-read-only (is-admin (address principal))
(default-to false (get active (map-get? reservation-admins { address: address })))
)

;; Add an admin
(define-public (add-admin (address principal))
(begin
  ;; Only admins can add admins
  (asserts! (is-admin tx-sender) (err u403))

  (map-set reservation-admins
    { address: address }
    { active: true }
  )

  (ok true)
)
)

;; Create a reservation
(define-public (create-reservation
              (space-id uint)
              (start-time uint)
              (end-time uint))
(let ((new-id (+ (var-get reservation-counter) u1)))

  ;; Space must exist and be available
  (asserts! (is-space-available space-id) (err u404))

  ;; End time must be after start time
  (asserts! (> end-time start-time) (err u400))

  ;; Start time must be in the future
  (asserts! (> start-time block-height) (err u400))

  ;; Check for conflicting reservations
  (asserts! (not (has-conflict space-id start-time end-time)) (err u409))

  ;; Update counter
  (var-set reservation-counter new-id)

  ;; Store reservation data
  (map-set reservations
    { id: new-id }
    {
      space-id: space-id,
      user: tx-sender,
      start-time: start-time,
      end-time: end-time,
      status: "pending",
      payment-id: u0
    }
  )

  ;; Mark time slots as reserved
  (mark-time-slots space-id start-time end-time new-id)

  (ok new-id)
)
)

;; Mark time slots as reserved (helper function)
(define-private (mark-time-slots (space-id uint) (start-time uint) (end-time uint) (reservation-id uint))
(begin
  ;; In a real implementation, we would iterate through all hours
  ;; For simplicity, we just mark the start time
  (map-set space-reservations
    { space-id: space-id, time: start-time }
    { reservation-id: reservation-id }
  )

  true
)
)

;; Check for conflicting reservations (helper function)
(define-read-only (has-conflict (space-id uint) (start-time uint) (end-time uint))
(let ((existing (map-get? space-reservations { space-id: space-id, time: start-time })))
  ;; In a real implementation, we would check all hours between start and end
  ;; For simplicity, we just check the start time
  (is-some existing)
)
)

;; Confirm reservation after payment
(define-public (confirm-reservation (reservation-id uint) (payment-id uint))
(let ((reservation (map-get? reservations { id: reservation-id })))

  ;; Reservation must exist
  (asserts! (is-some reservation) (err u404))

  ;; Only payment processor can confirm
  (asserts! (or
              (is-payment-processor tx-sender)
              (is-admin tx-sender))
            (err u403))

  ;; Store updated reservation
  (map-set reservations
    { id: reservation-id }
    (merge (unwrap-panic reservation)
      {
        status: "confirmed",
        payment-id: payment-id
      }
    )
  )

  (ok true)
)
)

;; Cancel reservation
(define-public (cancel-reservation (reservation-id uint))
(let ((reservation (map-get? reservations { id: reservation-id })))

  ;; Reservation must exist
  (asserts! (is-some reservation) (err u404))

  ;; Only user or admin can cancel
  (asserts! (or
              (is-eq tx-sender (get user (unwrap-panic reservation)))
              (is-admin tx-sender))
            (err u403))

  ;; Cannot cancel if already checked in
  (asserts! (not (is-eq (get status (unwrap-panic reservation)) "checked-in")) (err u400))

  ;; Store updated reservation
  (map-set reservations
    { id: reservation-id }
    (merge (unwrap-panic reservation) { status: "cancelled" })
  )

  ;; Clear time slots
  (clear-time-slots
    (get space-id (unwrap-panic reservation))
    (get start-time (unwrap-panic reservation))
    (get end-time (unwrap-panic reservation))
  )

  (ok true)
)
)

;; Clear time slots (helper function)
(define-private (clear-time-slots (space-id uint) (start-time uint) (end-time uint))
(begin
  ;; In a real implementation, we would iterate through all hours
  ;; For simplicity, we just clear the start time
  (map-delete space-reservations { space-id: space-id, time: start-time })

  true
)
)

;; Check in
(define-public (check-in (reservation-id uint))
(let ((reservation (map-get? reservations { id: reservation-id })))

  ;; Reservation must exist
  (asserts! (is-some reservation) (err u404))

  ;; Only user can check in
  (asserts! (is-eq tx-sender (get user (unwrap-panic reservation))) (err u403))

  ;; Reservation must be confirmed
  (asserts! (is-eq (get status (unwrap-panic reservation)) "confirmed") (err u400))

  ;; Current time must be near start time
  (asserts! (>= block-height (- (get start-time (unwrap-panic reservation)) u144)) (err u400)) ;; Within ~1 day

  ;; Store updated reservation
  (map-set reservations
    { id: reservation-id }
    (merge (unwrap-panic reservation) { status: "checked-in" })
  )

  (ok true)
)
)

;; Check out
(define-public (check-out (reservation-id uint))
(let ((reservation (map-get? reservations { id: reservation-id })))

  ;; Reservation must exist
  (asserts! (is-some reservation) (err u404))

  ;; Only user can check out
  (asserts! (is-eq tx-sender (get user (unwrap-panic reservation))) (err u403))

  ;; Reservation must be checked in
  (asserts! (is-eq (get status (unwrap-panic reservation)) "checked-in") (err u400))

  ;; Store updated reservation
  (map-set reservations
    { id: reservation-id }
    (merge (unwrap-panic reservation) { status: "completed" })
  )

  ;; Clear time slots
  (clear-time-slots
    (get space-id (unwrap-panic reservation))
    (get start-time (unwrap-panic reservation))
    (get end-time (unwrap-panic reservation))
  )

  (ok true)
)
)

;; Get reservation details
(define-read-only (get-reservation (reservation-id uint))
(map-get? reservations { id: reservation-id })
)

;; Check if space is available at time
(define-read-only (is-time-available (space-id uint) (time uint))
(not (is-some (map-get? space-reservations { space-id: space-id, time: time })))
)

;; Check if reservation is active
(define-read-only (is-reservation-active (reservation-id uint))
(let ((reservation (map-get? reservations { id: reservation-id })))
  (and
    (is-some reservation)
    (or
      (is-eq (get status (unwrap-panic reservation)) "confirmed")
      (is-eq (get status (unwrap-panic reservation)) "checked-in")
    )
  )
)
)

;; Check if payment processor (placeholder - would be implemented in payment contract)
(define-read-only (is-payment-processor (address principal))
(is-admin address)
)

;; External function to check if space is available (from space registration contract)
(define-read-only (is-space-available (space-id uint))
true
)

