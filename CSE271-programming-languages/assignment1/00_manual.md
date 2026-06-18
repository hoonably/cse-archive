# Assignment 1: Implementing an interpreter for a simple programming language

## Problem Description

Your task is to implement an interpreter for a simple programming language. The concrete syntax of the language is given below.

```
Program ::= Expression

Expression ::= Number
            | Identifier
            | (+ Expression Expression)                               ; Expression₁ + Expression₂
            | (- Expression₁ Expression₂)                             ; Expression₁ - Expression₂ 
            | (zero? Expression)                                      ; see zero?-exp of §3.2
            | (< Expression₁ Expression₂)                             ; true if Expression₁ < Expression₂; otherwise false
            | (not Expression)                                        ; true if Expression is false; otherwise false
            | (if Expression Expression Expression)                   ; see if-exp of §3.2
            | (lambda (Identifier) Expression)                        ; see proc-exp of §3.3
            | (Expression Expression)                                 ; see call-exp of §3.3
            | (let (Identifier Expression) Expression)                ; see let-exp of §3.2
            | (letrec (Identifier Identifier) Expression Expression)  ; see letrec-exp of §3.4
```

The meaning of each expression should be intuitively clear from the syntax. For most of the expressions, the meaning is the same as in the book. Note that while different concrete syntax is used in the textbook, the meaning of the expressions is the same.

### Set Up

- The following files are provided:
  - parser.scm: This file defines the `parse` function, which converts a string into an abstract syntax tree.
  - datatype.scm: This file defines all necessary data types.
  - environment.scm: This file defines the `apply-env` function.
  - interpreter.scm: This file defines the main logic of the interpreter.
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

### Tasks

Modify [interpreter.scm](./interpreter.scm) to implement the interpreter for the language described above. Do not modify any other files. A successful implementation should pass all the test cases in [run-tests.scm](./run-tests.scm).

### How to submit

Submit your interpreter.scm file via BlackBoard.

**Due: October 29, 2024; 11:59pm KST**