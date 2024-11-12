;; Work Collaboration Smart Contract
;; Handles project management, task assignments, and payments between collaborators

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-PROJECT-NOT-FOUND (err u101))
(define-constant ERR-TASK-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATUS-UPDATE (err u103))
(define-constant ERR-INSUFFICIENT-PROJECT-FUNDS (err u104))
(define-constant ERR-DUPLICATE-PROJECT-ID (err u105))
(define-constant ERR-DUPLICATE-TASK-ID (err u106))

;; Data Maps
(define-map ProjectDetails
    { project-identifier: uint }
    {
        project-owner: principal,
        project-title: (string-ascii 50),
        project-description: (string-ascii 500),
        project-budget: uint,
        project-status: (string-ascii 20),
        project-creation-time: uint,
        project-team-members: (list 20 principal)
    }
)

(define-map TaskDetails
    { project-identifier: uint, task-identifier: uint }
    {
        task-assignee: principal,
        task-title: (string-ascii 50),
        task-description: (string-ascii 500),
        task-due-date: uint,
        task-payment-amount: uint,
        task-status: (string-ascii 20),
        task-creation-time: uint
    }
)

(define-map ProjectSequence
    { sequence-type: (string-ascii 10) }
    { current-sequence: uint }
)

(define-map TaskSequence
    { project-identifier: uint }
    { current-sequence: uint }
)

(define-map TeamMemberMetrics
    { team-member-address: principal }
    {
        completed-task-count: uint,
        total-earnings: uint,
        performance-rating: uint,
        rating-count: uint
    }
)

;; Private Functions
(define-private (verify-project-ownership (project-identifier uint) (requesting-address principal))
    (let ((project-data (unwrap! (map-get? ProjectDetails { project-identifier: project-identifier }) ERR-PROJECT-NOT-FOUND)))
        (is-eq (get project-owner project-data) requesting-address)
    )
)

(define-private (verify-team-membership (project-identifier uint) (requesting-address principal))
    (let ((project-data (unwrap! (map-get? ProjectDetails { project-identifier: project-identifier }) ERR-PROJECT-NOT-FOUND)))
        (or
            (is-eq (get project-owner project-data) requesting-address)
            (is-some (index-of (get project-team-members project-data) requesting-address))
        )
    )
)

(define-private (generate-project-identifier)
    (let ((sequence-data (default-to { current-sequence: u0 } (map-get? ProjectSequence { sequence-type: "projects" }))))
        (begin
            (map-set ProjectSequence { sequence-type: "projects" } { current-sequence: (+ (get current-sequence sequence-data) u1) })
            (get current-sequence sequence-data)
        )
    )
)

(define-private (generate-task-identifier (project-identifier uint))
    (let ((sequence-data (default-to { current-sequence: u0 } (map-get? TaskSequence { project-identifier: project-identifier }))))
        (begin
            (map-set TaskSequence { project-identifier: project-identifier } { current-sequence: (+ (get current-sequence sequence-data) u1) })
            (get current-sequence sequence-data)
        )
    )
)

;; Public Functions
(define-public (initialize-project (project-title (string-ascii 50)) (project-description (string-ascii 500)) (project-budget uint))
    (let
        (
            (project-identifier (generate-project-identifier))
            (project-creator tx-sender)
        )
        (begin
            (map-set ProjectDetails
                { project-identifier: project-identifier }
                {
                    project-owner: project-creator,
                    project-title: project-title,
                    project-description: project-description,
                    project-budget: project-budget,
                    project-status: "active",
                    project-creation-time: block-height,
                    project-team-members: (list)
                }
            )
            (ok project-identifier)
        )
    )
)

(define-public (register-team-member (project-identifier uint) (new-member-address principal))
    (let
        (
            (requesting-address tx-sender)
            (project-data (unwrap! (map-get? ProjectDetails { project-identifier: project-identifier }) ERR-PROJECT-NOT-FOUND))
        )
        (if (verify-project-ownership project-identifier requesting-address)
            (begin
                (map-set ProjectDetails
                    { project-identifier: project-identifier }
                    (merge project-data { project-team-members: (unwrap! (as-max-len? (append (get project-team-members project-data) new-member-address) u20) ERR-UNAUTHORIZED-ACCESS) })
                )
                (ok true)
            )
            ERR-UNAUTHORIZED-ACCESS
        )
    )
)

(define-public (create-task-assignment
    (project-identifier uint)
    (task-title (string-ascii 50))
    (task-description (string-ascii 500))
    (assigned-member principal)
    (task-deadline uint)
    (task-reward uint)
)
    (let
        (
            (requesting-address tx-sender)
            (task-identifier (generate-task-identifier project-identifier))
        )
        (if (verify-project-ownership project-identifier requesting-address)
            (begin
                (map-set TaskDetails
                    { project-identifier: project-identifier, task-identifier: task-identifier }
                    {
                        task-assignee: assigned-member,
                        task-title: task-title,
                        task-description: task-description,
                        task-due-date: task-deadline,
                        task-payment-amount: task-reward,
                        task-status: "pending",
                        task-creation-time: block-height
                    }
                )
                (ok task-identifier)
            )
            ERR-UNAUTHORIZED-ACCESS
        )
    )
)

(define-public (update-task-progress (project-identifier uint) (task-identifier uint) (new-task-status (string-ascii 20)))
    (let
        (
            (requesting-address tx-sender)
            (task-data (unwrap! (map-get? TaskDetails { project-identifier: project-identifier, task-identifier: task-identifier }) ERR-TASK-NOT-FOUND))
        )
        (if (or (verify-project-ownership project-identifier requesting-address) (is-eq (get task-assignee task-data) requesting-address))
            (begin
                (map-set TaskDetails
                    { project-identifier: project-identifier, task-identifier: task-identifier }
                    (merge task-data { task-status: new-task-status })
                )
                (ok true)
            )
            ERR-UNAUTHORIZED-ACCESS
        )
    )
)

(define-public (mark-task-completed (project-identifier uint) (task-identifier uint))
    (let
        (
            (requesting-address tx-sender)
            (task-data (unwrap! (map-get? TaskDetails { project-identifier: project-identifier, task-identifier: task-identifier }) ERR-TASK-NOT-FOUND))
            (project-data (unwrap! (map-get? ProjectDetails { project-identifier: project-identifier }) ERR-PROJECT-NOT-FOUND))
        )
        (if (and
                (is-eq (get task-assignee task-data) requesting-address)
                (is-eq (get task-status task-data) "pending")
            )
            (begin
                (try! (stx-transfer? (get task-payment-amount task-data) (get project-owner project-data) requesting-address))
                (map-set TaskDetails
                    { project-identifier: project-identifier, task-identifier: task-identifier }
                    (merge task-data { task-status: "completed" })
                )
                ;; Update team member metrics
                (let ((member-metrics (default-to
                        { completed-task-count: u0, total-earnings: u0, performance-rating: u0, rating-count: u0 }
                        (map-get? TeamMemberMetrics { team-member-address: requesting-address })
                    )))
                    (map-set TeamMemberMetrics
                        { team-member-address: requesting-address }
                        {
                            completed-task-count: (+ (get completed-task-count member-metrics) u1),
                            total-earnings: (+ (get total-earnings member-metrics) (get task-payment-amount task-data)),
                            performance-rating: (get performance-rating member-metrics),
                            rating-count: (get rating-count member-metrics)
                        }
                    )
                )
                (ok true)
            )
            ERR-UNAUTHORIZED-ACCESS
        )
    )
)

(define-public (submit-member-rating (rated-member principal) (rating-score uint))
    (if (and (>= rating-score u1) (<= rating-score u5))
        (let ((member-metrics (default-to
                { completed-task-count: u0, total-earnings: u0, performance-rating: u0, rating-count: u0 }
                (map-get? TeamMemberMetrics { team-member-address: rated-member })
            )))
            (map-set TeamMemberMetrics
                { team-member-address: rated-member }
                {
                    completed-task-count: (get completed-task-count member-metrics),
                    total-earnings: (get total-earnings member-metrics),
                    performance-rating: (/ (+ (* (get performance-rating member-metrics) (get rating-count member-metrics)) rating-score) (+ (get rating-count member-metrics) u1)),
                    rating-count: (+ (get rating-count member-metrics) u1)
                }
            )
            (ok true)
        )
        ERR-INVALID-STATUS-UPDATE
    )
)

;; Read-only Functions
(define-read-only (get-project-details (project-identifier uint))
    (map-get? ProjectDetails { project-identifier: project-identifier })
)

(define-read-only (get-task-details (project-identifier uint) (task-identifier uint))
    (map-get? TaskDetails { project-identifier: project-identifier, task-identifier: task-identifier })
)

(define-read-only (get-member-performance-metrics (team-member-address principal))
    (map-get? TeamMemberMetrics { team-member-address: team-member-address })
)

(define-read-only (verify-member-status (project-identifier uint) (member-address principal))
    (verify-team-membership project-identifier member-address)
)