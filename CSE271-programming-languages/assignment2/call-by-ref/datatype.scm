#lang racket

(require eopl)
(require "store.scm")

(provide (all-defined-out))

(define identifier? symbol?)

(define-datatype program program?
  (a-program
   (exp expression?)))

(define-datatype proc proc?
  (procedure
   (var identifier?)
   (body expression?)
   (saved-env environment?)))

(define-datatype expression expression?
  (const-exp
   (num number?))
  (var-exp (var identifier?))
  (add-exp
   (exp1 expression?)
   (exp2 expression?))
  (diff-exp
   (exp1 expression?)
   (exp2 expression?))
  (zero?-exp (exp expression?))
  (less-than-exp
   (exp1 expression?)
   (exp2 expression?))
  (not-exp (exp expression?))
  (if-exp
   (test expression?)
   (then expression?)
   (else expression?))
  (lambda-exp
   (bound-var identifier?)
   (body expression?))
  (let-exp
   (var identifier?)
   (exp expression?)
   (body expression?))
  (letref-exp
   (var identifier?)
   (exp expression?)
   (body expression?))
  (letrec-exp
   (proc-name (listof identifier?))
   (lambda-expression (listof expression?))
   (body expression?))
  (app-exp
   (rator expression?)
   (rand expression?))
  (begin-exp
    (exps (listof expression?)))
  (newref-exp
   (exp expression?))
  (deref-exp
   (exp expression?))
  (setref-exp
   (exp1 expression?)
   (exp2 expression?))
  (assign-exp
   (var identifier?)
   (exp expression?)))

(define-datatype expval expval?
  (num-val
   (num number?))
  (bool-val
   (boolean boolean?))
  (proc-val
   (proc proc?))
  (ref-val
   (ref reference?)))

(define-datatype environment environment?
  (empty-env)
  (extend-env
   (var identifier?)
   (val reference?)
   (env environment?))
  (extend-env-rec
   (proc-names (listof identifier?))
   (proc-defs (listof expression?))
   (saved-env environment?)))

;;;;;;;;;;;;;;
;; extractors
;;;;;;;;;;;;;;

;; expval->num : ExpVal -> Int
(define expval->num
  (lambda (v)
    (cases expval v
      (num-val (num) num)
      (else (expval-extractor-error 'num v)))))

;; expval->bool : ExpVal -> Bool
(define expval->bool
  (lambda (v)
    (cases expval v
      (bool-val (bool) bool)
      (else (expval-extractor-error 'bool v)))))

;; expval->proc : ExpVal -> Proc
(define expval->proc
  (lambda (v)
    (cases expval v
      (proc-val (proc) proc)
      (else (expval-extractor-error 'proc v)))))

(define expval->ref
  (lambda (v)
    (cases expval v
      (ref-val (ref) ref)
      (else (expval-extractor-error 'ref v)))))

(define expval-extractor-error
  (lambda (variant value)
    (error 'expval-extractors "Looking for a ~s, found ~s"
           variant value)))