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
(define-constant err-contract-paused (err u111))
(define-constant err-rate-limit-exceeded (err u112))
(define-constant err-overflow (err u113))
(define-constant err-invalid-input (err u114))
(define-constant err-self-interaction (err u115))

(define-constant max-prediction-weight u10000) ;; 100.00% with 2 decimal precision
(define-constant min-stake-amount u1000000) ;; 1 STX minimum stake
(define-constant max-stake-amount u100000000000) ;; 100,000 STX maximum stake per prediction
(define-constant base-voting-weight u100) ;; Base weight for new users
(define-constant rate-limit-blocks u10) ;; Minimum blocks between operations
(define-constant max-operations-per-block u5) ;; Maximum operations per user per block
(define-constant min-resolution-delay u144) ;; Minimum 1 day (144 blocks) before resolution
(define-constant min-prediction-duration u144) ;; Minimum 1 day for predictions
(define-constant max-prediction-duration u4320) ;; Maximum 30 days for predictions
(define-constant min-participants u3) ;; Minimum participants before resolution

;; data vars
(define-data-var market-counter uint u0)
(define-data-var decision-counter uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% with 2 decimal precision
(define-data-var max-platform-fee-rate uint u1000) ;; 10% maximum fee cap
(define-data-var contract-paused bool false)
(define-data-var emergency-shutdown bool false)
(define-data-var total-platform-fees uint u0)

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
    linked-decision: (optional uint),
    participant-count: uint,
    resolution-locked-until: uint
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

(define-map last-operation-block principal uint)
(define-map operations-per-block {user: principal, block: uint} uint)

;; Security helper functions
(define-private (check-not-paused)
  (begin
    (asserts! (not (var-get emergency-shutdown)) err-contract-paused)
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (ok true)
  )
)

(define-private (safe-add (a uint) (b uint))
  (let ((result (+ a b)))
    (asserts! (>= result a) err-overflow)
    (ok result)
  )
)

(define-private (safe-mul (a uint) (b uint))
  (let ((result (* a b)))
    (asserts! (or (is-eq b u0) (is-eq (/ result b) a)) err-overflow)
    (ok result)
  )
)

(define-private (check-rate-limit (user principal))
  (let (
    (current-block burn-block-height)
    (last-block (default-to u0 (map-get? last-operation-block user)))
    (ops-count (default-to u0 (map-get? operations-per-block {user: user, block: current-block})))
  )
    (asserts! 
      (or 
        (>= (- current-block last-block) rate-limit-blocks)
        (< ops-count max-operations-per-block)
      )
      err-rate-limit-exceeded
    )
    (map-set last-operation-block user current-block)
    (map-set operations-per-block {user: user, block: current-block} (+ ops-count u1))
    (ok true)
  )
)

(define-private (validate-string-not-empty-ascii (str (string-ascii 256)))
  (if (> (len str) u0)
    (ok true)
    err-invalid-input
  )
)

(define-private (validate-time-bounds (duration uint))
  (begin
    (asserts! (>= duration min-prediction-duration) err-invalid-params)
    (asserts! (<= duration max-prediction-duration) err-invalid-params)
    (ok true)
  )
)

(define-private (validate-stake-amount (amount uint))
  (begin
    (asserts! (>= amount min-stake-amount) err-invalid-params)
    (asserts! (<= amount max-stake-amount) err-invalid-params)
    (ok true)
  )
)

;; public functions

;; Pause/unpause contract (owner only)
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get emergency-shutdown)) err-contract-paused)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (emergency-shutdown-contract)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set emergency-shutdown true)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee (var-get max-platform-fee-rate)) err-invalid-params)
    (var-set platform-fee-rate new-fee)
    (ok true)
  )
)

(define-public (withdraw-platform-fees (amount uint))
  (let ((total-fees (var-get total-platform-fees)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= amount total-fees) err-insufficient-balance)
    (var-set total-platform-fees (- total-fees amount))
    (as-contract (stx-transfer? amount tx-sender contract-owner))
  )
)

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
      (market-id (unwrap! (safe-add (var-get market-counter) u1) err-overflow))
      (current-time burn-block-height)
      (prediction-end (unwrap! (safe-add current-time prediction-duration) err-overflow))
      (resolution-time (unwrap! (safe-add prediction-end resolution-delay) err-overflow))
    )
    (try! (check-not-paused))
    (try! (check-rate-limit tx-sender))
    (try! (validate-string-not-empty-ascii title))
    (try! (validate-string-not-empty-ascii category))
    (try! (validate-time-bounds prediction-duration))
    (asserts! (>= resolution-delay min-resolution-delay) err-invalid-params)
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
        linked-decision: none,
        participant-count: u0,
        resolution-locked-until: resolution-time
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
    (try! (check-not-paused))
    (try! (check-rate-limit tx-sender))
    (try! (validate-stake-amount stake-amount))
    (asserts! (>= user-balance stake-amount) err-insufficient-balance)
    (asserts! (<= burn-block-height (get prediction-end-time market)) err-prediction-period-ended)
    (asserts! (not (get resolved market)) err-market-resolved)
    (asserts! (not (is-eq tx-sender (get creator market))) err-self-interaction)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Update market totals and participant count if first prediction
    (let ((is-new-participant (is-none (map-get? market-positions { market-id: market-id, user: tx-sender }))))
      (if outcome
        (map-set markets
          { market-id: market-id }
          (merge market {
            total-stake: (unwrap! (safe-add (get total-stake market) stake-amount) err-overflow),
            outcome-a-stake: (unwrap! (safe-add (get outcome-a-stake market) stake-amount) err-overflow),
            participant-count: (if is-new-participant (+ (get participant-count market) u1) (get participant-count market))
          })
        )
        (map-set markets
          { market-id: market-id }
          (merge market {
            total-stake: (unwrap! (safe-add (get total-stake market) stake-amount) err-overflow),
            outcome-b-stake: (unwrap! (safe-add (get outcome-b-stake market) stake-amount) err-overflow),
            participant-count: (if is-new-participant (+ (get participant-count market) u1) (get participant-count market))
          })
        )
      )
    )
    
    ;; Update user position
    (if outcome
      (map-set market-positions
        { market-id: market-id, user: tx-sender }
        (merge current-position {
          outcome-a-stake: (unwrap! (safe-add (get outcome-a-stake current-position) stake-amount) err-overflow)
        })
      )
      (map-set market-positions
        { market-id: market-id, user: tx-sender }
        (merge current-position {
          outcome-b-stake: (unwrap! (safe-add (get outcome-b-stake current-position) stake-amount) err-overflow)
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
    (try! (check-not-paused))
    (asserts! (or (is-eq tx-sender contract-owner) (is-eq tx-sender (get creator market))) err-unauthorized)
    (asserts! (>= burn-block-height (get resolution-locked-until market)) err-invalid-params)
    (asserts! (not (get resolved market)) err-market-resolved)
    (asserts! (>= (get participant-count market) min-participants) err-invalid-params)
    
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
      (decision-id (unwrap! (safe-add (var-get decision-counter) u1) err-overflow))
      (current-time burn-block-height)
      (voting-end (unwrap! (safe-add current-time voting-duration) err-overflow))
    )
    (try! (check-not-paused))
    (try! (check-rate-limit tx-sender))
    (try! (validate-string-not-empty-ascii title))
    (try! (validate-string-not-empty-ascii category))
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
    (try! (check-not-paused))
    (try! (check-rate-limit tx-sender))
    (asserts! (not (is-eq tx-sender (get creator decision))) err-self-interaction)
    (asserts! (<= burn-block-height (get voting-end-time decision)) err-market-closed)
    (asserts! (not (get resolved decision)) err-market-resolved)
    (asserts! (is-none existing-vote) err-already-exists)
    
    ;; Record vote
    (map-set decision-votes
      { decision-id: decision-id, user: tx-sender }
      {
        vote: vote,
        weight: user-weight,
        timestamp: burn-block-height
      }
    )
    
    ;; Update decision totals
    (if vote
      (map-set decisions
        { decision-id: decision-id }
        (merge decision {
          total-weighted-votes: (unwrap! (safe-add (get total-weighted-votes decision) user-weight) err-overflow),
          yes-weighted-votes: (unwrap! (safe-add (get yes-weighted-votes decision) user-weight) err-overflow)
        })
      )
      (map-set decisions
        { decision-id: decision-id }
        (merge decision {
          total-weighted-votes: (unwrap! (safe-add (get total-weighted-votes decision) user-weight) err-overflow),
          no-weighted-votes: (unwrap! (safe-add (get no-weighted-votes decision) user-weight) err-overflow)
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
    (try! (check-not-paused))
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
        (platform-fee (unwrap! (safe-mul total-losing-stake (var-get platform-fee-rate)) err-overflow))
        (platform-fee-final (/ platform-fee u10000))
        (winnings-pool (- total-losing-stake platform-fee-final))
        (current-fees (var-get total-platform-fees))
        (user-share-calc (unwrap! (safe-mul winnings-pool user-winning-stake) err-overflow))
        (user-share (if (> total-winning-stake u0)
          (/ user-share-calc total-winning-stake)
          u0))
        (total-payout (unwrap! (safe-add user-winning-stake user-share) err-overflow))
      )
      (asserts! (> user-winning-stake u0) err-unauthorized)
      
      ;; Mark as claimed BEFORE transfer (reentrancy protection)
      (map-set market-positions
        { market-id: market-id, user: tx-sender }
        (merge position { claimed: true })
      )
      
      ;; Update user prediction scores
      (update-prediction-score tx-sender (get category market) market-id true)
      
      ;; Update platform fees
      (var-set total-platform-fees (unwrap! (safe-add current-fees platform-fee-final) err-overflow))
      
      ;; Transfer winnings
      (try! (as-contract (stx-transfer? total-payout tx-sender contract-caller)))
      (ok true)
    )
  )
)

;; User verification
(define-public (verify-user (user principal))
  (begin
    (try! (check-not-paused))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set user-verification
      { user: user }
      {
        verified: true,
        verification-time: burn-block-height,
        reputation-score: u1000 ;; Starting reputation
      }
    )
    (ok true)
  )
)


;; read only functions

(define-read-only (get-market (market-id uint))
  (map-get? markets { market-id: market-id })
)

(define-read-only (get-decision (decision-id uint))
  (map-get? decisions { decision-id: decision-id })
)

(define-read-only (get-user-position (market-id uint) (user principal))
  (map-get? market-positions { market-id: market-id, user: user })
)

(define-read-only (get-user-vote (decision-id uint) (user principal))
  (map-get? decision-votes { decision-id: decision-id, user: user })
)

(define-read-only (get-user-prediction-score (user principal) (category (string-ascii 64)))
  (map-get? user-prediction-scores { user: user, category: category })
)

(define-read-only (calculate-voting-weight (user principal) (category (string-ascii 64)))
  (let 
    (
      (base-weight base-voting-weight)
      (prediction-score (default-to 
        { total-predictions: u0, correct-predictions: u0, total-stake: u0, profit: 0, accuracy-score: u0 }
        (map-get? user-prediction-scores { user: user, category: category })
      ))
      (verification (map-get? user-verification { user: user }))
      (accuracy-multiplier (if (> (get total-predictions prediction-score) u0)
        (get accuracy-score prediction-score)
        u100)) ;; Default 1.0x multiplier
      (verification-bonus (if (and (is-some verification) (get verified (unwrap-panic verification)))
        u50 ;; 0.5x bonus for verified users
        u0))
    )
    (+ base-weight (/ (* base-weight (+ accuracy-multiplier verification-bonus)) u100))
  )
)

(define-read-only (get-market-odds (market-id uint))
  (let 
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) err-not-found))
      (total-stake (get total-stake market))
      (outcome-a-stake (get outcome-a-stake market))
      (outcome-b-stake (get outcome-b-stake market))
    )
    (if (> total-stake u0)
      (ok {
        outcome-a-probability: (/ (* outcome-a-stake u10000) total-stake),
        outcome-b-probability: (/ (* outcome-b-stake u10000) total-stake),
        total-stake: total-stake
      })
      (ok {
        outcome-a-probability: u5000,
        outcome-b-probability: u5000,
        total-stake: u0
      })
    )
  )
)

(define-read-only (get-decision-results (decision-id uint))
  (let 
    (
      (decision (unwrap! (map-get? decisions { decision-id: decision-id }) err-not-found))
      (total-votes (get total-weighted-votes decision))
      (yes-votes (get yes-weighted-votes decision))
      (no-votes (get no-weighted-votes decision))
    )
    (ok {
      yes-percentage: (if (> total-votes u0) (/ (* yes-votes u10000) total-votes) u0),
      no-percentage: (if (> total-votes u0) (/ (* no-votes u10000) total-votes) u0),
      total-weighted-votes: total-votes,
      resolved: (get resolved decision)
    })
  )
)

;; Security read-only functions
(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-last-operation-block (user principal))
  (default-to u0 (map-get? last-operation-block user))
)

(define-read-only (get-market-creator (market-id uint))
  (match (map-get? markets { market-id: market-id })
    market (some (get creator market))
    none
  )
)

(define-read-only (get-decision-creator (decision-id uint))
  (match (map-get? decisions { decision-id: decision-id })
    decision (some (get creator decision))
    none
  )
)

;; private functions

(define-private (update-prediction-score 
    (user principal) 
    (category (string-ascii 64))
    (market-id uint)
    (was-correct bool))
  (let 
    (
      (current-score (default-to 
        { total-predictions: u0, correct-predictions: u0, total-stake: u0, profit: 0, accuracy-score: u0 }
        (map-get? user-prediction-scores { user: user, category: category })
      ))
      (new-total (+ (get total-predictions current-score) u1))
      (new-correct (if was-correct 
        (+ (get correct-predictions current-score) u1)
        (get correct-predictions current-score)))
      (new-accuracy-calc (* new-correct u10000))
      (new-accuracy (if (> new-total u0)
        (/ new-accuracy-calc new-total)
        u0))
    )
    (map-set user-prediction-scores
      { user: user, category: category }
      (merge current-score {
        total-predictions: new-total,
        correct-predictions: new-correct,
        accuracy-score: new-accuracy
      })
    )
    true
  )
)