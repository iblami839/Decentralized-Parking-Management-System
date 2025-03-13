;; Space Registration Contract
;; Records available parking locations and their details

;; Data variables
(define-data-var space-counter uint u0)

;; Data maps
(define-map parking-spaces
{ id: uint }
{
  owner: principal,
  location: (string-ascii 64),
  description: (string-ascii 128),
  hourly-rate: uint,
  daily-rate: uint,
  available: bool,
  active: bool
}
)

(define-map space-admins
{ address: principal }
{ active: bool }
)

;; Initialize contract
(define-public (initialize)
(begin
  (map-set space-admins { address: tx-sender } { active: true })
  (ok true)
)
)

;; Check if address is admin
(define-read-only (is-admin (address principal))
(default-to false (get active (map-get? space-admins { address: address })))
)

;; Add an admin
(define-public (add-admin (address principal))
(begin
  ;; Only admins can add admins
  (asserts! (is-admin tx-sender) (err u403))

  (map-set space-admins
    { address: address }
    { active: true }
  )

  (ok true)
)
)

;; Register a parking space
(define-public (register-space
              (location (string-ascii 64))
              (description (string-ascii 128))
              (hourly-rate uint)
              (daily-rate uint))
(let ((new-id (+ (var-get space-counter) u1)))
  ;; Update counter
  (var-set space-counter new-id)

  ;; Store space data
  (map-set parking-spaces
    { id: new-id }
    {
      owner: tx-sender,
      location: location,
      description: description,
      hourly-rate: hourly-rate,
      daily-rate: daily-rate,
      available: true,
      active: true
    }
  )

  (ok new-id)
)
)

;; Update space details
(define-public (update-space
              (space-id uint)
              (description (string-ascii 128))
              (hourly-rate uint)
              (daily-rate uint))
(let ((space (map-get? parking-spaces { id: space-id })))

  ;; Space must exist
  (asserts! (is-some space) (err u404))

  ;; Only owner or admin can update
  (asserts! (or
              (is-eq tx-sender (get owner (unwrap-panic space)))
              (is-admin tx-sender))
            (err u403))

  ;; Store updated space
  (map-set parking-spaces
    { id: space-id }
    (merge (unwrap-panic space)
      {
        description: description,
        hourly-rate: hourly-rate,
        daily-rate: daily-rate
      }
    )
  )

  (ok true)
)
)

;; Update space availability
(define-public (set-availability (space-id uint) (available bool))
(let ((space (map-get? parking-spaces { id: space-id })))

  ;; Space must exist
  (asserts! (is-some space) (err u404))

  ;; Only owner or admin can update
  (asserts! (or
              (is-eq tx-sender (get owner (unwrap-panic space)))
              (is-admin tx-sender))
            (err u403))

  ;; Store updated space
  (map-set parking-spaces
    { id: space-id }
    (merge (unwrap-panic space) { available: available })
  )

  (ok true)
)
)

;; Deactivate a space
(define-public (deactivate-space (space-id uint))
(let ((space (map-get? parking-spaces { id: space-id })))

  ;; Space must exist
  (asserts! (is-some space) (err u404))

  ;; Only owner or admin can deactivate
  (asserts! (or
              (is-eq tx-sender (get owner (unwrap-panic space)))
              (is-admin tx-sender))
            (err u403))

  ;; Store updated space
  (map-set parking-spaces
    { id: space-id }
    (merge (unwrap-panic space) { active: false })
  )

  (ok true)
)
)

;; Get space details
(define-read-only (get-space (space-id uint))
(map-get? parking-spaces { id: space-id })
)

;; Check if space is available
(define-read-only (is-space-available (space-id uint))
(let ((space (map-get? parking-spaces { id: space-id })))
  (and
    (is-some space)
    (get available (unwrap-panic space))
    (get active (unwrap-panic space))
  )
)
)

;; Get hourly rate
(define-read-only (get-hourly-rate (space-id uint))
(default-to u0 (get hourly-rate (map-get? parking-spaces { id: space-id })))
)

;; Get daily rate
(define-read-only (get-daily-rate (space-id uint))
(default-to u0 (get daily-rate (map-get? parking-spaces { id: space-id })))
)

;; Get space owner
(define-read-only (get-space-owner (space-id uint))
(default-to tx-sender (get owner (map-get? parking-spaces { id: space-id })))
)

