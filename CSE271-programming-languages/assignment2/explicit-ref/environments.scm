#lang racket

(require eopl)
(require "datatype.scm")
(require "utils.scm")

(provide apply-env)

(define apply-env
  (lambda (env search-var)
    (debug "searh for ~s in ~s~n" search-var env)
    (cases environment env
      (empty-env ()
                 (eopl:error 'apply-env "No binding for ~s" search-var))
      (extend-env (var val saved-env)
                  (if (eqv? search-var var)
                      val
                      (apply-env saved-env search-var)))
      (extend-env-rec (p-names proc-defs saved-env)
                      (let ((idx (index-of p-names search-var)))
                        (if (eq? idx #f)
                            (apply-env saved-env search-var)
                            (let ((proc-def (list-ref proc-defs idx)))
                              (cases expression proc-def
                                (lambda-exp (bound-var body)
                                            (proc-val (procedure bound-var body env)))
                                (else (eopl:error 'extend-env-rec "Unsupported expression: ~s" proc-def))))))))))
