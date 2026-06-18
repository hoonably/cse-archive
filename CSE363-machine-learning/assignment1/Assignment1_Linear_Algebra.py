# Self-contained code: define A, B, C; check each requested product for
# dimension compatibility; if compatible, compute and print rounded to 3 decimals.

import numpy as np

# ----- Define matrices -----
A = np.array([[ 1.3443, -2.3342,  4.5461],
              [-2.3234,  3.4535, -5.6617]], dtype=float)   # 2x3

B = np.array([[ 2.3724,  4.5212],
              [ 3.4564,  6.7448],
              [ 1.2643, -2.3254]], dtype=float)            # 3x2

C = np.array([[-1.2373,  1.2334],
              [ 3.3122,  3.2122]], dtype=float)            # 2x2

# ----- Helper -----
def try_prod(name, X, Y, ndigits=3):
    left_shape, right_shape = X.shape, Y.shape
    compatible = X.shape[1] == Y.shape[0]
    print(f"\n{name}: {left_shape} x {right_shape}  -> ", end="")
    if not compatible:
        print("impossible (inner dims differ)")
        return None
    prod = X @ Y
    rounded = np.round(prod, ndigits)
    print(f"OK, result shape {rounded.shape}\n{rounded}")
    return rounded

# ----- Requested products -----
results = {}
results["CA"]        = try_prod("CA",         C,      A)
results["BC"]        = try_prod("BC",         B,      C)
results["B^T A"]     = try_prod("B^T A",      B.T,    A)
results["A^T C"]     = try_prod("A^T C",      A.T,    C)
results["(-A)^T C"]  = try_prod("(-A)^T C", (-A).T,   C)
results["B^T A^T"]   = try_prod("B^T A^T",    B.T,    A.T)
results["AC"]        = try_prod("AC",         A,      C)
results["CB"]        = try_prod("CB",         C,      B)

# If you also want to access the raw full-precision results programmatically,
# they are available in the 'results' dict (rounded versions where computed).
