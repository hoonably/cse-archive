#lang racket

(require eopl)

(provide (all-defined-out))

(define identifier? symbol?)

(define-datatype program program?
  (a-program
   (exp expression?)))

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
   (bound-vars (listof identifier?))
   (var-types (listof type?))
   (body expression?))
  (let-exp
   (vars (listof identifier?))
   (exps (listof expression?))
   (body expression?))
  (letrec-exp
   (result-types (listof type?))
   (proc-names (listof identifier?))
   (lambda-expressions (listof expression?))
   (body expression?))
  (app-exp
   (rator expression?)
   (rand (listof expression?)))
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

(define-datatype type type?
  (int-type)
  (bool-type)
  (tvar-type (id number?)) ;; type variable with unique id
  (proc-type (arg-types (listof type?)) (result-type type?)))

(define-datatype type-environment type-environment?
  (empty-tenv)
  (extend-tenv
   (var identifier?)
   (typ type?)
   (env type-environment?))
  (extend-tenv-list ;; the type of n'th vars is the n'th type in typs
   (vars (listof identifier?))
   (typs (listof type?))
   (env type-environment?)))

(define-datatype answer answer?
  (an-answer
   (type type?)
   (subst list?)))

(define pretty-print
  (lambda (t)
    (if (type? t)
        (cases type t
          (int-type () 'int)
          (bool-type () 'bool)
          (proc-type (arg-types result-type)
                     (list (simplify (pretty-print (map pretty-print arg-types)))
                           '->
                           (pretty-print result-type)))
          (tvar-type (id) (string->symbol (format "tvar-~a" id))))
        t)))

(define simplify
  (lambda (lst)
    (if (eq? (length lst) 1)
        (car lst)
        lst)))

;;;;;;;;;;;;;;
;; extractors
;;;;;;;;;;;;;;

(define lambda-exp->bound-vars
  (lambda (e)
    (cases expression e
      (lambda-exp (bound-vars var-types body)
                  bound-vars)
      (else (error (format "lambda-exp->bound-vars: not a lambda-exp: ~s" e))))))

(define lambda-exp->var-types
  (lambda (e)
    (cases expression e
      (lambda-exp (bound-vars var-types body)
                  var-types)
      (else (error (format "lambda-exp->var-types: not a lambda-exp: ~s" e))))))

(define lambda-exp->body
  (lambda (e)
    (cases expression e
      (lambda-exp (bound-vars var-types body)
                  body)
      (else (error (format "lambda-exp->body: not a lambda-exp: ~s" e))))))

(define proc-type->arg-types
  (lambda (t)
    (cases type t
      (proc-type (arg-types result-type) arg-types)
      (else (error (format "proc-type->arg-types: not a proc-type: ~s" t))))))

(define proc-type->result-type
  (lambda (t)
    (cases type t
      (proc-type (arg-types result-type) result-type)
      (else (error (format "proc-type->result-type: not a proc-type: ~s" t))))))

;;;;;;;;;;;;;;
;; predicates
;;;;;;;;;;;;;;

(define tvar-type?
  (lambda (t)
    (cases type t
      (tvar-type (id) #t)
      (else #f))))

(define proc-type?
  (lambda (t)
    (cases type t
      (proc-type (arg-types result-type) #t)
      (else #f))))