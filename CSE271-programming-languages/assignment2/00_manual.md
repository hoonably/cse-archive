# Assignment 2: Implementing various parameter-passing mechanisms

## Problem Description

In this assignment, you will implement various parameter-passing mechanisms including explicit-reference, call-by-value, call-by-reference and call-by-name in our simple programming language.

### Tasks

You should be able to find the following three folders in the repository:

1. explicit-ref
2. call-by-val
3. call-by-ref
4. call-by-name

Each folder contains the following files:

  - parser.scm: This file defines the `parse` function, which converts a string into an abstract syntax tree.
  - datatype.scm: This file defines all necessary data types.
  - environment.scm: This file defines the `apply-env` function.
  - store.scm: This file contains the implementation of the store.
  - interpreter-XXX.scm: This file defines the main logic of the interpreter. XXX is identical with the folder name. For example, `explicit-ref` folder contains `interpreter-explicit-ref.scm`.
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

Your task is to complete the `interpreter-XXX.scm` file in each folder. You should not modify any other files. A successful implementation should pass all the test cases in `run-tests.scm` in the corresponding folder.

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
            | (lambda (Identifier) Expression)                           ; see proc-exp of §3.3
            | (Expression Expression)                                    ; should be handled differently depending on the parameter-passing mechanism
            | (let (Identifier Expression) Expression)                   ; see let-exp of §3.2
            | (letrec ((Identifier Expression)+) Expression Expression)  ; see Remark 1
            | (letref (Identifier Expression) Expression)                ; call-by-reference version of let
            | (begin Expression+)                                        ; a sequence of expressions
            | (newref Expression)                                        ; see newref-exp of §4.2.2
            | (deref Expression)                                         ; see deref-exp of §4.2.2
            | (setref Expression Expression)                             ; see setref-exp of §4.2.2
            | (set Identifier Expression)                                ; see assign-exp of §4.3
```

The meaning of each expression should be intuitively clear from the syntax. For most of the expressions, the meaning is the same as in the book. Note that while different concrete syntax is used in the textbook, the meaning of the expressions is the same. 

Remark 1. The `letrec` expression contains a list of pairs of identifiers and expressions. Notation `(Identifier Expression)+` denotes N pairs of `(Identifier Expression)` where N >= 1. The following shows an example of the `letrec` expression where `even` and `odd` are mutually recursive functions:

```scheme
(letrec ((even (lambda (x) (if (zero? x) 1 (odd (- x 1)))))
         (odd (lambda (x) (if (zero? x) 0 (even (- x 1))))))
  (odd 1))
```

### How to submit

1. Zip the following three files and name the zip file as `{StudentID}.zip` where `{StudentID}` should be your student ID:
   - interpreter-explicit-ref.scm
   - interpreter-call-by-val.scm
   - interpreter-call-by-ref.scm
   - interpreter-call-by-name.scm
2. Submit your zip file via BlackBoard.  

It is your responsibility to ensure that the zip file contains the correct files. If the zip file is corrupted or contains the wrong files, you will receive a grade of zero. You can test your zip file in the following link:

[https://www.ezyzip.com/unzip-files-online.html](https://www.ezyzip.com/unzip-files-online.html)

**Due: November 26, 2024; 11:59pm KST**