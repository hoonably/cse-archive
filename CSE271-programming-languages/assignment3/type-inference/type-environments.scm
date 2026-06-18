#lang racket

(require eopl)
(require "datatype.scm")
(require "utils.scm")

(provide apply-tenv)

(define apply-tenv
  (lambda (tenv search-var)
    ; (debug "search for ~s in ~s~n" search-var tenv)
    (cases type-environment tenv
      (empty-tenv ()
                  (error (format "No binding for ~s" search-var)))
      (extend-tenv (var typ saved-env)
                   (if (eqv? search-var var)
                       typ
                       (apply-tenv saved-env search-var)))
      (extend-tenv-list (vars var-types saved-env)
                        (let ((idx (index-of vars search-var)))
                          (if (eq? idx #f)
                              (apply-tenv saved-env search-var)
                              (list-ref var-types idx)))))))