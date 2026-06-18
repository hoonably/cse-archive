#lang racket

(require eopl)
(require "datatype.scm")
(require "type-environments.scm")
(require "utils.scm")

(provide type-of-program type-of)

;; type-of-program : Program * Env -> Type
(define type-of-program
  (lambda (pgm)
    (cases program pgm
      (a-program (exp)
                 (type-of exp (empty-tenv))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; You need to complete this function.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define type-of
  (lambda (exp tenv)
    (debug "type-checking exp: ~s~n" exp)
    (cases expression exp
      (const-exp (num) (int-type))
      (var-exp (var) (apply-tenv tenv var))
      (add-exp (exp1 exp2)
               (let ((ty1 (type-of exp1 tenv))
                     (ty2 (type-of exp2 tenv)))
                 (check-equal-type! ty1 (int-type) exp1)
                 (check-equal-type! ty2 (int-type) exp2)
                 (int-type)))
      (diff-exp (exp1 exp2)
                (let ((ty1 (type-of exp1 tenv))
                      (ty2 (type-of exp2 tenv)))
                  (check-equal-type! ty1 (int-type) exp1)
                  (check-equal-type! ty2 (int-type) exp2)
                  (int-type)))
      (zero?-exp (exp)
                 (let ((ty (type-of exp tenv)))
                   (check-equal-type! ty (int-type) exp)
                   (bool-type)))
      (less-than-exp (exp1 exp2)
                     (let ((ty1 (type-of exp1 tenv))
                           (ty2 (type-of exp2 tenv)))
                       (check-equal-type! ty1 (int-type) exp1)
                       (check-equal-type! ty2 (int-type) exp2)
                       (bool-type)))
      (not-exp (exp)
                (let ((ty (type-of exp tenv)))
                  (check-equal-type! ty (bool-type) exp)
                  (bool-type)))
      (if-exp (exp1 exp2 exp3)
              (let ((ty1 (type-of exp1 tenv))
                    (ty2 (type-of exp2 tenv))
                    (ty3 (type-of exp3 tenv)))
                (check-equal-type! ty1 (bool-type) exp1)
                (check-equal-type! ty2 ty3 exp3)
                ty2))
      (lambda-exp (bound-vars var-types body)
                  (let ((result-type 
                        (type-of body 
                          (extend-tenv-list bound-vars var-types tenv))))
                    (proc-type var-types result-type)))
      (app-exp (rator rand)
                (let ((rator-type (type-of rator tenv))
                      (rand-types (map (lambda (rand) (type-of rand tenv)) rand)))
                  (cases type rator-type
                    (proc-type (arg-types result-type)
                      (begin
                        (check-equal-type-list! rand-types arg-types rand)
                        result-type))
                    (else (error (format "rator-not-a-proc-type!" rator-type))))))

      ; 교재 코드
      ; (let-exp (vars exps body)
      ;          (let ((exps-type (type-of exps tenv)))
      ;            (type-of body 
      ;             (extend-tenv vars exps-type tenv))))
      (let-exp (vars exps body)
                (let ((exps-types (map (lambda (exp) (type-of exp tenv)) exps)))
                  (type-of body 
                    (extend-tenv-list vars exps-types tenv))))

      ; 교재 코드
      ; (letrec-exp (result-types proc-names lambda-expressions body)
      ;           (let (b-var (map (lambda (lambda-exp) lambda-exp->bound-vars) lambda-expressions))
      ;           (let (b-var-types (map (lambda (lambda-exp) lambda-exp->var-types) lambda-expressions))
      ;           (let (b-body (map (lambda (lambda-exp) lambda-exp->body) lambda-expressions))
      ;             (let ((tenv-for-letrec-body
      ;                     (extend-tenv proc-names
      ;                       (proc-type b-var-types result-types)
      ;                       tenv)))
      ;               (let ((p-body-type
      ;                       (type-of b-body 
      ;                         (extend-tenv b-var b-var-types
      ;                           tenv-for-letrec-body))))
      ;                 (check-equal-type! 
      ;                   p-body-type result-types lambda-expressions->body)
      ;                 (type-of body tenv-for-letrec-body)))))))
      
      (letrec-exp (result-types proc-names lambda-expressions body)
                    ; lambda-expressions에서 bound-vars, var-types, body를 추출
                    (let ((b-vars (map lambda-exp->bound-vars lambda-expressions)))
                      (let ((b-var-types (map lambda-exp->var-types lambda-expressions)))
                        (let ((b-body (map lambda-exp->body lambda-expressions)))
                          ; proc-types를 만들어서 tenv에 추가
                          (let ((proc-types (map (lambda (var-types result-type)
                                                  (proc-type var-types result-type))
                                                b-var-types result-types)))
                            (let ((tenv-for-letrec-body 
                                (extend-tenv-list proc-names proc-types tenv)))
                              (let ((p-body-type
                                    (type-of (car b-body)
                                              (extend-tenv-list (car b-vars) (car b-var-types)
                                                                tenv-for-letrec-body))))
                                (check-equal-type!
                                p-body-type (car result-types) (car b-body))
                                (type-of body tenv-for-letrec-body))))))))

      (begin-exp (exps)
                 (let loop ((exps exps))
                   (if (null? (cdr exps))
                       (type-of (car exps) tenv)
                       (begin
                         (type-of (car exps) tenv)
                         (loop (cdr exps))))))


      (else (error (format "type-of: not implemented: ~s" exp))))))

(define check-equal-type!
  (lambda (ty1 ty2 exp)
    (when (not (equal? ty1 ty2))
      (debug "type-error in ~s: ~s (actual) != ~s (expected)~n"
             exp (pretty-print ty1) (pretty-print ty2))
      (error (format "type-error: ~s (actual) != ~s (expected)"
                     (pretty-print ty1) (pretty-print ty2))))))

(define check-equal-type-list!
  (lambda (tys1 tys2 exps)
    (when (not (null? tys1))
      (begin
        (check-equal-type! (car tys1) (car tys2) (car exps))
        (check-equal-type-list! (cdr tys1) (cdr tys2) (cdr exps))))))

