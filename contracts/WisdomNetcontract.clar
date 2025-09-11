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