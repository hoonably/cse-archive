#lang racket

(require eopl)
(require "datatype.scm")
(require "type-environments.scm")
(require "utils.scm")
(require "parser.scm")

(provide type-of-program type-of)

;; type-of-program : Program * Env -> Type
(define type-of-program
  (lambda (pgm)
    (cases program pgm
      (a-program (exp)
                 (cases answer (type-of exp (empty-tenv) '())
                   (an-answer (ty subst)
                              (debug "obtained type: ~s, subst: ~s~n" ty subst)
                              (apply-subst-to-type ty subst)))))))
(define var-types->type
  (lambda (var-types)
    (map (lambda (var-type)
           (cases type var-type
             (int-type () (int-type))
             (bool-type () (bool-type))
             (tvar-type (id) (tvar-type id))
             (proc-type (arg-types result-type)
                        (proc-type (map var-types->type arg-types) (var-types->type result-type)))))
         var-types)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; You need to complete this function.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define type-of
  (lambda (exp tenv subst)
    (debug "type-inferring exp: ~s~n" exp)
    (cases expression exp
      (const-exp (num) (an-answer (int-type) subst))
      (var-exp (var)
               (an-answer (apply-tenv tenv var) subst))

      ; add와 diff는 같음
      (add-exp (exp1 exp2)
                (cases answer (type-of exp1 tenv subst)
                  (an-answer (type1 subst1)
                    (let ((subst1 
                            (unifier type1 (int-type) subst1 exp1)))
                      (cases answer (type-of exp2 tenv subst1)
                        (an-answer (type2 subst2)
                                  (let ((subst2
                                          (unifier type2 (int-type)
                                           subst2 exp2)))
                                    (an-answer (int-type) subst2))))))))
      (diff-exp (exp1 exp2)
                (cases answer (type-of exp1 tenv subst)
                  (an-answer (type1 subst1)
                    (let ((subst1 
                            (unifier type1 (int-type) subst1 exp1)))
                      (cases answer (type-of exp2 tenv subst1)
                        (an-answer (type2 subst2)
                                  (let ((subst2
                                          (unifier type2 (int-type)
                                           subst2 exp2)))
                                    (an-answer (int-type) subst2))))))))
      (zero?-exp (exp1)
                  (cases answer (type-of exp1 tenv subst)
                    (an-answer (type1 subst1)
                      (let ((subst2 
                              (unifier type1 (int-type) subst1 exp)))
                        (an-answer (bool-type) subst2)))))
      ; 마지막에 int만 bool로 바꿔주면 됨
      (less-than-exp (exp1 exp2)
                (cases answer (type-of exp1 tenv subst)
                  (an-answer (type1 subst1)
                    (let ((subst1 
                            (unifier type1 (int-type) subst1 exp1)))
                      (cases answer (type-of exp2 tenv subst1)
                        (an-answer (type2 subst2)
                                  (let ((subst2
                                          (unifier type2 (int-type)
                                           subst2 exp2)))
                                    (an-answer (bool-type) subst2))))))))
      (not-exp (exp1)
        (cases answer (type-of exp1 tenv subst)
          (an-answer (type1 subst1)
            (let ((subst2 (unifier type1 (bool-type) subst1 exp)))
              (an-answer (bool-type) subst2)))))
      (if-exp (exp1 exp2 exp3)
        (cases answer (type-of exp1 tenv subst)
          (an-answer (type1 subst1)
            (let ((subst1 
                    (unifier type1 (bool-type) subst1 exp1)))
              (cases answer (type-of exp2 tenv subst1)
                (an-answer (type2 subst2)
                  (cases answer (type-of exp3 tenv subst2)
                    (an-answer (type3 subst3)
                      (let ((subst3 
                              (unifier type2 type3 subst3 exp3)))
                        (an-answer type2 subst3))))))))))

      (lambda-exp (bound-vars var-types body)
            (let ((arg-type (var-types->type var-types)))  ; var-types->type 추가
              (cases answer (type-of body
                              (extend-tenv-list bound-vars arg-type tenv)
                              subst)
                (an-answer (body-type subst)
                  (an-answer 
                    (proc-type arg-type body-type)
                    subst)))))

      ; 시도 1
      ; (app-exp (rator rand)
      ;   (let ((result-type (fresh-tvar-type)))
      ;       (cases answer (type-of rator tenv subst)
      ;         (an-answer (rator-type subst)
      ;           (cases answer (type-of rand tenv subst)  ; (car rand)?
      ;             (an-answer (rand-type subst)
      ;               (let ((subst
      ;                       (unifier rator-type 
      ;                         (proc-type rand-type result-type)
      ;                         subst
      ;                         exp)))
      ;                 (an-answer result-type subst))))))))
      (app-exp (rator rand)
        (let ((result-type (fresh-tvar-type)))
          (cases answer (type-of rator tenv subst)
            (an-answer (rator-type subst1)
              (let loop ((rand-exps rand) (rand-types '()) (subst subst1))
                (if (null? rand-exps)
                    ; rand-exps가 null일 때 = '()
                    ;  cons를 사용하여 리스트를 누적할 경우, 리스트의 순서가 역전되기 때문에 올바른 순서를 유지하기 위해 reverse가 필요
                    (let ((subst2 (unifier rator-type 
                                          (proc-type (reverse rand-types) result-type) subst exp)))
                      (an-answer result-type subst2))
                    ; rand-exps가 null이 아닐 때 car 사용
                    (cases answer (type-of (car rand-exps) tenv subst)
                      (an-answer (rand-type subst2)
                        (loop (cdr rand-exps) (cons rand-type rand-types) subst2)))))))))

      ; let 교과서
      ; (let-exp (vars exp1 body)
      ;   (cases answer (type-of exp1 tenv subst)
      ;     (an-answer (type1 subst1)
      ;       (type-of body
      ;         (extend-tenv-list vars type1 tenv)
      ;         subst1))))
      (let-exp (vars exps body)
        (let loop ((exps exps) (types '()) (subst subst))
          (if (null? exps)
              ; exps가 null일 때 = '()
              (cases answer (type-of body (extend-tenv-list vars (reverse types) tenv) subst)
                (an-answer (body-type subst2)
                  (an-answer body-type subst2)))
              ; exps가 null이 아닐 때 car 사용
              (cases answer (type-of (car exps) tenv subst)
                (an-answer (exp-type subst1)
                  (loop (cdr exps) (cons exp-type types) subst1))))))

      ; (letrec-exp (result-types proc-names lambda-expressions body)
      ;   (let ((b-vars (map lambda-exp->bound-vars lambda-expressions)))
      ;     (let ((p-var-types (map lambda-exp->var-types lambda-expressions)))
      ;       (let ((b-body (map lambda-exp->body lambda-expressions)))
      ;         (let ((proc-types (map (lambda (var-types result-type)
      ;                                 (proc-type var-types result-type))
      ;                               p-var-types result-types)))
      ;           (let ((tenv-for-letrec-body
      ;                   (extend-tenv-list proc-names proc-types tenv)))
      ;             (cases answer (type-of b-body
      ;                             (extend-tenv-list b-vars p-var-types
      ;                               tenv-for-letrec-body)
      ;                             subst)
      ;               (an-answer (p-body-type subst)
      ;                 (let ((subst
      ;                         (unifier p-body-type result-types subst b-body)))
      ;                   (type-of body tenv-for-letrec-body subst))))))))))
      (letrec-exp (result-types proc-names lambda-expressions body)
        (let ((b-vars (apply append (map lambda-exp->bound-vars lambda-expressions))))
          (let ((p-var-types (apply append (map lambda-exp->var-types lambda-expressions))))
            (let ((b-body (map lambda-exp->body lambda-expressions)))
              (let ((proc-types (map (lambda (var-types result-type)
                                      (proc-type var-types result-type))
                                    (map lambda-exp->var-types lambda-expressions) result-types)))
                (let ((tenv-for-letrec-body
                      (extend-tenv-list proc-names proc-types tenv)))
                  (cases answer (type-of (car b-body)
                                  (extend-tenv-list b-vars p-var-types
                                                    tenv-for-letrec-body)
                                  subst)
                    (an-answer (p-body-type subst)
                      (let ((subst
                            (unifier p-body-type (car result-types) subst (car b-body))))
                        (type-of body tenv-for-letrec-body subst))))))))))

      (begin-exp (exps)
        (let loop ((exps exps) (subst subst))
          (if (null? exps)
              ; exps가 null일 때 = '()
              (an-answer (int-type) subst)
              ; exps가 null이 아닐 때
              (cases answer (type-of (car exps) tenv subst)
                (an-answer (type1 subst1)
                  (loop (cdr exps) subst1))))))

      (else (error (format "type-of: not implemented: ~s" exp))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; You need to complete this function.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define unifier
  (lambda (ty1 ty2 subst exp)
    (debug "unifying ~s and ~s~n" ty1 ty2)
    (let ((ty1 (apply-subst-to-type ty1 subst))
          (ty2 (apply-subst-to-type ty2 subst)))
      (cond
        ((equal? ty1 ty2)
         subst)

        ((tvar-type? ty1)
          (if (no-occurrence? ty1 ty2)
            (extend-subst subst ty1 ty2)
            (unification-failure ty1 ty2 exp)))

        ((tvar-type? ty2)
          (if (no-occurrence? ty2 ty1)
            (extend-subst subst ty2 ty1)
            (unification-failure ty1 ty2 exp)))
        
        ; ((and (proc-type? ty1) (proc-type? ty2))
        ;   (let ((subst2 (unifier
        ;                   (proc-type->arg-types ty1)
        ;                   (proc-type->arg-types ty2)
        ;                   subst exp)))
        ;     (let ((subst3 (unifier
        ;                     (proc-type->result-type ty1)
        ;                     (proc-type->result-type ty2)
        ;                     subst2 exp)))
        ;       subst3)))
        ((and (proc-type? ty1) (proc-type? ty2))
         (let ((arg-types1 (proc-type->arg-types ty1))
               (arg-types2 (proc-type->arg-types ty2))
               (result-type1 (proc-type->result-type ty1))
               (result-type2 (proc-type->result-type ty2)))
           (if (and (list? arg-types1) (list? arg-types2) (= (length arg-types1) (length arg-types2)))
               (let ((subst2 (foldl (lambda (arg-pair subst)
                                      (unifier (cdr arg-pair) (car arg-pair) subst exp))
                                    subst
                                    (map cons arg-types1 arg-types2))))
                 (unifier result-type1 result-type2 subst2 exp))
               (unification-failure ty1 ty2 exp))))

        (else (unification-failure ty1 ty2 exp))

        ))))
        
        

(define apply-subst-to-type
  (lambda (ty subst)
    (cases type ty
      (int-type () (int-type))
      (bool-type () (bool-type))
      (proc-type (arg-types result-type)
                 (proc-type
                  (map (lambda (arg-type)
                         (apply-subst-to-type arg-type subst))
                       arg-types)
                  (apply-subst-to-type result-type subst)))
      (tvar-type (id)
                 (let ((ty-val-pair (assoc ty subst)))
                   (if ty-val-pair
                       (cdr ty-val-pair)
                       ty))))))

;; apply-one-subst: type * tvar * type -> type
;; (apply-one-subst ty0 var ty1) returns the type obtained by
;; substituting ty1 for every occurrence of tvar in ty0.
(define apply-one-subst
  (lambda (ty0 tvar ty1)
    (cases type ty0
      (int-type () (int-type))
      (bool-type () (bool-type))
      (proc-type (arg-type result-type)
                 (proc-type
                  (map (lambda (arg-type)
                         (apply-one-subst arg-type tvar ty1))
                       arg-type)
                  (apply-one-subst result-type tvar ty1)))
      (tvar-type (id)
                 (if (equal? ty0 tvar) ty1 ty0)))))

(define extend-subst
  (lambda (subst tvar ty)
    (cons
     (cons tvar ty)
     (map
      (lambda (p)
        (let ((oldlhs (car p))
              (oldrhs (cdr p)))
          (cons
           oldlhs
           (apply-one-subst oldrhs tvar ty))))
      subst))))

(define no-occurrence?
  (lambda (tvar ty)
    (cases type ty
      (int-type () #t)
      (bool-type () #t)
      (proc-type (arg-types result-type)
                 (and
                  (foldl (lambda (arg-type acc)
                           (and acc (no-occurrence? tvar arg-type)))
                         #t
                         arg-types)
                  (no-occurrence? tvar result-type)))
      (tvar-type (id) (not (equal? tvar ty))))))

(define unification-failure
  (lambda (ty1 ty2 exp)
    (debug "unification failure in ~s: ~s (actual) != ~s (expected)"
           exp
           (pretty-print ty1)
           (pretty-print ty2))
    (error (format "unification failure: ~s (actual) != ~s (expected)"
                   (pretty-print ty1)
                   (pretty-print ty2)))))
