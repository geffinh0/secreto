import os
import sys

# make `import db`, `import engine`, ... work when running `python -m unittest` from backend/
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.dont_write_bytecode = True
