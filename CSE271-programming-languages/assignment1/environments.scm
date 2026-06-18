#lang racket

(require eopl)
(require "datatype.scm")

(provide apply-env)

(define apply-env
  (lambda (env search-var)
    (cases environment env
      (empty-env ()
                 (eopl:error 'apply-env "No binding for ~s" search-var))
      (extend-env (var val saved-env)
                  (if (eqv? search-var var)
                      val
                      (apply-env saved-env search-var)))
      (extend-env-rec (p-name proc-def saved-env)
                      (cases expression proc-def
                        (lambda-exp (bound-var body)
                                    (if (eqv? search-var p-name)
                                        (proc-val (procedure bound-var body env))
                                        (apply-env saved-env search-var)))
                        (else (eopl:error 'extend-env-rec "Unsupported expression: ~s" proc-def)))))))
