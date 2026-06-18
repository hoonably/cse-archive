#lang racket

(define debug-mode #t)

(provide debug)

(define debug
  (lambda (msg . args)
    (if debug-mode
        (apply printf msg args)
        (void))))