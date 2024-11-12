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
(define-constant ERR-INVALID-INPUT (err u107))

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
    (match (map-get? ProjectDetails { project-identifier: project-identifier })
        project-data (is-eq (get project-owner project-data) requesting-address)
        false
    )
)

(define-private (verify-team-membership (project-identifier uint) (requesting-address principal))
    (match (map-get? ProjectDetails { project-identifier: project-identifier })
        project-data (or
            (is-eq (get project-owner project-data) requesting-address)
            (is-some (index-of (get project-team-members project-data) requesting-address))
        )
        false
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
    (match (map-get? ProjectDetails { project-identifier: project-identifier })
        project-data 
            (let ((sequence-data (default-to { current-sequence: u0 } (map-get? TaskSequence { project-identifier: project-identifier }))))
                (begin
                    (map-set TaskSequence { project-identifier: project-identifier } { current-sequence: (+ (get current-sequence sequence-data) u1) })
                    (ok (get current-sequence sequence-data))
                )
            )
        (err ERR-PROJECT-NOT-FOUND)
    )
)

;; Public Functions
(define-public (initialize-project (project-title (string-ascii 50)) (project-description (string-ascii 500)) (project-budget uint))
    (let
        (
            (project-identifier (generate-project-identifier))
            (project-creator tx-sender)
        )
        (if (and 
                (> (len project-title) u0)
                (> (len project-description) u0)
                (> project-budget u0)
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
            ERR-INVALID-INPUT
        )
    )
)

(define-public (register-team-member (project-identifier uint) (new-member-address principal))
    (let
        (
            (requesting-address tx-sender)
        )
        (match (map-get? ProjectDetails { project-identifier: project-identifier })
            project-data
                (if (is-eq (get project-owner project-data) requesting-address)
                    (if (is-some (index-of (get project-team-members project-data) new-member-address))
                        ERR-INVALID-INPUT
                        (begin
                            (map-set ProjectDetails
                                { project-identifier: project-identifier }
                                (merge project-data { project-team-members: (unwrap! (as-max-len? (append (get project-team-members project-data) new-member-address) u20) ERR-UNAUTHORIZED-ACCESS) })
                            )
                            (ok true)
                        )
                    )
                    ERR-UNAUTHORIZED-ACCESS
                )
            ERR-PROJECT-NOT-FOUND
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
        )
        (match (map-get? ProjectDetails { project-identifier: project-identifier })
            project-data
                (if (is-eq (get project-owner project-data) requesting-address)
                    (if (and 
                            (> (len task-title) u0)
                            (> (len task-description) u0)
                            (> task-deadline block-height)
                            (> task-reward u0)
                            (or
                                (is-eq assigned-member (get project-owner project-data))
                                (is-some (index-of (get project-team-members project-data) assigned-member))
                            )
                        )
                        (match (generate-task-identifier project-identifier)
                            task-identifier
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
                            error ERR-PROJECT-NOT-FOUND
                        )
                        ERR-INVALID-INPUT
                    )
                    ERR-UNAUTHORIZED-ACCESS
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

(define-public (update-task-progress (project-identifier uint) (task-identifier uint) (new-task-status (string-ascii 20)))
    (let
        (
            (requesting-address tx-sender)
        )
        (match (map-get? ProjectDetails { project-identifier: project-identifier })
            project-data
                (match (map-get? TaskDetails { project-identifier: project-identifier, task-identifier: task-identifier })
                    task-data
                        (if (or (is-eq (get project-owner project-data) requesting-address) (is-eq (get task-assignee task-data) requesting-address))
                            (if (> (len new-task-status) u0)
                                (begin
                                    (map-set TaskDetails
                                        { project-identifier: project-identifier, task-identifier: task-identifier }
                                        (merge task-data { task-status: new-task-status })
                                    )
                                    (ok true)
                                )
                                ERR-INVALID-INPUT
                            )
                            ERR-UNAUTHORIZED-ACCESS
                        )
                    ERR-TASK-NOT-FOUND
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

(define-public (mark-task-completed (project-identifier uint) (task-identifier uint))
    (let
        (
            (requesting-address tx-sender)
        )
        (match (map-get? ProjectDetails { project-identifier: project-identifier })
            project-data
                (match (map-get? TaskDetails { project-identifier: project-identifier, task-identifier: task-identifier })
                    task-data
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
                    ERR-TASK-NOT-FOUND
                )
            ERR-PROJECT-NOT-FOUND
        )
    )
)

(define-public (submit-member-rating (rated-member principal) (rating-score uint))
    (if (and 
            (>= rating-score u1) 
            (<= rating-score u5)
        )
        (let
            (
                (existing-metrics (default-to
                    { completed-task-count: u0, total-earnings: u0, performance-rating: u0, rating-count: u0 }
                    (map-get? TeamMemberMetrics { team-member-address: rated-member })
                ))
            )
            (map-set TeamMemberMetrics
                { team-member-address: rated-member }
                {
                    completed-task-count: (get completed-task-count existing-metrics),
                    total-earnings: (get total-earnings existing-metrics),
                    performance-rating: (/ (+ (* (get performance-rating existing-metrics) (get rating-count existing-metrics)) rating-score) (+ (get rating-count existing-metrics) u1)),
                    rating-count: (+ (get rating-count existing-metrics) u1)
                }
            )
            (ok true)
        )
        ERR-INVALID-INPUT
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