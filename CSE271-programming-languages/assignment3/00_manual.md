# Assignment 3: Implementing type checking and type inference

## Problem Description

In this assignment, you will implement type checking and type inference.

### Tasks

You should be able to find the following three folders in the repository:

1. type-checking
2. type-inference

The `type-checking` folder contains the `checker.scm` file, and the `type-inference` folder contains the `inferencer.scm` file. You need to complete these files. As in the previous assignments, you should not modify any other files, and a successful implementation should pass all the test cases in `run-tests.scm`.

Each folder additionally contains the following files:

  - parser.scm: This file defines the `parse` function, which converts a string into an abstract syntax tree.
  - datatype.scm: This file defines all necessary data types.
  - type-environment.scm: This file defines the `apply-tenv` function.
  - run-tests.scm: This file contains test cases you need to pass. You can run the test cases by running this file. For example, you can run the test cases by executing the following command in the terminal:
    
    ```bash
    racket run-tests.scm
    ```

    You can also run the test cases in Visual Studio Code by using the Magic Racket extension. See this [video](https://www.youtube.com/watch?v=sK6yET1k_9A) for more information on how to run the test cases in Visual Studio Code.

  - test-infra.scm: This file defines functions used in `run-tests.scm`.
  - utils.scm: This file defines a `debug` function. Initially, the debug mode is turned off, as you can see in this file:
  
    ```scheme
    (define debug-mode #f)
    ```

    You can turn on the debug mode by changing `#f` to `#t`. In the debug mode, the interpreter will print debug information. 


The following shows the concrete syntax of the language:

```
Program ::= Expression

Expression ::= Number
            | Identifier
            | (+ Expression Expression)                                  ; Expression₁ + Expression₂
            | (- Expression₁ Expression₂)                                ; Expression₁ - Expression₂ 
            | (zero? Expression)                                         ; see zero?-exp of §3.2
            | (< Expression₁ Expression₂)                                ; true if Expression₁ < Expression₂; otherwise false
            | (not Expression)                                           ; true if Expression is false; otherwise false
            | (if Expression Expression Expression)                      ; see if-exp of §3.2
            | (lambda ((Identifier Type)+) Expression)                   ; multiple typed arguments are allowed
            | (Expression Expression)                                    ; should be handled differently depending on the parameter-passing mechanism
            | (let ((Identifier Expression)+) Expression)                ; multiple bindings are allowed
            | (letrec ((Identifier Expression)+) Expression Expression)  ; see Remark 1
            | (begin Expression+)                                        ; a sequence of expressions
```

The meaning of each expression should be intuitively clear from the syntax. For most of the expressions, the meaning is the same as in the book. Note that while different concrete syntax is used in the textbook, the meaning of the expressions is the same. 

Remark 1. The `letrec` expression contains a list of pairs of identifiers and expressions. Notation `(Identifier Expression)+` denotes N pairs of `(Identifier Expression)` where N >= 1. The following shows an example of the `letrec` expression where `even` and `odd` are mutually recursive functions:

```scheme
(letrec ((even (lambda (x) (if (zero? x) 1 (odd (- x 1)))))
         (odd (lambda (x) (if (zero? x) 0 (even (- x 1))))))
  (odd 1))
```

Simiarly, `let` and `lambda` expressions can have multiple elements, as shown in the following example:

```scheme
(let ((x 3) (y 2)) (- x y)) ; multiple bindings
(lambda ((x int) (y int)) (+ x y)) ; multiple typed arguments
```

### How to submit

1. Zip the following three files and name the zip file as `{StudentID}.zip` where `{StudentID}` should be your student ID:
   - checker.scm
   - inferrer.scm
2. Submit your zip file via BlackBoard.  

It is your responsibility to ensure that the zip file contains the correct files. If the zip file is corrupted or contains the wrong files, you will receive a grade of zero. You can test your zip file in the following link:

[https://www.ezyzip.com/unzip-files-online.html](https://www.ezyzip.com/unzip-files-online.html)

**Due: December 15, 2024; 11:59pm KST**