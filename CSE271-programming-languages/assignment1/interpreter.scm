;; CSE271 Principles of Programming Languages
;; 20201118 Jeonghoon Park
;; Assignment 1: Implementing an interpreter for a simple programming language
;; utils.scm에서 debug 함수를 사용할 수 있음.

#lang racket

(require eopl)
(require "datatype.scm")
(require "environments.scm")
(require "utils.scm")

(provide value-of-program value-of)

;; value-of-program : Program * Env -> ExpVal
(define value-of-program
  (lambda (pgm env)
    (cases program pgm
      (a-program (exp)
                 (value-of exp env)))))

;; apply-procedure (ppt 5-24)
(define apply-procedure
  (lambda (proc1 val)
    (cases proc proc1
      (procedure (var body saved-env)
        (value-of body (extend-env var val saved-env))))))

;; value-of : Exp * Env -> ExpVal
(define value-of
  (lambda (exp env)
    (debug "Evaluating exp: ~s, env: ~s~n" exp env)
    (cases expression exp
      (const-exp (num) (num-val num))

      ;; var-exp (ppt 3-28)
      (var-exp (var)
        (apply-env env var))

      ;; add-exp (ppt 3-32 + a)
      (add-exp (exp1 exp2)
          (let ((val1 (value-of exp1 env))
                (val2 (value-of exp2 env)))
            (let ((num1 (expval->num val1))
                  (num2 (expval->num val2)))
              (num-val (+ num1 num2)))))

      ;; diff-exp (ppt 3-32)
      (diff-exp (exp1 exp2)
          (let ((val1 (value-of exp1 env))
                (val2 (value-of exp2 env)))
            (let ((num1 (expval->num val1))
                  (num2 (expval->num val2)))
              (num-val (- num1 num2)))))

      ;; zero?-exp (ppt 4-5)
      (zero?-exp (exp)
        (let ((val (value-of exp env)))
          (let ((num (expval->num val)))
            (if (zero? num)
                (bool-val #t)
                (bool-val #f)))))

      ;; less-than-exp
      (less-than-exp (exp1 exp2)
          (let ((val1 (value-of exp1 env))
                (val2 (value-of exp2 env)))
            (let ((num1 (expval->num val1))
                  (num2 (expval->num val2)))
              (bool-val (< num1 num2)))))

      ;; not-exp
      (not-exp (exp)
        (let ((val (value-of exp env)))
          (let ((boolean (expval->bool val)))
            (bool-val (not boolean)))))  ;; use not
            ; (if boolean                ;; use if
            ;   (bool-val #f)
            ;   (bool-val #t)))))

      ;; if-exp (ppt 4-8)
      (if-exp (test then else)
        (let ((val1 (value-of test env)))
          (if (expval->bool val1)
              (value-of then env)
              (value-of else env))))

      ;; lambda-exp (ppt 5-23)
      (lambda-exp (bound-var body)
        (proc-val (procedure bound-var body env)))

      ;; app-exp (ppt 5-24)
      (app-exp (rator rand)
        (let ((proc (expval->proc (value-of rator env)))
              (arg (value-of rand env)))
          (apply-procedure proc arg)))

      ;; let-exp (ppt 3-37)
      (let-exp (var exp body)
        (let ((val (value-of exp env)))
          (value-of body
            (extend-env var val env))))

      ;; letrec-exp (ppt 6-14)
      (letrec-exp (proc-name lambda-expression body)
        (let ((new-env (extend-env-rec proc-name lambda-expression env)))
          (value-of body new-env)))      

      (else (error 'value-of "Unsupported expression: ~s" exp)))))


