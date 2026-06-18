#lang racket

(require "test-infra.scm")
(require "parser.scm")
(require "datatype.scm")
(require "utils.scm")

;;;;;;;;;;;;;;;; tests ;;;;;;;;;;;;;;;;

(define test-list
  '(
    ;; Format:
    ;; (test-name explicit-or-implicit-ref program environment expected-output)
    (const-exp-1 "11" 11)
    (const-exp-2 "-10" -10)
    (add-exp-1 "(+ 5 2)" 7)
    (diff-exp-1 "(- 10 4)" 6)
    (zero?-1 "(zero? 0)" #t)
    (zero?-2 "(zero? 1)" #f)
    (less-than-1 "(< 5 10)" #t)
    (less-than-2 "(< 11 6)" #f)
    (not-1 "(not (< 5 10))" #f)
    (not-2 "(not (< 11 6))" #t)
    (if-exp-1 "(if (zero? 0) 1 2)" 1)
    (if-exp-2 "(if (zero? 1) 1 2)" 2)
    (app-1 "((lambda (x) x) 3)" 3)
    (app-2 "((lambda (x) (+ x 1)) 3)" 4)
    (app-3 "((lambda (x) (- x 1)) 3)" 2)
    (app-4 "((lambda (x) (if (zero? x) (+ x 1) (- x 1))) 0)" 1)
    (app-4 "((lambda (x) (if (zero? x) (+ x 1) (- x 1))) 3)" 2)
    (let-1 "(let (x 3) x)" 3)
    (let-2 "(let (x 3) (+ x 2))" 5)
    (let-3 "(let (x 3) (let (y 2) (- x y)))" 1)
    (let-4 "(let (x 1) (let (x 10) (+ 5 x)))" 15)
    (let-5 "(let (x 3) (begin (let (y x) (set y 5)) x))" 3)
    (letref-1 "(let (x 3) (begin (letref (y x) (set y 5)) x))" 5)
    (proc-1 "(let (f (lambda (x) (+ x 1))) (f 4))" 5)
    (proc-2 "(let (f (lambda (x) (if (zero? x) 0 2))) (f 4))" 2)
    (proc-3 "(let (f (lambda (x) (if (zero? x) 0 (- x 1)))) (f 4))" 3)
    (proc-4 "(let (x 200) (let (f (lambda (z) (- z x))) (let (x 100) (let (g (lambda (z) (z x))) (g f)))))" -100)
    (proc-5 "(let (f (lambda (x) (lambda (y) (+ x y)))) ((f 3) 4))" 7)
    (proc-6 "(let (f (lambda (x) (set x 14))) (f (+ 2 1)))" 14)
    (proc-7 "(let (f (lambda (x) (set x 4))) (let (a 30) (begin (f a) a))))" 4)
    (proc-8 "(let (f (lambda (x) (set x 4))) (let (a 30) (begin (f (+ a 1)) a)))" 30)
    (proc-9 "(let (f (lambda (x) (set x (+ x 4)))) (let (a 30) (begin (f a) a))))" 34)
    (rec-proc-1 "(letrec ((f (lambda (x) (if (zero? x) 0 (+ 1 (f (- x 1))))))) (f 0))" 0)
    (rec-proc-2 "(letrec ((f (lambda (x) (if (zero? x) 0 (+ 1 (f (- x 1))))))) (f 1))" 1)
    (rec-proc-3 "(letrec ((f (lambda (x) (if (zero? x) 0 (+ 1 (f (- x 1))))))) (f 2))" 2)
    (rec-proc-4 "(letrec ((f (lambda (x) (if (zero? x) 0 (+ 10 (f (- x 1))))))) (f 2))" 20)
    (mut-rec-proc-1 "(letrec ((even (lambda (x) (if (zero? x) 1 (odd (- x 1))))) (odd (lambda (x) (if (zero? x) 0 (even (- x 1)))))) (odd 1))" 1)
    (mut-rec-proc-1 "(letrec ((even (lambda (x) (if (zero? x) 1 (odd (- x 1))))) (odd (lambda (x) (if (zero? x) 0 (even (- x 1)))))) (odd 2))" 0)
    (mut-rec-proc-1 "(letrec ((even (lambda (x) (if (zero? x) 1 (odd (- x 1))))) (odd (lambda (x) (if (zero? x) 0 (even (- x 1)))))) (even 2))" 1)
    (mut-rec-proc-1 "(letrec ((even (lambda (x) (if (zero? x) 1 (odd (- x 1))))) (odd (lambda (x) (if (zero? x) 0 (even (- x 1)))))) (even 3))" 0)
    (count-1 "(let (counter 0) (let (f (lambda (x) (let (counter (+ counter 1)) x))) (let (a (f (f 1))) counter)))" 0)
    (begin-1 "(begin 1 2 3)" 3)
    (begin-2 "(begin 1)" 1)
    (begin-3 "(begin)" "parse-exp: begin requires at least one argument")
    (implicit-1 "(let (x 1) (begin (set x 2) x))" 2)
    (implicit-2 "(let (x 1) (begin (set x 2) (set x 3) x))" 3)
    (implicit-3 "(let (x 1) (begin (set x (+ x 5)) x))" 6)
    ))

;; run : String -> ExpVal
(define run
  (lambda (string)
    (let ((ast (parse string)))
      (begin
        (debug "program: ~a~%" string)
        (debug "ast: ~a~%" ast)
        (let ((result (value-of-program ast (empty-env))))
          (debug "result: ~a~%" result)
          result)))))

(define run-all
  (lambda ()
    (run-tests! run equal-answer? test-list)))

(run-all)