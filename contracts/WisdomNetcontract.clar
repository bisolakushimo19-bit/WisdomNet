;; title: WisdomNet - Prediction-Assisted Decision Markets
;; version: 1.0.0
;; summary: A smart contract system for crowdsourced decision making weighted by prediction accuracy
;; description: Implements prediction markets linked to decision voting where voting power is determined by historical prediction accuracy on related topics

;; traits
(define-trait sip010-token
  (
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
  )
)

;; token definitions
(define-fungible-token wisdom-token)

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-params (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-market-closed (err u105))
(define-constant err-market-resolved (err u106))
(define-constant err-insufficient-balance (err u107))
(define-constant err-invalid-outcome (err u108))
(define-constant err-decision-active (err u109))
(define-constant err-prediction-period-ended (err u110))

(define-constant max-prediction-weight u10000) ;; 100.00% with 2 decimal precision
(define-constant min-stake-amount u1000000) ;; 1 STX minimum stake
(define-constant base-voting-weight u100) ;; Base weight for new users

;; data vars
(define-data-var market-counter uint u0)
(define-data-var decision-counter uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% with 2 decimal precision

;; data maps
(define-map markets
  { market-id: uint }
  {
    creator: principal,
    title: (string-ascii 256),
    description: (string-ascii 1024),
    category: (string-ascii 64),
    resolution-source: (string-ascii 256),
    creation-time: uint,
    prediction-end-time: uint,
    resolution-time: uint,
    total-stake: uint,
    outcome-a-stake: uint,
    outcome-b-stake: uint,
    resolved: bool,
    winning-outcome: (optional bool), ;; true for A, false for B
    linked-decision: (optional uint)
  }
)

(define-map market-positions
  { market-id: uint, user: principal }
  {
    outcome-a-stake: uint,
    outcome-b-stake: uint,
    claimed: bool
  }
)

(define-map decisions
  { decision-id: uint }
  {
    creator: principal,
    title: (string-ascii 256),
    description: (string-ascii 1024),
    category: (string-ascii 64),
    creation-time: uint,
    voting-end-time: uint,
    total-weighted-votes: uint,
    yes-weighted-votes: uint,
    no-weighted-votes: uint,
    resolved: bool,
    linked-markets: (list 10 uint)
  }
)

(define-map decision-votes
  { decision-id: uint, user: principal }
  {
    vote: bool, ;; true for yes, false for no
    weight: uint,
    timestamp: uint
  }
)

(define-map user-prediction-scores
  { user: principal, category: (string-ascii 64) }
  {
    total-predictions: uint,
    correct-predictions: uint,
    total-stake: uint,
    profit: int,
    accuracy-score: uint ;; calculated score with 2 decimal precision
  }
)

(define-map user-verification
  { user: principal }
  {
    verified: bool,
    verification-time: uint,
    reputation-score: uint
  }
)

;; public functions

;; Market creation and management
(define-public (create-prediction-market 
    (title (string-ascii 256))
    (description (string-ascii 1024))
    (category (string-ascii 64))
    (resolution-source (string-ascii 256))
    (prediction-duration uint)
    (resolution-delay uint))
  (let 
    (
      (market-id (+ (var-get market-counter) u1))
      (current-time block-height)
      (prediction-end (+ current-time prediction-duration))
      (resolution-time (+ prediction-end resolution-delay))
    )
    (asserts! (> prediction-duration u0) err-invalid-params)
    (asserts! (> resolution-delay u0) err-invalid-params)
    (asserts! (< (len title) u257) err-invalid-params)
    (asserts! (< (len description) u1025) err-invalid-params)
    
    (map-set markets
      { market-id: market-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        category: category,
        resolution-source: resolution-source,
        creation-time: current-time,
        prediction-end-time: prediction-end,
        resolution-time: resolution-time,
        total-stake: u0,
        outcome-a-stake: u0,
        outcome-b-stake: u0,
        resolved: false,
        winning-outcome: none,
        linked-decision: none
      }
    )
    
    (var-set market-counter market-id)
    (ok market-id)
  )
)

(define-public (place-prediction 
    (market-id uint)
    (outcome bool) ;; true for A, false for B
    (stake-amount uint))
  (let 
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) err-not-found))
      (current-position (default-to 
        { outcome-a-stake: u0, outcome-b-stake: u0, claimed: false }
        (map-get? market-positions { market-id: market-id, user: tx-sender })
      ))
      (user-balance (stx-get-balance tx-sender))
    )
    (asserts! (>= user-balance stake-amount) err-insufficient-balance)
    (asserts! (>= stake-amount min-stake-amount) err-invalid-params)
    (asserts! (<= block-height (get prediction-end-time market)) err-prediction-period-ended)
    (asserts! (not (get resolved market)) err-market-resolved)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Update market totals
    (if outcome
      (map-set markets
        { market-id: market-id }
        (merge market {
          total-stake: (+ (get total-stake market) stake-amount),
          outcome-a-stake: (+ (get outcome-a-stake market) stake-amount)
        })
      )
      (map-set markets
        { market-id: market-id }
        (merge market {
          total-stake: (+ (get total-stake market) stake-amount),
          outcome-b-stake: (+ (get outcome-b-stake market) stake-amount)
        })
      )
    )
    
    ;; Update user position
    (if outcome
      (map-set market-positions
        { market-id: market-id, user: tx-sender }
        (merge current-position {
          outcome-a-stake: (+ (get outcome-a-stake current-position) stake-amount)
        })
      )
      (map-set market-positions
        { market-id: market-id, user: tx-sender }
        (merge current-position {
          outcome-b-stake: (+ (get outcome-b-stake current-position) stake-amount)
        })
      )
    )
    
    (ok true)
  )
)

(define-public (resolve-market 
    (market-id uint)
    (winning-outcome bool))
  (let 
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) err-not-found))
    )
    (asserts! (or (is-eq tx-sender contract-owner) (is-eq tx-sender (get creator market))) err-unauthorized)
    (asserts! (>= block-height (get resolution-time market)) err-invalid-params)
    (asserts! (not (get resolved market)) err-market-resolved)
    
    (map-set markets
      { market-id: market-id }
      (merge market {
        resolved: true,
        winning-outcome: (some winning-outcome)
      })
    )
    
    (ok true)
  )
)

;; Decision creation and voting
(define-public (create-decision
    (title (string-ascii 256))
    (description (string-ascii 1024))
    (category (string-ascii 64))
    (voting-duration uint)
    (linked-markets (list 10 uint)))
  (let 
    (
      (decision-id (+ (var-get decision-counter) u1))
      (current-time block-height)
      (voting-end (+ current-time voting-duration))
    )
    (asserts! (> voting-duration u0) err-invalid-params)
    (asserts! (< (len title) u257) err-invalid-params)
    (asserts! (< (len description) u1025) err-invalid-params)
    
    (map-set decisions
      { decision-id: decision-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        category: category,
        creation-time: current-time,
        voting-end-time: voting-end,
        total-weighted-votes: u0,
        yes-weighted-votes: u0,
        no-weighted-votes: u0,
        resolved: false,
        linked-markets: linked-markets
      }
    )
    
    (var-set decision-counter decision-id)
    (ok decision-id)
  )
)

(define-public (cast-vote
    (decision-id uint)
    (vote bool)) ;; true for yes, false for no
  (let 
    (
      (decision (unwrap! (map-get? decisions { decision-id: decision-id }) err-not-found))
      (user-weight (calculate-voting-weight tx-sender (get category decision)))
      (existing-vote (map-get? decision-votes { decision-id: decision-id, user: tx-sender }))
    )
    (asserts! (<= block-height (get voting-end-time decision)) err-market-closed)
    (asserts! (not (get resolved decision)) err-market-resolved)
    (asserts! (is-none existing-vote) err-already-exists)
    
    ;; Record vote
    (map-set decision-votes
      { decision-id: decision-id, user: tx-sender }
      {
        vote: vote,
        weight: user-weight,
        timestamp: block-height
      }
    )
    
    ;; Update decision totals
    (if vote
      (map-set decisions
        { decision-id: decision-id }
        (merge decision {
          total-weighted-votes: (+ (get total-weighted-votes decision) user-weight),
          yes-weighted-votes: (+ (get yes-weighted-votes decision) user-weight)
        })
      )
      (map-set decisions
        { decision-id: decision-id }
        (merge decision {
          total-weighted-votes: (+ (get total-weighted-votes decision) user-weight),
          no-weighted-votes: (+ (get no-weighted-votes decision) user-weight)
        })
      )
    )
    
    (ok true)
  )
)

;; Claim winnings from resolved markets
(define-public (claim-winnings (market-id uint))
  (let 
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) err-not-found))
      (position (unwrap! (map-get? market-positions { market-id: market-id, user: tx-sender }) err-not-found))
      (winning-outcome (unwrap! (get winning-outcome market) err-market-closed))
    )
    (asserts! (get resolved market) err-market-closed)
    (asserts! (not (get claimed position)) err-already-exists)
    
    (let 
      (
        (user-winning-stake (if winning-outcome 
          (get outcome-a-stake position) 
          (get outcome-b-stake position)))
        (total-winning-stake (if winning-outcome 
          (get outcome-a-stake market) 
          (get outcome-b-stake market)))
        (total-losing-stake (if winning-outcome 
          (get outcome-b-stake market) 
          (get outcome-a-stake market)))
        (platform-fee (/ (* total-losing-stake (var-get platform-fee-rate)) u10000))
        (winnings-pool (- total-losing-stake platform-fee))
        (user-share (if (> total-winning-stake u0)
          (/ (* winnings-pool user-winning-stake) total-winning-stake)
          u0))
        (total-payout (+ user-winning-stake user-share))
      )
      (asserts! (> user-winning-stake u0) err-unauthorized)
      
      ;; Mark as claimed
      (map-set market-positions
        { market-id: market-id, user: tx-sender }
        (merge position { claimed: true })
      )
      
      ;; Update user prediction scores
      (update-prediction-score tx-sender (get category market) market-id true)
      
      ;; Transfer winnings
      (as-contract (stx-transfer? total-payout tx-sender tx-sender))
    )
  )
)

;; User verification
(define-public (verify-user (user principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set user-verification
      { user: user }
      {
        verified: true,
        verification-time: block-height,
        reputation-score: u1000 ;; Starting reputation
      }
    )
    (ok true)
  )
)
